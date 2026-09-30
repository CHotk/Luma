// 2026-09-30 使用者回報：把頻道分類刪除，點「立即同步」之後，被刪除的
// 分類又跑回來了。這份測試用假的 HTTP client 模擬 R2（不打真的網路），
// 照使用者描述的順序重現：
//   1. 裝置已經同步過一次（雲端、本機、meta 記錄都對齊，分類還在）。
//   2. 使用者刪除分類（墓碑標記）。
//   3. 再按一次「立即同步」。
// 目前這兩種情境都測不出問題（[R2SyncService.mergeCategoriesFromCloud]／
// [YtTrackerRepository.mergeSeedCategories] 的「刪除永遠贏」邏輯是對的），
// 保留下來當永久的迴歸測試；使用者回報的情境可能需要兩台裝置或特定
// 時間點才會踩到，還沒重現出來。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  test('刪除分類之後再同步一次，分類不會復活', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);
    final fakeHttp = _FakeR2Http();
    final client = R2Client(
      credentials: const R2Credentials(
        endpoint: 'https://example.r2.cloudflarestorage.com',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
      ),
      bucket: 'test-bucket',
      httpClient: fakeHttp,
    );
    final service = R2SyncService(client, store);

    // 1. 建一個分類，第一次同步（雲端、本機、meta 都對齊）。
    await repo.addCategory(
      const YtCategory(id: 'seed-food', name: '美食/料理', colorValue: 0xFF000000),
    );
    await service.syncYtTracker(repo);
    expect(
      (await repo.loadCategories()).map((c) => c.id),
      contains('seed-food'),
    );

    // 2. 使用者刪除這個分類。
    await repo.deleteCategory('seed-food');
    expect(
      (await repo.loadCategories()).map((c) => c.id),
      isNot(contains('seed-food')),
      reason: '本機刪除後、還沒同步前，分類就該是不見的',
    );

    // 3. 再按一次「立即同步」。
    await service.syncYtTracker(repo);

    final after = await repo.loadCategories();
    expect(
      after.map((c) => c.id),
      isNot(contains('seed-food')),
      reason: '同步完分類應該還是刪除狀態，不該復活',
    );
  });

  test('刪除分類之後，重新進首頁（會跑 mergeSeedCategories）分類也不該復活', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);

    await repo.addCategory(
      const YtCategory(id: 'seed-food', name: '美食/料理', colorValue: 0xFF000000),
    );
    await repo.deleteCategory('seed-food');

    // 模擬 yt_tracker_home_page.dart 的 _load()：每次打開首頁都會把
    // 專案內建的快照併回本機。快照裡的 seed-food 是活的（deletedAt跟
    // updatedAt 都是 null），跟使用者實際打包進 App 的 JSON 資料一樣。
    await repo.mergeSeedCategories([
      const YtCategory(id: 'seed-food', name: '美食/料理', colorValue: 0xFF000000),
    ]);

    final after = await repo.loadCategories();
    expect(
      after.map((c) => c.id),
      isNot(contains('seed-food')),
      reason: '重新進首頁併回內建快照，不該讓已刪除的分類復活',
    );
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

/// 假的 R2：把每個 key 的內容跟一個遞增的 ETag 存在記憶體裡，不管簽章
/// 對不對、憑證是什麼，只看 method／path。
class _FakeR2Http extends http.BaseClient {
  final Map<String, Uint8List> _objects = {};
  final Map<String, String> _etags = {};
  int _etagSeq = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    switch (request.method) {
      case 'HEAD':
        if (!_objects.containsKey(path)) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'etag': _etags[path]!},
        );
      case 'GET':
        final body = _objects[path];
        if (body == null) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          Stream.value(body),
          200,
          headers: {'etag': _etags[path]!},
        );
      case 'PUT':
        final bytes = await request.finalize().toBytes();
        _objects[path] = Uint8List.fromList(bytes);
        _etagSeq++;
        final etag = 'v$_etagSeq';
        _etags[path] = etag;
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'etag': etag},
        );
      case 'DELETE':
        _objects.remove(path);
        _etags.remove(path);
        return http.StreamedResponse(const Stream.empty(), 204);
      default:
        throw UnsupportedError('unexpected method ${request.method}');
    }
  }
}
