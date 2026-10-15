import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_new_videos.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// NEW（2026-10-15 使用者定義）：當下快取沒有、API 抓到的。
void main() {
  YoutubeVideo v(String id) => YoutubeVideo(
    videoId: id,
    title: id,
    publishedAt: DateTime(2026),
    thumbnailUrl: '',
  );

  test('頻道第一次抓不算；之後新抓到、快取沒有的才算；同步帶來的不算', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('UC', [v('a'), v('b')]);
    expect(YtNewVideos.notifier.value, isEmpty);
    await cache.upsertVideos('UC', [v('b'), v('c')]);
    expect(YtNewVideos.notifier.value, {'c'});
    await cache.mergeFromCloud('UC', [v('d')], null);
    expect(YtNewVideos.notifier.value, {'c'});
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
