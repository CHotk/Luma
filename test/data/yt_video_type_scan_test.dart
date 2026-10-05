import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/repositories/yt_video_type_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';

YoutubeVideo _video(String id, DateTime at) =>
    YoutubeVideo(videoId: id, title: id, publishedAt: at, thumbnailUrl: '');

void main() {
  test('掃描範圍：掃到哪天之後的才能確定「不是這一類」，更早的還不知道', () {
    final scan = YtTypeScan(videoIds: {'s1'}, oldest: DateTime(2026, 6, 1));
    expect(scan.covers(DateTime(2026, 9, 1)), isTrue);
    expect(scan.covers(DateTime(2026, 6, 1)), isTrue);
    expect(scan.covers(DateTime(2026, 1, 1)), isFalse);
    expect(const YtTypeScan(complete: true).covers(DateTime(2000)), isTrue);
    expect(const YtTypeScan().isFresh, isTrue);
  });

  test('掃描進度存得回來', () async {
    final store = YtVideoTypeStore(_MemoryStore());
    await store.save(
      'ch',
      'shorts',
      YtTypeScan(
        videoIds: {'a', 'b'},
        oldest: DateTime(2026, 5, 1),
        nextToken: 'tok',
      ),
    );
    final back = await store.load('ch', 'shorts');
    expect(back.videoIds, {'a', 'b'});
    expect(back.oldest, DateTime(2026, 5, 1));
    expect(back.nextToken, 'tok');
    expect(back.complete, isFalse);
  });

  test('retag 只改有變的影片，回傳改了幾部', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('ch', [
      _video('s1', DateTime(2026, 9, 1)),
      _video('v1', DateTime(2026, 9, 2)),
    ]);
    final changed = await cache.retag(
      'ch',
      (v) => v.videoId == 's1' ? v.withShort(true) : v,
    );
    expect(changed, 1);
    final byId = {for (final v in await cache.load('ch')) v.videoId: v};
    expect(byId['s1']!.isShort, isTrue);
    expect(byId['v1']!.isShort, isNull);
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
