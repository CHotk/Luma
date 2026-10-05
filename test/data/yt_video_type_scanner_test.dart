import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/services/yt_video_type_scanner.dart';
import 'package:lume/data/storage/key_value_store.dart';

YoutubeVideo _v(String id, int day) => YoutubeVideo(
  videoId: id,
  title: id,
  publishedAt: DateTime(2026, 9, day),
  thumbnailUrl: '',
);

/// 假的 API：每個清單一份新到舊的影片，一頁 [pageSize] 部，記下被叫了
/// 幾次，用來確認有沒有亂翻頁。
class _FakeApi extends YoutubeApiService {
  _FakeApi(this.lists, {this.pageSize = 2}) : super('key');

  final Map<String, List<YoutubeVideo>> lists;
  final int pageSize;
  int calls = 0;

  @override
  Future<({List<YoutubeVideo> videos, String? nextPageToken})> fetchVideosPage(
    String uploadsPlaylistId, {
    String? pageToken,
    int maxResults = 10,
  }) async {
    calls++;
    final list = lists[uploadsPlaylistId];
    if (list == null) throw YoutubeApiException('沒有這個清單', status: 404);
    final start = pageToken == null ? 0 : int.parse(pageToken);
    final end = (start + pageSize).clamp(0, list.length);
    return (
      videos: list.sublist(start, end),
      nextPageToken: end < list.length ? '$end' : null,
    );
  }
}

void main() {
  test('補類型：Shorts 標 true、範圍內其他標 false，沒有直播清單（404）當成都不是直播', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('ch', [_v('a', 20), _v('s1', 18), _v('b', 15)]);
    final api = _FakeApi({
      'UUSHxyz': [_v('s1', 18), _v('s0', 10)],
    });

    final changed = await YtVideoTypeScanner(
      api,
      store,
    ).scan(channelId: 'ch', uploadsId: 'UUxyz');

    final byId = {for (final v in await cache.load('ch')) v.videoId: v};
    expect(changed, 3);
    expect(byId['s1']!.isShort, isTrue);
    expect(byId['a']!.isShort, isFalse);
    expect(byId['b']!.isShort, isFalse);
    expect(byId['a']!.isLive, isFalse);
  });

  test('只翻到快取最舊那部的日期就停，不把整份清單翻完', () async {
    final store = _MemoryStore();
    await YtVideoCacheStore(store).upsertVideos('ch', [_v('a', 25)]);
    final api = _FakeApi({
      'UUSHxyz': [for (var d = 30; d >= 1; d--) _v('s$d', d)],
      'UULVxyz': const [],
    });

    await YtVideoTypeScanner(
      api,
      store,
    ).scan(channelId: 'ch', uploadsId: 'UUxyz');

    // Shorts 翻到 9/25 那天就停：30..29、28..27、26..25 共 3 頁，
    // 直播清單是空的 1 頁。
    expect(api.calls, 4);
  });

  test('第二次掃：從最新翻到碰到掃過的就停，只多 1 頁', () async {
    final store = _MemoryStore();
    await YtVideoTypeScanner(
      _FakeApi({
        'UUSHxyz': [_v('s1', 18)],
        'UULVxyz': const [],
      }),
      store,
    ).scan(channelId: 'ch', uploadsId: 'UUxyz', target: DateTime(2026, 9, 1));

    final api = _FakeApi({
      'UUSHxyz': [_v('s2', 22), _v('s1', 18)],
      'UULVxyz': const [],
    });
    await YtVideoTypeScanner(
      api,
      store,
    ).scan(channelId: 'ch', uploadsId: 'UUxyz', target: DateTime(2026, 9, 1));

    expect(api.calls, 2); // Shorts 1 頁＋直播 1 頁
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
