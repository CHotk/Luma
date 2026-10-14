import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/yt_video_cache_store.dart';
import 'youtube_api_service.dart';

/// 進頻道就在背景把這個頻道的影片全部抓進快取（2026-10-14 使用者要求：
/// 一進去先全部抓，畫面照樣從新到舊一批一批出來，搜尋、往下滑都只要讀
/// 快取）。一個頻道一份，頻道頁、搜尋共用，不會兩邊各抓一次。
///
/// 1. **補最新**：從最新那頁往下翻，碰到快取已經有的影片就停——上次之後
///    發的新片全部補齊（原本打開只抓最新 10 部，新片超過 10 部時中間會漏）。
/// 2. **補到最舊**：從快取記下的「翻到哪裡」（[YtResume]）接著翻到底。
///
/// 每一頁都存進快取、記下位置，中途離開下次接著抓；全部抓完後
/// [complete] 為 true，頻道頁就能寫「共 N 部影片」。同一個頻道 10 分鐘內
/// 抓完過就不再重跑（只是再搜一次之類）。
class YtChannelFiller extends ChangeNotifier {
  YtChannelFiller._(this.channelId);

  static final _all = <String, YtChannelFiller>{};

  static YtChannelFiller of(String channelId) =>
      _all.putIfAbsent(channelId, () => YtChannelFiller._(channelId));

  @visibleForTesting
  static void resetAll() => _all.clear();

  final String channelId;

  bool running = false;

  /// 整個頻道都在快取裡了（翻到過最舊那頁）。
  bool complete = false;
  String? error;

  /// 快取裡現在有幾部（[loadStatus] 讀一次，之後每抓一頁加上去）。
  int cached = 0;

  /// 剛抓到的那一頁新影片（搜尋拿來比對）。
  List<YoutubeVideo> lastFresh = const [];

  DateTime? _finishedAt;
  Future<void>? _run;
  Completer<void>? _tick;

  /// 等下一次有進度（抓完一頁或結束）。
  Future<void> nextTick() => (_tick ??= Completer<void>()).future;

  void _notify() {
    notifyListeners();
    final t = _tick;
    _tick = null;
    t?.complete();
  }

  /// 讀快取看現在有幾部、是不是已經抓完（打開頻道頁先讀，不打 API）。
  Future<void> loadStatus(YtVideoCacheStore cache) async {
    if (running) return;
    cached = (await cache.load(channelId)).length;
    complete = (await cache.loadResume(channelId))?.end ?? false;
    _notify();
  }

  /// 開始（或接上正在跑的那一次）；全部抓完或出錯才 complete。
  Future<void> start({
    required YtVideoCacheStore cache,
    required YoutubeApiService api,
    required Future<String?> Function() uploadsId,
  }) {
    final recent =
        _finishedAt != null &&
        DateTime.now().difference(_finishedAt!) < const Duration(minutes: 10);
    if (_run == null && complete && recent) return Future.value();
    return _run ??= _go(cache, api, uploadsId).whenComplete(() => _run = null);
  }

  Future<void> _go(
    YtVideoCacheStore cache,
    YoutubeApiService api,
    Future<String?> Function() uploadsIdOf,
  ) async {
    running = true;
    error = null;
    _notify();
    try {
      final uploads = await uploadsIdOf();
      if (uploads == null || uploads.isEmpty) {
        throw StateError('找不到這個頻道的上傳清單');
      }
      final known = {for (final v in await cache.load(channelId)) v.videoId};
      cached = known.length;

      Future<void> save(
        List<YoutubeVideo> page,
        String? next,
        int offset,
      ) async {
        var fresh = [
          for (final v in page)
            if (!known.contains(v.videoId)) v,
        ];
        if (fresh.isNotEmpty) {
          try {
            final durations = await api.fetchDurations([
              for (final v in fresh) v.videoId,
            ]);
            fresh = [
              for (final v in fresh)
                durations.containsKey(v.videoId)
                    ? v.withDuration(durations[v.videoId]!)
                    : v,
            ];
          } catch (_) {
            // 時長抓不到就算了，影片照樣存。
          }
          await cache.upsertVideos(channelId, fresh);
        }
        await cache.saveResumeIfDeeper(
          channelId,
          YtResume(token: next, offset: offset, end: next == null),
        );
        known.addAll(fresh.map((v) => v.videoId));
        cached += fresh.length;
        lastFresh = fresh;
        if (next == null) complete = true;
        _notify();
      }

      // 1. 補最新：碰到已經有的就停。
      String? token;
      var offset = 0;
      while (true) {
        final page = await api.fetchVideosPage(
          uploads,
          pageToken: token,
          maxResults: 50,
        );
        offset += page.videos.length;
        final hitKnown = page.videos.any((v) => known.contains(v.videoId));
        await save(page.videos, page.nextPageToken, offset);
        token = page.nextPageToken;
        if (hitKnown || token == null) break;
      }

      // 2. 補到最舊：從記下的位置接著翻。
      var resume = await cache.loadResume(channelId);
      while (resume != null && !resume.end && resume.token != null) {
        final page = await api.fetchVideosPage(
          uploads,
          pageToken: resume.token,
          maxResults: 50,
        );
        await save(
          page.videos,
          page.nextPageToken,
          resume.offset + page.videos.length,
        );
        resume = await cache.loadResume(channelId);
      }
      complete = resume?.end ?? complete;
      _finishedAt = DateTime.now();
    } catch (e) {
      error = '$e';
    } finally {
      running = false;
      lastFresh = const [];
      _notify();
    }
  }
}
