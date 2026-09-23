import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// R2 連線用的憑證。三個欄位對應設定頁輸入卡片的三個欄位（見
/// `design-history/雲端同步設計/01_簡潔卡片式.html`）：`endpoint` 是
/// 「Account ID / S3 API 網址」那格，貼的是完整網址（例如
/// `https://<account_id>.r2.cloudflarestorage.com`），不是只貼
/// account id 本身，少一道自己組字串的手續。
class R2Credentials {
  const R2Credentials({
    required this.endpoint,
    required this.accessKeyId,
    required this.secretAccessKey,
  });

  final String endpoint;
  final String accessKeyId;
  final String secretAccessKey;

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'accessKeyId': accessKeyId,
    'secretAccessKey': secretAccessKey,
  };

  factory R2Credentials.fromJson(Map<String, dynamic> json) => R2Credentials(
    endpoint: json['endpoint'] as String,
    accessKeyId: json['accessKeyId'] as String,
    secretAccessKey: json['secretAccessKey'] as String,
  );
}

class R2Exception implements Exception {
  R2Exception(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 直接對 Cloudflare R2 的 S3 相容 API 做請求，純前端、不用整包 AWS
/// SDK。R2 沒有「測試連線」這種 API，[headBucket] 是業界慣用的替代
/// 做法：打一個很輕量、沒有副作用的請求（`HEAD /`）去確認金鑰能不能
/// 通、bucket 存不存在——設定頁的「儲存並測試連線」會先呼叫這個，
/// 再實際寫一個測試檔驗證寫入權限（見 `r2_sync_service.dart`），兩個
/// 都過才算真的能同步（2026-09-23 使用者問「真的有這個 API 嗎」，
/// 答案是沒有專門的，這是組出來的慣用驗證流程）。
///
/// R2／S3 的請求要用 AWS SigV4 簽章，這個 class 自己刻簽章邏輯
/// （[_sign]），不是隨便加個 header 就能打——沒有官方 Dart SDK 支援
/// R2，社群套件也不夠成熟到值得為這麼一小塊功能整包引入。
class R2Client {
  R2Client({
    required this.credentials,
    required this.bucket,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final R2Credentials credentials;
  final String bucket;
  final http.Client _http;

  static const _region = 'auto';
  static const _service = 's3';

  Uri _uriFor(String key) {
    final base = Uri.parse(credentials.endpoint);
    final segments = [bucket, ...key.split('/').where((s) => s.isNotEmpty)];
    return base.replace(pathSegments: segments);
  }

  /// 確認 bucket 存不存在、金鑰讀得動——不代表寫入權限也沒問題，見
  /// class 說明。
  Future<void> headBucket() async {
    final uri = Uri.parse(credentials.endpoint).replace(pathSegments: [bucket]);
    final res = await _send('HEAD', uri, body: null);
    if (res.statusCode >= 300) {
      throw R2Exception(_errorMessage(res));
    }
  }

  Future<Uint8List?> getObject(String key) async {
    final res = await _send('GET', _uriFor(key), body: null);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 300) {
      throw R2Exception(_errorMessage(res));
    }
    return res.bodyBytes;
  }

  Future<void> putObject(
    String key,
    Uint8List body, {
    String contentType = 'application/json',
  }) async {
    final res = await _send(
      'PUT',
      _uriFor(key),
      body: body,
      extraHeaders: {'content-type': contentType},
    );
    if (res.statusCode >= 300) {
      throw R2Exception(_errorMessage(res));
    }
  }

  Future<void> deleteObject(String key) async {
    final res = await _send('DELETE', _uriFor(key), body: null);
    // R2 對已經不存在的 key 也回 204，不用特別處理 404。
    if (res.statusCode >= 300 && res.statusCode != 404) {
      throw R2Exception(_errorMessage(res));
    }
  }

  String _errorMessage(http.Response res) {
    if (res.statusCode == 403) return 'R2 拒絕存取，檢查金鑰是否正確、有沒有讀寫權限';
    if (res.statusCode == 404) return '找不到這個 bucket，檢查 Account ID／網址是否正確';
    return 'R2 回應錯誤（狀態碼 ${res.statusCode}）';
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Uint8List? body,
    Map<String, String> extraHeaders = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final payload = body ?? Uint8List(0);
    final payloadHash = sha256.convert(payload).toString();

    final headers = <String, String>{
      ...extraHeaders,
      'host': uri.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };

    final authorization = _sign(
      method: method,
      uri: uri,
      headers: headers,
      payloadHash: payloadHash,
      amzDate: amzDate,
      dateStamp: dateStamp,
    );

    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..headers['authorization'] = authorization;
    if (body != null) request.bodyBytes = body;

    final streamed = await _http.send(request);
    return http.Response.fromStream(streamed);
  }

  String _sign({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payloadHash,
    required String amzDate,
    required String dateStamp,
  }) {
    final sortedHeaderNames = headers.keys.map((h) => h.toLowerCase()).toList()
      ..sort();
    final canonicalHeaders = sortedHeaderNames
        .map((name) => '$name:${headers.entries.firstWhere((e) => e.key.toLowerCase() == name).value.trim()}\n')
        .join();
    final signedHeaders = sortedHeaderNames.join(';');

    final canonicalUri = uri.pathSegments.isEmpty
        ? '/'
        : '/${uri.pathSegments.map(_uriEncode).join('/')}';

    final canonicalRequest = [
      method,
      canonicalUri,
      '', // 沒有 query string 需要處理
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$_region/$_service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    return 'AWS4-HMAC-SHA256 '
        'Credential=${credentials.accessKeyId}/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';
  }

  List<int> _deriveSigningKey(String dateStamp) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4${credentials.secretAccessKey}'), dateStamp);
    final kRegion = hmac(kDate, _region);
    final kService = hmac(kRegion, _service);
    return hmac(kService, 'aws4_request');
  }

  String _amzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// AWS 的路徑編碼規則：unreserved 字元（A-Za-z0-9-_.~）不編碼，
  /// 其餘都要編碼——`Uri.encodeComponent` 對 `~` 的處理跟 AWS 要求的
  /// 不一樣，自己刻一個符合規格的版本，不然簽章會對不起來。
  String _uriEncode(String input) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(input)) {
      final char = String.fromCharCode(byte);
      if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(char)) {
        buffer.write(char);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }
}
