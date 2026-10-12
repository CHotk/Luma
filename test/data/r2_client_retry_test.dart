import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';

/// 2026-10-12 使用者在 iPhone 同步，一個檔「Load failed」整項失敗：網路
/// 瞬斷要自動重試，連續失敗才放棄。
void main() {
  setUp(() => R2Client.retryDelayForTest = Duration.zero);

  R2Client client(http.Client c) => R2Client(
    credentials: const R2Credentials(
      endpoint: 'https://acc.r2.cloudflarestorage.com',
      accessKeyId: 'k',
      secretAccessKey: 's',
    ),
    bucket: 'lume',
    httpClient: c,
  );

  test('斷線兩次、第三次成功：照樣上傳成功', () async {
    var calls = 0;
    final c = client(
      MockClient((req) async {
        calls++;
        if (calls < 3) throw http.ClientException('Load failed', req.url);
        expect(req.bodyBytes, [1, 2, 3]);
        return http.Response('', 200, headers: {'etag': '"abc"'});
      }),
    );
    expect(await c.putObject('a.json', Uint8List.fromList([1, 2, 3])), 'abc');
    expect(calls, 3);
  });

  test('R2 暫時 503 也重試', () async {
    var calls = 0;
    final c = client(
      MockClient((req) async {
        calls++;
        return calls == 1
            ? http.Response('busy', 503)
            : http.Response.bytes([9], 200, headers: {'etag': '"e"'});
      }),
    );
    expect(await c.getObject('a.json'), [9]);
    expect(calls, 2);
  });

  test('一直斷線：試 3 次就放棄，把錯誤丟出來', () async {
    var calls = 0;
    final c = client(
      MockClient((req) async {
        calls++;
        throw http.ClientException('Load failed', req.url);
      }),
    );
    await expectLater(
      c.getObject('a.json'),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 3);
  });
}
