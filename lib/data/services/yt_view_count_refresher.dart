import '../repositories/yt_video_cache_store.dart';
import '../storage/key_value_store.dart';
import 'youtube_api_service.dart';

/// 觀看次數背景更新（2026-10-15 使用者要求）：進頻道才觸發；快取裡
/// 觀看次數超過 [every] 沒更新（或還沒抓過）的影片，50 部一批重抓
/// （[YoutubeApiService.fetchViewCounts]，每批 1 單位），抓一批寫回一批，
/// 中途離開下次接著抓沒更新到的。
///
/// 一個月內發的影片數字變得快，每次進頻道都重抓，不管 [every]（2026-10-15
/// 使用者要求）。
///
/// 不綁頁面（跟 [YtRemovedVideoChecker] 一樣）：點進頻道馬上退出也會
/// 跑完。同一個頻道同時只跑一次。
class YtViewCountRefresher {
  YtViewCountRefresher(this._store, this._api);

  final KeyValueStore _store;
  final YoutubeApiService _api;

  static final _running = <String>{};

  /// 多新的影片每次進頻道都更新。
  static const recent = Duration(days: 30);

  /// 回傳更新了幾部；正在跑或沒有要更新的回傳 0。
  Future<int> refreshIfDue(
    String channelId, {
    required Duration every,
    DateTime? now,
  }) async {
    if (!_running.add(channelId)) return 0;
    try {
      final at = now ?? DateTime.now();
      final cache = YtVideoCacheStore(_store);
      final due = [
        for (final v in await cache.load(channelId))
          if (v.removedAt == null &&
              (v.viewsAt == null ||
                  at.difference(v.publishedAt) < recent ||
                  at.difference(v.viewsAt!) >= every))
            v.videoId,
      ];
      var updated = 0;
      for (var i = 0; i < due.length; i += 50) {
        final batch = due.sublist(i, i + 50 > due.length ? due.length : i + 50);
        final views = await _api.fetchViewCounts(batch);
        updated += await cache.applyViews(channelId, views, at);
      }
      return updated;
    } finally {
      _running.remove(channelId);
    }
  }
}
