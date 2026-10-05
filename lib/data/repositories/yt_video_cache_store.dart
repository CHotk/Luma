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
/// 「往更早翻頁」的續抓位置：YouTube 上傳清單是新到舊，`nextPageToken`
/// 接著上次翻到的地方往下抓。[offset] 是「這個位置之前已經有幾部影片」，
/// 拿來比哪個位置比較深；[end] 是已經翻到最早一部、沒有更多了。
///
/// 為什麼記這個：頻道詳情頁往下滑要抓更早影片時，本機（含其他裝置同步
/// 過來的）已經有的那一段不用再請求，直接從這個位置接著抓
/// （2026-09-24 使用者要求）。token 是位移式的，頻道之後又發了新片會讓
/// 位置往後挪一點，結果只會是多抓到幾部重複的（用影片 id 去重），不會
/// 漏掉。
class YtResume {
  const YtResume({this.token, required this.offset, this.end = false});

  final String? token;
  final int offset;
  final bool end;

  Map<String, dynamic> toJson() => {
    'token': token,
    'offset': offset,
    'end': end,
  };

  factory YtResume.fromJson(Map<String, dynamic> json) => YtResume(
    token: json['token'] as String?,
    offset: json['offset'] as int? ?? 0,
    end: json['end'] as bool? ?? false,
  );
}

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

  static String _resumeKeyFor(String channelId) =>
      'yt_tracker.video_resume.$channelId.v1';

  Future<YtResume?> loadResume(String channelId) async {
    final raw = await _store.read(_resumeKeyFor(channelId));
    if (raw == null) return null;
    return YtResume.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// 只在新位置比已存的「更深」（或剛好翻到底）才更新。
  Future<void> saveResumeIfDeeper(String channelId, YtResume next) async {
    final current = await loadResume(channelId);
    if (current != null) {
      if (current.end) return;
      if (!next.end && next.offset <= current.offset) return;
    }
    await _store.write(_resumeKeyFor(channelId), jsonEncode(next.toJson()));
  }

  /// 把新抓到的影片併進快取（不動「上次對過 YouTube 的時間」）。已經有
  /// 的影片保留有時長的那份。回傳真的新增／補到時長的部數。
  Future<int> upsertVideos(String channelId, List<YoutubeVideo> videos) async {
    if (videos.isEmpty) return 0;
    final byId = {for (final v in await load(channelId)) v.videoId: v};
    var changed = 0;
    for (final v in videos) {
      final existing = byId[v.videoId];
      final next = existing == null ? v : _fillGaps(existing, v);
      if (!identical(next, existing)) {
        byId[v.videoId] = next;
        changed++;
      }
    }
    if (changed > 0) {
      await _store.write(
        _keyFor(channelId),
        jsonEncode([for (final v in byId.values) v.toJson()]),
      );
    }
    return changed;
  }

  /// 把雲端抓下來的快取併進本機（2026-09-24 使用者要求：資料都該可同步）。
  /// 聯集：同一部影片兩邊都有就留有時長的那份（時長是額外打 API 才補上
  /// 的，別被沒補到的版本蓋掉）；「上次對過 YouTube 的時間」取兩邊較晚
  /// 的（純記錄，不拿來擋 API）。回傳本機實際變動幾部影片。
  Future<int> mergeFromCloud(
    String channelId,
    List<YoutubeVideo> cloud,
    DateTime? cloudFetchedAt, {
    YtResume? cloudResume,
  }) async {
    if (cloudResume != null) await saveResumeIfDeeper(channelId, cloudResume);
    final local = await load(channelId);
    final byId = {for (final v in local) v.videoId: v};
    var changed = 0;
    for (final v in cloud) {
      final existing = byId[v.videoId];
      final next = existing == null ? v : _fillGaps(existing, v);
      if (!identical(next, existing)) {
        byId[v.videoId] = next;
        changed++;
      }
    }
    final localAt = await lastFetchedAt(channelId);
    final newest = [localAt, cloudFetchedAt]
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
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

/// 同一部影片已經在快取裡時，只把快取還沒有、新來的那份有的資訊補上：
/// 時長、是不是 Shorts、是不是直播。原本只看時長，已經在快取裡的影片
/// 從「一般影片／Shorts／直播」清單抓到時帶的類型標籤會被直接丟掉，
/// 快取裡的類型永遠補不起來（2026-10-05 使用者問「不是說翻類型清單時
/// 會順便標記類型嗎」才抓到）。已經有的值不蓋掉。什麼都沒補就回傳
/// [existing] 本身，呼叫端用 `identical` 判斷有沒有變。
YoutubeVideo _fillGaps(YoutubeVideo existing, YoutubeVideo incoming) {
  var v = existing;
  if (v.duration == null && incoming.duration != null) {
    v = v.withDuration(incoming.duration!);
  }
  if (v.isShort == null && incoming.isShort != null) {
    v = v.withShort(incoming.isShort!);
  }
  if (v.isLive == null && incoming.isLive != null) {
    v = v.withLive(incoming.isLive!);
  }
  return v;
}
