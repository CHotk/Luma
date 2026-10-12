import '../repositories/yt_video_cache_store.dart';
import '../storage/key_value_store.dart';
import 'youtube_api_service.dart';

/// 頻道影片下架檢查（2026-10-12 使用者要求）：打開頻道時，這個頻道超過
/// [interval] 沒查過，就把快取裡的影片編號丟回 YouTube 問「這些還在嗎」
/// （[YoutubeApiService.fetchExistingVideoIds]，50 部 1 次），沒回來的
/// 標成下架（[YoutubeVideo.removedAt]），快取不刪。
///
/// 不綁頁面：呼叫端只傳本機儲存跟金鑰進來，點進頻道馬上退出，檢查照樣
/// 在背景跑完、寫回快取（使用者要求）。同一個頻道同時只跑一次。
class YtRemovedVideoChecker {
  YtRemovedVideoChecker(this._store, this._api);

  final KeyValueStore _store;
  final YoutubeApiService _api;

  /// 多久查一次（2026-10-12 先定一週，同天改成兩週）。
  static const interval = Duration(days: 14);

  static final _running = <String>{};

  /// 到期才查；沒到期、正在查、快取是空的都回傳 null（沒查）。查了就
  /// 回傳這次新發現下架的部數。
  Future<int?> checkIfDue(String channelId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final cache = YtVideoCacheStore(_store);
    final last = await cache.aliveCheckedAt(channelId);
    if (last != null && at.difference(last) < interval) return null;
    if (!_running.add(channelId)) return null;
    try {
      final ids = [for (final v in await cache.load(channelId)) v.videoId];
      if (ids.isEmpty) return null;
      final alive = await _api.fetchExistingVideoIds(ids);
      return cache.applyAliveCheck(
        channelId,
        asked: ids.toSet(),
        alive: alive,
        at: at,
      );
    } finally {
      _running.remove(channelId);
    }
  }
}
