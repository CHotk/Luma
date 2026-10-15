import 'package:flutter/foundation.dart';

import '../repositories/yt_video_cache_store.dart';
import 'youtube_api_service.dart';
import 'yt_channel_filler.dart';

/// 頻道頁搜尋影片（2026-10-14 使用者選了設計稿第 1 版：頂部放大鏡）。
///
/// 2026-10-15 使用者要求改成**只搜快取、不自己打 API**：進頻道頁本來就會在
/// 背景把影片全部抓進快取（[YtChannelFiller]），搜尋時那一輪還在跑就接上
/// 它（抓到一頁比對一頁），沒在跑就只看快取（給 [fill]）。下面舊的 [api]
/// 流程留著給測試／舊呼叫用。
///
/// 1. 先找本機快取，馬上有結果。
/// 2. 設定是「快取＋YouTube」（預設）就用 [YtChannelFiller] 先補最新、再從
///    快取記下的「翻到哪裡」（[YtResume]）接著往更早翻，一路翻到頻道最舊的影片才算找完——
///    整個頻道都找過了還沒有，才說找不到。快取已經有的那一段整段跳過，
///    不重抓；翻過的一律存進快取（之後不用再請求、也會跟著同步），所以
///    同一個頻道只有第一次搜要花配額，之後只剩快取。
///
/// 只比對標題，大小寫不分。
class YtChannelSearch extends ChangeNotifier {
  YtChannelSearch({
    required this.channelId,
    required this.query,
    required this.cache,
    this.api,
    this.uploadsId,
    this.totalOnYoutube,
    this.fill,
  });

  /// 接上正在背景跑的那一輪；回傳 null＝沒在跑，只看快取。
  final Future<void>? Function()? fill;

  final String channelId;
  final String query;
  final YtVideoCacheStore cache;

  /// null＝只搜快取（設定選「只搜快取」或沒有 API 金鑰）。
  final YoutubeApiService? api;

  /// 頻道的上傳清單 id；還不知道時給一個去拿的函式。
  final Future<String?> Function()? uploadsId;

  /// 頻道上一共幾部（頻道資料裡的 videoCount），進度條用；不知道是 null。
  final int? totalOnYoutube;

  /// 找到的影片，新到舊。
  List<YoutubeVideo> get matches => List.unmodifiable(_matches);
  final _matches = <YoutubeVideo>[];

  /// 這次才從 YouTube 抓到、原本快取裡沒有的。
  final Set<String> fetchedIds = {};

  /// 快取裡原本有幾部。
  int cachedCount = 0;

  /// 目前找過幾部（快取＋這次新抓的）。
  int scanned = 0;

  /// 這次有在等 YouTube 補影片（自己抓或接上背景那一輪）。
  bool get usesApi => api != null || _joined;
  bool _joined = false;
  bool running = false;
  bool done = false;
  String? error;
  bool _cancelled = false;

  static bool matchesQuery(String title, String query) =>
      title.toLowerCase().contains(query.trim().toLowerCase());

  void cancel() => _cancelled = true;

  void _addMatches(Iterable<YoutubeVideo> videos) {
    _matches
      ..addAll(videos.where((v) => matchesQuery(v.title, query)))
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  void _changed() {
    if (!_cancelled) notifyListeners();
  }

  Future<void> run() async {
    running = true;
    error = null;
    try {
      final cached = await cache.load(channelId);
      if (_cancelled) return;
      final known = {for (final v in cached) v.videoId};
      if (scanned == 0) {
        cachedCount = cached.length;
        scanned = cached.length;
        _addMatches(cached);
        _changed();
      }
      final api = this.api;
      final joined = fill?.call();
      if (joined == null && api == null) {
        done = true;
        return;
      }
      _joined = true;
      _changed();
      // 跟頻道頁共用同一個背景抓取（[YtChannelFiller]）：先補最新、再補到
      // 最舊，抓到一頁就拿來比對；頻道頁已經在抓的話直接接上，不會抓兩次。
      final filler = YtChannelFiller.of(channelId);
      void onTick() {
        if (_cancelled) return;
        final fresh = [
          for (final v in filler.lastFresh)
            if (!known.contains(v.videoId)) v,
        ];
        if (fresh.isEmpty) return;
        known.addAll(fresh.map((v) => v.videoId));
        fetchedIds.addAll(fresh.map((v) => v.videoId));
        scanned += fresh.length;
        _addMatches(fresh);
        _changed();
      }

      filler.addListener(onTick);
      try {
        await (joined ??
            filler.start(
              cache: cache,
              api: api!,
              uploadsId: uploadsId ?? () async => null,
            ));
      } finally {
        filler.removeListener(onTick);
      }
      if (_cancelled) return;
      // 接上之前那一輪就已經存進快取、沒比對到的補比對。
      final later = [
        for (final v in await cache.load(channelId))
          if (!known.contains(v.videoId)) v,
      ];
      if (_cancelled) return;
      if (later.isNotEmpty) {
        known.addAll(later.map((v) => v.videoId));
        scanned += later.length;
        _addMatches(later);
      }
      if (filler.error != null) throw StateError(filler.error!);
      done = true;
    } catch (e) {
      error = '$e';
    } finally {
      running = false;
      _changed();
    }
  }
}
