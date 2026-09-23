import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
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
/// SDK——但簽章邏輯用 AWS 官方（Amplify Flutter 團隊）維護的
/// `package:aws_signature_v4`，不是自己手刻（2026-09-23 使用者問
/// 「應該自己刻嗎」，確認有現成、AWS 自己在用的實作後換成這個，理由是
/// 簽章這種東西編碼規則錯一個字元就整個失敗，手刻的版本沒有真的 R2
/// 帳號沒辦法驗證對不對，風險比用現成套件高很多）。
///
/// R2 沒有「測試連線」這種 API，[headBucket] 是業界慣用的替代做法：
/// 打一個很輕量、沒有副作用的請求（`HEAD /`）去確認金鑰能不能通、
/// bucket 存不存在——設定頁的「儲存並測試連線」會先呼叫這個，再實際
/// 寫一個測試檔驗證寫入權限（見 `r2_sync_service.dart`），兩個都過
/// 才算真的能同步。
class R2Client {
  R2Client({
    required this.credentials,
    required this.bucket,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client(),
       _signer = AWSSigV4Signer(
         credentialsProvider: AWSCredentialsProvider(
           AWSCredentials(credentials.accessKeyId, credentials.secretAccessKey),
         ),
       );

  final R2Credentials credentials;
  final String bucket;
  final http.Client _http;
  final AWSSigV4Signer _signer;

  // R2 的 SigV4 簽章固定用 "auto" 當 region，不是真的 AWS 區域代碼
  // ——這是 Cloudflare 文件明講的規則。
  static const _region = 'auto';

  Uri _uriFor(String key) {
    final base = Uri.parse(credentials.endpoint);
    final segments = [bucket, ...key.split('/').where((s) => s.isNotEmpty)];
    return base.replace(pathSegments: segments);
  }

  /// 確認 bucket 存不存在、金鑰讀得動——不代表寫入權限也沒問題，見
  /// class 說明。
  Future<void> headBucket() async {
    final uri = Uri.parse(credentials.endpoint).replace(pathSegments: [bucket]);
    final res = await _send(AWSHttpRequest.head(uri));
    if (res.statusCode >= 300) {
      throw R2Exception(_errorMessage(res));
    }
  }

  Future<Uint8List?> getObject(String key) async {
    final res = await _send(AWSHttpRequest.get(_uriFor(key)));
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
      AWSHttpRequest.put(
        _uriFor(key),
        body: body,
        headers: {'content-type': contentType},
      ),
    );
    if (res.statusCode >= 300) {
      throw R2Exception(_errorMessage(res));
    }
  }

  Future<void> deleteObject(String key) async {
    final res = await _send(AWSHttpRequest.delete(_uriFor(key)));
    // R2 對已經不存在的 key 也回 204，不用特別處理 404。
    if (res.statusCode >= 300 && res.statusCode != 404) {
      throw R2Exception(_errorMessage(res));
    }
  }

  String _errorMessage(http.Response res) {
    if (res.statusCode == 403) return 'R2 拒絕存取，檢查金鑰是否正確、有沒有讀寫權限';
    if (res.statusCode == 404) return '找不到這個 bucket，檢查 Account ID／網址是否正確';
    return 'R2 回應錯誤（狀態碼 ${res.statusCode}）：${res.body}';
  }

  Future<http.Response> _send(AWSHttpRequest request) async {
    final signed = await _signer.sign(
      request,
      credentialScope: AWSCredentialScope(region: _region, service: AWSService.s3),
      serviceConfiguration: S3ServiceConfiguration(),
    );
    final bytes = await signed.bodyBytes;
    final httpRequest = http.Request(signed.method.value, signed.uri)
      ..headers.addAll(signed.headers);
    if (bytes.isNotEmpty) httpRequest.bodyBytes = bytes;

    final streamed = await _http.send(httpRequest);
    return http.Response.fromStream(streamed);
  }
}
