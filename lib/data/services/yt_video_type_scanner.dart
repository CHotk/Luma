import '../repositories/yt_video_cache_store.dart';
import '../repositories/yt_video_type_store.dart';
import '../storage/key_value_store.dart';
import 'youtube_api_service.dart';

/// 翻頻道的 Shorts（UUSH）跟直播（UULV）清單，把類型標進影片快取
/// （2026-10-05 使用者要求：類型一開始就標好，類型篩選的數字才準）。
/// 頻道詳情頁打開時在背景跑一次（只掃那個頻道），YT 設定頁「補齊影片
/// 類型」一次跑全部頻道，兩邊共用這一份。
///
/// 翻多深不是固定抓幾部，而是**對齊快取已經有的範圍**：只翻到 [scan] 的
/// `target`（通常是快取裡最舊那部影片的日期）為止，更早的影片快取裡也
/// 沒有，標了用不到；之後「全部」往下捲變深，再叫一次就會從上次停的
/// 地方接著往更早翻。每頁拉滿 50 部——YouTube 一頁 5 部或 50 部都是
/// 1 單位配額。已經掃過的頻道，再叫只從最新的往下翻到碰到掃過的影片
/// 就停（通常 1 頁），只補新發的。掃到哪記在 [YtVideoTypeStore]。
class YtVideoTypeScanner {
  YtVideoTypeScanner(this._service, KeyValueStore store)
    : _cache = YtVideoCacheStore(store),
      _types = YtVideoTypeStore(store);

  final YoutubeApiService _service;
  final YtVideoCacheStore _cache;
  final YtVideoTypeStore _types;

  /// 掃一個頻道，回傳快取裡實際改了幾部影片的類型。[uploadsId] 是頻道
  /// 的上傳清單 id（`UU…`），不是 `UU` 開頭的就不掃（回傳 0）。
  /// [target] 沒給就用快取裡最舊那部；快取是空的就不掃。
  Future<int> scan({
    required String channelId,
    required String uploadsId,
    DateTime? target,
  }) async {
    if (!uploadsId.startsWith('UU')) return 0;
    var until = target;
    if (until == null) {
      final cached = await _cache.load(channelId);
      if (cached.isEmpty) return 0;
      until = cached
          .map((v) => v.publishedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
    }
    final rest = uploadsId.substring(2);
    final shorts = await _scanList(channelId, 'shorts', 'UUSH$rest', until);
    final live = await _scanList(channelId, 'live', 'UULV$rest', until);
    return _cache.retag(channelId, (v) {
      var r = v;
      if (shorts.videoIds.contains(v.videoId)) {
        if (r.isShort != true) r = r.withShort(true);
      } else if (shorts.covers(v.publishedAt) && r.isShort != false) {
        r = r.withShort(false);
      }
      if (live.videoIds.contains(v.videoId)) {
        if (r.isLive != true) r = r.withLive(true);
      } else if (live.covers(v.publishedAt) && r.isLive != false) {
        r = r.withLive(false);
      }
      return r;
    });
  }

  /// 翻一份特殊清單，回傳更新後的掃描進度：
  /// 1. 掃過的話，先從最新的往下翻，碰到已經掃過的影片就停（補新發的）。
  /// 2. 還沒翻到 [target] 那天、清單也還沒到底，就從上次停的地方往更早
  ///    翻，翻到比 [target] 更早為止。
  /// 頻道沒有這種清單時 YouTube 回 404，當成「整份翻完、一部都沒有」。
  Future<YtTypeScan> _scanList(
    String channelId,
    String kind,
    String playlistId,
    DateTime target,
  ) async {
    final scan = await _types.load(channelId, kind);
    final ids = {...scan.videoIds};
    var oldest = scan.oldest;
    var token = scan.nextToken;
    var complete = scan.complete;
    try {
      if (!scan.isFresh) {
        String? topToken;
        for (var i = 0; i < 10; i++) {
          final page = await _service.fetchVideosPage(
            playlistId,
            pageToken: topToken,
            maxResults: 50,
          );
          final hitKnown = page.videos.any((v) => ids.contains(v.videoId));
          ids.addAll(page.videos.map((v) => v.videoId));
          topToken = page.nextPageToken;
          if (hitKnown || topToken == null) break;
        }
      }
      for (
        var i = 0;
        i < 40 && !complete && (oldest == null || oldest.isAfter(target));
        i++
      ) {
        final page = await _service.fetchVideosPage(
          playlistId,
          pageToken: token,
          maxResults: 50,
        );
        ids.addAll(page.videos.map((v) => v.videoId));
        for (final v in page.videos) {
          if (oldest == null || v.publishedAt.isBefore(oldest)) {
            oldest = v.publishedAt;
          }
        }
        token = page.nextPageToken;
        complete = token == null;
      }
    } on YoutubeApiException catch (e) {
      if (e.status != 404) {
        // 配額用完、網路斷了：翻到一半的進度先存起來，下次接著翻。
        await _types.save(
          channelId,
          kind,
          YtTypeScan(
            videoIds: ids,
            oldest: oldest,
            nextToken: token,
            complete: complete,
          ),
        );
        rethrow;
      }
      complete = true;
      token = null;
    }
    final next = YtTypeScan(
      videoIds: ids,
      oldest: oldest,
      nextToken: token,
      complete: complete,
    );
    await _types.save(channelId, kind, next);
    return next;
  }
}
