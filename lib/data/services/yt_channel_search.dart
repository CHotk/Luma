import 'package:flutter/foundation.dart';

import '../repositories/yt_video_cache_store.dart';
import 'youtube_api_service.dart';

/// 頻道頁搜尋影片（2026-10-14 使用者選了設計稿第 1 版：頂部放大鏡）。
///
/// 1. 先找本機快取，馬上有結果。
/// 2. 設定是「快取＋YouTube」（預設）就從快取記下的「翻到哪裡」
///    （[YtResume]）接著往更早翻，一路翻到頻道最舊的影片才算找完——
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
    this.withDurations,
    this.totalOnYoutube,
  });

  final String channelId;
  final String query;
  final YtVideoCacheStore cache;

  /// null＝只搜快取（設定選「只搜快取」或沒有 API 金鑰）。
  final YoutubeApiService? api;

  /// 頻道的上傳清單 id；還不知道時給一個去拿的函式。
  final Future<String?> Function()? uploadsId;

  /// 新抓到的影片補時長（跟頻道頁往下滑載入同一支）。
  final Future<List<YoutubeVideo>> Function(List<YoutubeVideo>)? withDurations;

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

  bool get usesApi => api != null;
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
      if (api == null) {
        done = true;
        return;
      }
      final resume = await cache.loadResume(channelId);
      if (resume != null && (resume.end || resume.token == null)) {
        done = true;
        return;
      }
      final uploads = await uploadsId?.call();
      if (_cancelled) return;
      if (uploads == null || uploads.isEmpty) {
        throw StateError('找不到這個頻道的上傳清單');
      }
      // 沒有記過位置（還沒翻過）就從最新那頁開始。
      String? token = resume?.token;
      var offset = resume?.offset ?? 0;
      while (true) {
        final page = await api.fetchVideosPage(
          uploads,
          pageToken: token,
          maxResults: 50,
        );
        if (_cancelled) return;
        offset += page.videos.length;
        var fresh = [
          for (final v in page.videos)
            if (!known.contains(v.videoId)) v,
        ];
        if (fresh.isNotEmpty && withDurations != null) {
          fresh = await withDurations!(fresh);
        }
        await cache.upsertVideos(channelId, fresh);
        await cache.saveResumeIfDeeper(
          channelId,
          YtResume(
            token: page.nextPageToken,
            offset: offset,
            end: page.nextPageToken == null,
          ),
        );
        if (_cancelled) return;
        known.addAll(fresh.map((v) => v.videoId));
        fetchedIds.addAll(fresh.map((v) => v.videoId));
        scanned += fresh.length;
        _addMatches(fresh);
        token = page.nextPageToken;
        if (token == null) break;
        _changed();
      }
      done = true;
    } catch (e) {
      error = '$e';
    } finally {
      running = false;
      _changed();
    }
  }
}
