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
/// 幾次，用來確認有沒有多打。不在 [lists] 裡的清單回 404。
class _FakeApi extends YoutubeApiService {
  _FakeApi(this.lists) : super('key');

  final Map<String, List<YoutubeVideo>> lists;
  final int pageSize = 2;
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
  test('沒標的補上：在 Shorts 清單裡標 true、不在標 false，沒有直播清單（404）都不是直播', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('ch', [_v('a', 20), _v('s1', 18), _v('b', 15)]);

    final tagged = await YtVideoTypeScanner(
      _FakeApi({
        'UUSHxyz': [_v('s1', 18), _v('s0', 10)],
      }),
      store,
    ).tagUntagged(channelId: 'ch', uploadsId: 'UUxyz');

    final byId = {for (final v in await cache.load('ch')) v.videoId: v};
    expect(tagged, 3);
    expect(byId['s1']!.isShort, isTrue);
    expect(byId['a']!.isShort, isFalse);
    expect(byId['b']!.isShort, isFalse);
    expect(byId['a']!.isLive, isFalse);
  });

  test('只翻到最舊那部沒標的影片的日期就停，不把整份清單翻完', () async {
    final store = _MemoryStore();
    await YtVideoCacheStore(store).upsertVideos('ch', [_v('a', 25)]);
    final api = _FakeApi({
      'UUSHxyz': [for (var d = 30; d >= 1; d--) _v('s$d', d)],
      'UULVxyz': const [],
    });

    await YtVideoTypeScanner(
      api,
      store,
    ).tagUntagged(channelId: 'ch', uploadsId: 'UUxyz');

    // Shorts 翻到 9/25 那天就停：30..29、28..27、26..25 共 3 頁，
    // 直播清單是空的 1 頁。
    expect(api.calls, 4);
  });

  test('全部都標過了就完全不打 API；之後只剩新影片沒標，只翻最新 1 頁', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('ch', [_v('old', 1)]);
    final lists = {
      'UUSHxyz': [_v('s9', 9), _v('s5', 5), _v('s1', 1)],
      'UULVxyz': <YoutubeVideo>[],
    };
    await YtVideoTypeScanner(
      _FakeApi(lists),
      store,
    ).tagUntagged(channelId: 'ch', uploadsId: 'UUxyz');

    final idle = _FakeApi(lists);
    await YtVideoTypeScanner(
      idle,
      store,
    ).tagUntagged(channelId: 'ch', uploadsId: 'UUxyz');
    expect(idle.calls, 0);

    await cache.upsertVideos('ch', [_v('new', 28)]);
    final api = _FakeApi({
      'UUSHxyz': [_v('s27', 27), ...lists['UUSHxyz']!],
      'UULVxyz': const [],
    });
    await YtVideoTypeScanner(
      api,
      store,
    ).tagUntagged(channelId: 'ch', uploadsId: 'UUxyz');
    expect(api.calls, 2); // Shorts 1 頁＋直播 1 頁
    final byId = {for (final v in await cache.load('ch')) v.videoId: v};
    expect(byId['new']!.isShort, isFalse);
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
