import 'dart:convert';

import '../services/youtube_api_service.dart';
import '../storage/key_value_store.dart';

/// 頻道詳情頁「上傳頻率」圖表用的歷史影片本機快取，一個頻道一份，
/// key 帶頻道 id（2026-09-23 使用者要求：抓過的影片存起來，下次不用
/// 整段重抓）。
///
/// 只快取歷史影片這批（[YoutubeApiService.fetchAllVideos] 那批，用來
/// 畫圖的），不快取「最近影片」那個獨立小清單——那批本來就只抓
/// 10 筆，一次 API 呼叫的事，快取省下來的配額不多，不值得多一層
/// 複雜度。
class YtVideoCacheStore {
  YtVideoCacheStore(this._store);

  final KeyValueStore _store;

  static String _keyFor(String channelId) =>
      'yt_tracker.video_cache.$channelId.v1';

  Future<List<YoutubeVideo>> load(String channelId) async {
    final raw = await _store.read(_keyFor(channelId));
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YoutubeVideo.fromJson)
        .toList();
  }

  static String _stampKeyFor(String channelId) =>
      'yt_tracker.video_cache_at.$channelId.v1';

  /// 上一次「真的跟 YouTube 對過」的時間，沒有就是 null。頻道詳情頁靠
  /// 這個判斷快取夠不夠新，夠新就完全不打 API、直接用本機資料畫圖
  /// （2026-09-24 使用者抱怨：資料明明存了，每次進來還是等很久像重抓）。
  Future<DateTime?> lastFetchedAt(String channelId) async {
    final raw = await _store.read(_stampKeyFor(channelId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> save(String channelId, List<YoutubeVideo> videos) async {
    await _store.write(
      _keyFor(channelId),
      jsonEncode([for (final v in videos) v.toJson()]),
    );
    await _store.write(
      _stampKeyFor(channelId),
      DateTime.now().toIso8601String(),
    );
  }
}
