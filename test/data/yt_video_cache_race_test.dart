
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/repositories/yt_video_tags.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-08 使用者回報「偶爾還是有幾部沒標上類型」：同一個頻道的快取
/// 被好幾個地方同時「讀→改→整份寫回」，後寫的蓋掉先寫的。
YoutubeVideo v(String id, {bool? short, bool? live, int day = 1}) =>
    YoutubeVideo(
      videoId: id,
      title: id,
      publishedAt: DateTime(2026, 9, day),
      thumbnailUrl: '',
      isShort: short,
      isLive: live,
    );

void main() {
  test('同時標類型跟新增影片，兩邊的結果都留得住', () async {
    final store = _SlowStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('c', [v('a'), v('b')]);

    // 背景掃描在標 a、b，同一時間往下捲抓到 c。
    await Future.wait([
      cache.retag('c', (x) => x.withShort(false).withLive(false)),
      cache.upsertVideos('c', [v('c', day: 0)]),
    ]);

    final byId = {for (final x in await cache.load('c')) x.videoId: x};
    expect(byId.keys, containsAll(['a', 'b', 'c']));
    expect(byId['a']!.isShort, isFalse);
    expect(byId['b']!.isLive, isFalse);
  });

  test('上傳頻率圖存回時不會洗掉途中標好的類型', () async {
    final store = _SlowStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('c', [v('a'), v('b')]);
    final staleCopy = await cache.load('c'); // 圖表一開始讀的舊副本

    await cache.retag('c', (x) => x.withLive(x.videoId == 'a'));
    await cache.upsertVideos('c', [v('new', day: 2)]);
    // 圖表抓完，帶著舊副本＋它判斷的 Shorts 存回去。
    await cache.save('c', [for (final x in staleCopy) x.withShort(false)]);

    final byId = {for (final x in await cache.load('c')) x.videoId: x};
    expect(byId['a']!.isLive, isTrue, reason: '途中標的直播不能被洗掉');
    expect(byId['a']!.isShort, isFalse, reason: '圖表判斷的 Shorts 要寫進去');
    expect(byId.containsKey('new'), isTrue, reason: '途中新增的影片不能消失');
  });

  test('快取一標到，共用標籤表就有，畫面那份清單不用自己複製', () async {
    final cache = YtVideoCacheStore(_SlowStore());
    var notified = 0;
    void listener() => notified++;
    YtVideoTags.notifier.addListener(listener);
    addTearDown(() => YtVideoTags.notifier.removeListener(listener));

    final onScreen = v('row1'); // 畫面上那份還沒有類型
    await cache.upsertVideos('c', [onScreen]);
    expect(YtVideoTags.apply(onScreen).isShort, isNull);

    await cache.retag('c', (x) => x.withShort(true));
    expect(notified, greaterThan(0));
    expect(YtVideoTags.apply(onScreen).isShort, isTrue);
    // 影片本身已經有的值不會被表蓋掉。
    expect(YtVideoTags.apply(onScreen.withShort(false)).isShort, isFalse);
  });
}

/// 每次讀寫都讓出一下，模擬真的非同步儲存，讓交錯有機會發生。
class _SlowStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
}
