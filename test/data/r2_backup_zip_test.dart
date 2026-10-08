import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';

/// 2026-10-08 使用者問：雲端存什麼，備份就該拿到一整包壓縮檔吧？
/// 備份改成列出雲端所有檔案、原封不動打包成 zip。
void main() {
  final files = {
    'diary.json': '[{"id":"1"}]',
    'trades.json': '[]',
    'yt_video_cache/UC123.json': '[{"videoId":"a"}]',
    'debts.json': '[{"name":"信貸 & 車貸"}]',
  };

  http.Client fakeR2() => MockClient((req) async {
    final q = req.url.queryParameters;
    if (q['list-type'] == '2') {
      // 分兩頁回，測 continuation token。
      final keys = files.keys.toList();
      final second = q['continuation-token'] == 'next';
      final page = second ? keys.sublist(2) : keys.sublist(0, 2);
      final contents = page
          .map(
            (k) =>
                '<Contents><Key>${k.replaceAll('&', '&amp;')}</Key></Contents>',
          )
          .join();
      return http.Response(
        '<ListBucketResult>$contents'
        '<IsTruncated>${second ? 'false' : 'true'}</IsTruncated>'
        '${second ? '' : '<NextContinuationToken>next</NextContinuationToken>'}'
        '</ListBucketResult>',
        200,
      );
    }
    final key = req.url.pathSegments.skip(1).join('/');
    final body = files[key];
    return body == null
        ? http.Response('', 404)
        : http.Response.bytes(utf8.encode(body), 200);
  });

  R2Client client() => R2Client(
    credentials: const R2Credentials(
      endpoint: 'https://acc.r2.cloudflarestorage.com',
      accessKeyId: 'k',
      secretAccessKey: 's',
    ),
    bucket: 'lume',
    httpClient: fakeR2(),
  );

  test('列出雲端所有檔案（會翻頁）', () async {
    expect(await client().listKeys(), files.keys.toList());
  });

  test('打包成 zip：每個檔案原封不動、路徑跟雲端一樣，加一份說明', () async {
    final r = await R2SyncService(client()).fetchBackupZip();
    expect(r.fileCount, files.length);
    final zip = ZipDecoder().decodeBytes(r.zip);
    for (final e in files.entries) {
      final f = zip.findFile(e.key);
      expect(f, isNotNull, reason: e.key);
      expect(utf8.decode(f!.content as List<int>), e.value);
    }
    expect(zip.findFile('_備份說明.txt'), isNotNull);
  });
}
