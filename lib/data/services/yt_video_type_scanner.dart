import '../repositories/yt_video_cache_store.dart';
import '../storage/key_value_store.dart';
import 'youtube_api_service.dart';

/// 幫影片快取裡**還沒標類型**的影片補上一般影片／Shorts／直播
/// （2026-10-05 使用者要求）。頻道詳情頁打開時在背景跑（只跑那個頻道），
/// YT 設定頁「補齊影片類型」一次跑全部頻道，兩邊共用這一份。
///
/// 標過的影片類型永遠不會變，所以不用記「掃到哪」：每次只看快取裡還
/// 沒標的影片，沒有就完全不打 API。有的話：
/// - YouTube API 沒有「這部是不是 Shorts」的欄位，只能看它在不在頻道
///   的 Shorts 清單（UUSH）／直播清單（UULV）裡。一部一部問要每部
///   1 單位配額；翻清單一頁 50 部才 1 單位，所以用翻的。
/// - 從清單最新的那頁往下翻，翻到比「最舊那部沒標的影片」更早就停，
///   那段時間內沒標的一次標好（在清單裡＝是，不在＝不是）。
/// 第一次（全部都沒標）會翻到最舊；之後只剩新抓到的影片沒標，通常
/// 只翻最新 1 頁。
class YtVideoTypeScanner {
  YtVideoTypeScanner(this._service, KeyValueStore store)
    : _cache = YtVideoCacheStore(store);

  final YoutubeApiService _service;
  final YtVideoCacheStore _cache;

  /// 一份清單最多翻幾頁（50 部一頁，5000 部），防止極端頻道翻到失控；
  /// 翻不到的那段留著沒標，下次再補。
  static const _maxPages = 100;

  /// 補一個頻道，回傳實際標了幾部。[uploadsId] 是頻道的上傳清單 id
  /// （`UU…`），不是 `UU` 開頭的就不補（回傳 0）。
  Future<int> tagUntagged({
    required String channelId,
    required String uploadsId,
  }) async {
    if (!uploadsId.startsWith('UU')) return 0;
    final cached = await _cache.load(channelId);
    final needShort = cached.where((v) => v.isShort == null).toList();
    final needLive = cached.where((v) => v.isLive == null).toList();
    if (needShort.isEmpty && needLive.isEmpty) return 0;
    final rest = uploadsId.substring(2);
    final shorts = needShort.isEmpty
        ? null
        : await _listUntil('UUSH$rest', _oldest(needShort));
    final live = needLive.isEmpty
        ? null
        : await _listUntil('UULV$rest', _oldest(needLive));
    return _cache.retag(channelId, (v) {
      var r = v;
      if (shorts != null && r.isShort == null) {
        if (shorts.ids.contains(v.videoId)) {
          r = r.withShort(true);
        } else if (shorts.covers(v.publishedAt)) {
          r = r.withShort(false);
        }
      }
      if (live != null && r.isLive == null) {
        if (live.ids.contains(v.videoId)) {
          r = r.withLive(true);
        } else if (live.covers(v.publishedAt)) {
          r = r.withLive(false);
        }
      }
      return r;
    });
  }

  static DateTime _oldest(List<YoutubeVideo> videos) =>
      videos.map((v) => v.publishedAt).reduce((a, b) => a.isBefore(b) ? a : b);

  /// 從最新的往下翻 [playlistId]，翻到比 [until] 更早（或清單到底）為止。
  /// 頻道沒有這種清單時 YouTube 回 404，當成「一部都沒有」。
  Future<_ListResult> _listUntil(String playlistId, DateTime until) async {
    final ids = <String>{};
    DateTime? oldest;
    String? token;
    try {
      for (var i = 0; i < _maxPages; i++) {
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
        if (token == null) return _ListResult(ids, oldest, complete: true);
        if (oldest != null && !oldest.isAfter(until)) break;
      }
    } on YoutubeApiException catch (e) {
      if (e.status != 404) rethrow;
      return _ListResult(ids, oldest, complete: true);
    }
    return _ListResult(ids, oldest, complete: false);
  }
}

class _ListResult {
  _ListResult(this.ids, this.oldest, {required this.complete});

  final Set<String> ids;
  final DateTime? oldest;
  final bool complete;

  /// 這部影片的發布時間有被翻到的範圍蓋到：不在 [ids] 裡就確定「不是
  /// 這一類」；範圍外的還不知道，留著沒標。
  bool covers(DateTime publishedAt) =>
      complete || (oldest != null && !publishedAt.isBefore(oldest!));
}
