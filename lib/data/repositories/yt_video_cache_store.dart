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

  /// 上一次「真的跟 YouTube 對過」的時間，沒有就是 null。目前只是記錄、
  /// 跟著同步，不拿來擋 API——頻道隨時可能發新片，不設「多久內不重抓」
  /// （2026-09-24 使用者要求）。
  Future<DateTime?> lastFetchedAt(String channelId) async {
    final raw = await _store.read(_stampKeyFor(channelId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// 把雲端抓下來的快取併進本機（2026-09-24 使用者要求：資料都該可同步）。
  /// 聯集：同一部影片兩邊都有就留有時長的那份（時長是額外打 API 才補上
  /// 的，別被沒補到的版本蓋掉）；「上次對過 YouTube 的時間」取兩邊較晚
  /// 的（純記錄，不拿來擋 API）。回傳本機實際變動幾部影片。
  Future<int> mergeFromCloud(
    String channelId,
    List<YoutubeVideo> cloud,
    DateTime? cloudFetchedAt,
  ) async {
    final local = await load(channelId);
    final byId = {for (final v in local) v.videoId: v};
    var changed = 0;
    for (final v in cloud) {
      final existing = byId[v.videoId];
      if (existing == null) {
        byId[v.videoId] = v;
        changed++;
      } else if (existing.duration == null && v.duration != null) {
        byId[v.videoId] = v;
        changed++;
      }
    }
    final localAt = await lastFetchedAt(channelId);
    final newest = [localAt, cloudFetchedAt].whereType<DateTime>().fold<DateTime?>(
      null,
      (a, b) => a == null || b.isAfter(a) ? b : a,
    );
    if (changed > 0) {
      await _store.write(
        _keyFor(channelId),
        jsonEncode([for (final v in byId.values) v.toJson()]),
      );
    }
    if (newest != null && newest != localAt) {
      await _store.write(_stampKeyFor(channelId), newest.toIso8601String());
    }
    return changed;
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
