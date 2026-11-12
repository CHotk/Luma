import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/usdt_twd_rate_store.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// R2 連線出錯（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：403 金鑰錯、
/// 404 找不到 bucket、500 其他錯誤，每種請求都要丟出看得懂的錯；憑證存讀。
/// 也測 USDT 匯率同步（第一次、雲端比較新、本機比較新、時間一樣）。
void main() {
  R2Client client(int status) => R2Client(
    credentials: const R2Credentials(
      endpoint: 'https://acc.r2.cloudflarestorage.com',
      accessKeyId: 'k',
      secretAccessKey: 's',
    ),
    bucket: 'lume',
    httpClient: MockClient((_) async => http.Response('broken', status)),
  );

  test('憑證 JSON 來回不會變', () {
    const c = R2Credentials(
      endpoint: 'https://e',
      accessKeyId: 'a',
      secretAccessKey: 'b',
    );
    final back = R2Credentials.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.endpoint, 'https://e');
    expect(back.secretAccessKey, 'b');
    expect(R2Exception('x').toString(), 'x');
  });

  for (final (status, words) in [
    (403, '拒絕存取'),
    (404, '找不到這個 bucket'),
    (500, '狀態碼 500'),
  ]) {
    test('狀態碼 $status：每種請求都丟出「$words」', () async {
      final c = client(status);
      Future<void> expectErr(Future<Object?> Function() f) => expectLater(
        f(),
        throwsA(
          isA<R2Exception>().having(
            (e) => e.message,
            'message',
            contains(words),
          ),
        ),
      );
      await expectErr(c.headBucket);
      await expectErr(() => c.putObject('a.json', utf8.encode('{}')));
      await expectErr(c.listKeys);
      await expectErr(() => c.listEtags('p/'));
      if (status != 404) {
        // 404 對單一檔案是「沒有這個檔案」，不算錯。
        await expectErr(() => c.getObject('a.json'));
        await expectErr(() => c.getObjectWithEtag('a.json'));
        await expectErr(() => c.headObject('a.json'));
        await expectErr(() => c.deleteObject('a.json'));
      } else {
        expect(await c.getObject('a.json'), isNull);
        expect((await c.getObjectWithEtag('a.json')).bytes, isNull);
        expect(await c.headObject('a.json'), isNull);
        await c.deleteObject('a.json');
      }
    });
  }

  group('USDT 匯率同步', () {
    late Map<String, List<int>> bucket;
    R2SyncService service(_MemoryStore s) => R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: MockClient((req) async {
          final key = req.url.pathSegments.skip(1).join('/');
          String etag(List<int> b) => md5.convert(b).toString();
          final b = bucket[key];
          switch (req.method) {
            case 'GET':
              return b == null
                  ? http.Response('', 404)
                  : http.Response.bytes(
                      b,
                      200,
                      headers: {'etag': '"${etag(b)}"'},
                    );
            case 'HEAD':
              return b == null
                  ? http.Response('', 404)
                  : http.Response('', 200, headers: {'etag': '"${etag(b)}"'});
            case 'PUT':
              bucket[key] = req.bodyBytes;
              return http.Response(
                '',
                200,
                headers: {'etag': '"${etag(req.bodyBytes)}"'},
              );
          }
          return http.Response('', 400);
        }),
      ),
      s,
    );
    setUp(() => bucket = {});
    final t0 = DateTime(2026, 11, 1);

    test('兩邊都沒設定＝不做事；設定了＝上傳；別台拿到；比較新的贏；時間一樣不算', () async {
      final a = _MemoryStore(), b = _MemoryStore();
      expect(await service(a).syncUsdtTwdRate(UsdtTwdRateStore(a)), (
        downloaded: 0,
        uploaded: 0,
      ));
      await UsdtTwdRateStore(
        a,
      ).saveRecord(UsdtTwdRateRecord(rate: 31.5, updatedAt: t0));
      expect(
        (await service(a).syncUsdtTwdRate(UsdtTwdRateStore(a))).uploaded,
        1,
      );
      expect(
        (await service(b).syncUsdtTwdRate(UsdtTwdRateStore(b))).downloaded,
        1,
      );
      expect(await UsdtTwdRateStore(b).load(), 31.5);
      await UsdtTwdRateStore(b).saveRecord(
        UsdtTwdRateRecord(
          rate: 33,
          updatedAt: t0.add(const Duration(hours: 1)),
        ),
      );
      expect(
        (await service(b).syncUsdtTwdRate(UsdtTwdRateStore(b))).uploaded,
        1,
      );
      expect(
        (await service(a).syncUsdtTwdRate(UsdtTwdRateStore(a))).downloaded,
        1,
      );
      expect(await UsdtTwdRateStore(a).load(), 33);
      final c = _MemoryStore();
      await UsdtTwdRateStore(c).saveRecord(
        UsdtTwdRateRecord(
          rate: 33,
          updatedAt: t0.add(const Duration(hours: 1)),
        ),
      );
      expect(await service(c).syncUsdtTwdRate(UsdtTwdRateStore(c)), (
        downloaded: 0,
        uploaded: 0,
      ));
    });
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}
