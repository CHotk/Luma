import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';

YoutubeVideo _video({Duration? duration, bool? isShort, bool? isLive}) =>
    YoutubeVideo(
      videoId: 'v1',
      title: 't',
      publishedAt: DateTime(2026, 9, 1),
      thumbnailUrl: '',
      duration: duration,
      isShort: isShort,
      isLive: isLive,
    );

void main() {
  test('已經在快取裡的影片，翻類型清單抓到時會補上類型標籤，不蓋掉已有的時長', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('ch', [
      _video(duration: const Duration(minutes: 8)),
    ]);

    final changed = await cache.upsertVideos('ch', [
      _video(isShort: false, isLive: false),
    ]);

    final v = (await cache.load('ch')).single;
    expect(changed, 1);
    expect(v.duration, const Duration(minutes: 8));
    expect(v.isShort, isFalse);
    expect(v.isLive, isFalse);
  });

  test('「全部」跟每個類型各記各的翻頁位置，互不影響', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.saveResumeIfDeeper(
      'ch',
      const YtResume(token: 'all-2', offset: 100),
    );
    await cache.saveResumeIfDeeper(
      'ch',
      const YtResume(token: 'sh-1', offset: 50),
      kind: 'shorts',
    );

    expect((await cache.loadResume('ch'))!.token, 'all-2');
    expect((await cache.loadResume('ch', kind: 'shorts'))!.token, 'sh-1');
    expect(await cache.loadResume('ch', kind: 'live'), isNull);
  });

  test('雲端合併也會補類型標籤；已經有的標籤不會被蓋掉', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('ch', [_video(isShort: true)]);

    await cache.mergeFromCloud('ch', [
      _video(isShort: false, isLive: false),
    ], null);

    final v = (await cache.load('ch')).single;
    expect(v.isShort, isTrue);
    expect(v.isLive, isFalse);
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
