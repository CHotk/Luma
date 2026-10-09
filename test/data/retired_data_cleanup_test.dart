import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/data/storage/retired_data_cleanup.dart';

/// 2026-10-10 使用者要求：看盤次數整個移除之後，舊資料也要刪掉——本機的
/// `crypto_watch.*` 開機時刪，雲端的 `crypto_watch.json` 同步時刪。
void main() {
  test('開機清掉看盤舊資料，其他功能的資料不動，重複跑也沒事', () async {
    final store = _ListableStore()
      ..data.addAll({
        'crypto_watch.entries.v1': '[{"id":"1"}]',
        'crypto_watch.something_else': 'x',
        'r2_sync.meta.crypto_watch.json': '{}',
        'trade_log.trades.v1': '[]',
        'smoking.entries.v1': '[]',
        'r2_sync.meta.trades.json': '{}',
      });
    expect(await removeRetiredLocalData(store), 3);
    expect(
      store.data.keys,
      unorderedEquals([
        'trade_log.trades.v1',
        'smoking.entries.v1',
        'r2_sync.meta.trades.json',
      ]),
    );
    expect(await removeRetiredLocalData(store), 0);
  });

  test('列不出全部 key 的儲存後端，已知的 key 照樣刪得到', () async {
    final store = _PlainStore()
      ..data['crypto_watch.entries.v1'] = '[]'
      ..data['diary.entries.v1'] = '[]';
    expect(await removeRetiredLocalData(store), 1);
    expect(store.data.keys, ['diary.entries.v1']);
  });

  test('同步時刪掉雲端的 crypto_watch.json，同一台只刪一次', () async {
    final bucket = <String, List<int>>{
      'crypto_watch.json': [1, 2, 3],
      'trades.json': [4],
    };
    var deletes = 0;
    final client = MockClient((req) async {
      final key = req.url.pathSegments.skip(1).join('/');
      if (req.method == 'DELETE') {
        deletes++;
        bucket.remove(key);
        return http.Response('', 204);
      }
      final b = bucket[key];
      return b == null
          ? http.Response('', 404)
          : http.Response.bytes(
              b,
              200,
              headers: {'etag': '"${md5.convert(b)}"'},
            );
    });
    final meta = _PlainStore()..data['r2_sync.meta.crypto_watch.json'] = '{}';
    final service = R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: client,
      ),
      meta,
    );

    await service.deleteRetiredCloudFiles();
    expect(bucket.keys, ['trades.json']);
    expect(meta.data.containsKey('r2_sync.meta.crypto_watch.json'), isFalse);
    await service.deleteRetiredCloudFiles();
    expect(deletes, 1);
  });
}

class _PlainStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

class _ListableStore extends _PlainStore implements ListableKeyValueStore {
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}
