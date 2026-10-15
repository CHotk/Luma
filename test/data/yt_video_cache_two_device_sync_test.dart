// 2026-10-15 使用者回報：手機抓完一個頻道的全部影片、按同步（顯示上傳很多
// 筆），換電腦按同步卻沒下載多少，進頻道又整個重抓。這份用假的 R2 照那個
// 順序跑兩台裝置；順便驗證同步加速（列清單取代 HEAD、本機版本記號）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  YoutubeVideo v(int i) => YoutubeVideo(
    videoId: 'v$i',
    title: '影片 $i',
    publishedAt: DateTime(2020).add(Duration(days: i)),
    thumbnailUrl: '',
  );

  late _FakeR2Http r2;
  ({
    _MemoryStore store,
    YtTrackerRepository repo,
    YtVideoCacheStore cache,
    R2SyncService service,
  })
  device() {
    final store = _MemoryStore();
    final client = R2Client(
      credentials: const R2Credentials(
        endpoint: 'https://example.r2.cloudflarestorage.com',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
      ),
      bucket: 'b',
      httpClient: r2,
    );
    return (
      store: store,
      repo: YtTrackerRepository(store),
      cache: YtVideoCacheStore(store),
      service: R2SyncService(client, store),
    );
  }

  Future<void> sync(dynamic d) async {
    await d.service.syncYtTracker(d.repo);
    await d.service.syncYtVideoCache(d.cache, await d.repo.loadChannels());
  }

  setUp(() => r2 = _FakeR2Http());

  test('手機抓完整個頻道→同步，電腦同步後快取就有全部影片', () async {
    final phone = device();
    final pc = device();
    await phone.repo.addChannel(
      YtChannel(
        id: 'UC1',
        name: '頻道',
        categoryId: '',
        addedAt: DateTime(2026),
      ),
    );
    // 兩台先各同步過一次（手機那時只抓了 10 部，電腦也看過那 10 部）。
    await phone.cache.save('UC1', [for (var i = 0; i < 10; i++) v(i)]);
    await sync(phone);
    await sync(pc);
    expect((await pc.cache.load('UC1')).length, 10);
    await sync(pc); // 兩邊都沒動：整個跳過

    // 手機背景抓完全部 300 部、翻到底，再同步。
    await phone.cache.upsertVideos('UC1', [for (var i = 0; i < 300; i++) v(i)]);
    await phone.cache.saveResumeIfDeeper(
      'UC1',
      const YtResume(offset: 300, end: true),
    );
    await sync(phone);

    // 電腦同步：要拿到 300 部跟「已經翻到底」。
    await sync(pc);
    expect((await pc.cache.load('UC1')).length, 300);
    expect((await pc.cache.loadResume('UC1'))?.end, isTrue);
  });

  test('沒動過的頻道同步時不用 HEAD，列一次清單就知道', () async {
    final a = device();
    await a.repo.addChannel(
      YtChannel(id: 'UC1', name: 'x', categoryId: '', addedAt: DateTime(2026)),
    );
    await a.cache.save('UC1', [v(1)]);
    await sync(a);
    await a.service.syncYtTracker(a.repo);
    r2.heads = 0;
    await a.service.syncYtVideoCache(a.cache, await a.repo.loadChannels());
    expect(r2.heads, 0);
    expect((await a.cache.load('UC1')).length, 1);
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

/// 假的 R2：內容跟遞增 ETag 存在記憶體；支援 HEAD／GET／PUT／列清單。
class _FakeR2Http extends http.BaseClient {
  final Map<String, Uint8List> _objects = {};
  final Map<String, String> _etags = {};
  int _etagSeq = 0;
  int heads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' &&
        request.url.queryParameters['list-type'] == '2') {
      final prefix = '/b/${request.url.queryParameters['prefix'] ?? ''}';
      final items = [
        for (final k in _objects.keys)
          if (k.startsWith(prefix))
            '<Contents><Key>${k.substring(3)}</Key>'
                '<ETag>&quot;${_etags[k]}&quot;</ETag></Contents>',
      ];
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '<ListBucketResult>${items.join()}'
            '<IsTruncated>false</IsTruncated></ListBucketResult>',
          ),
        ),
        200,
      );
    }
    switch (request.method) {
      case 'HEAD':
        heads++;
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
        final etag = 'v${++_etagSeq}';
        _etags[path] = etag;
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'etag': etag},
        );
      default:
        throw UnsupportedError('unexpected ${request.method}');
    }
  }
}
