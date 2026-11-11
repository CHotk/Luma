import 'dart:convert';

import '../storage/key_value_store.dart';

/// 幣圈影片說的內容準不準（2026-11-11 使用者要求；設計稿
/// `design-history/2026-11-10_YT幣圈影片準度評價四種設計.html` 的「最終版」）。
///
/// 四種評價：對／半對／不對／沒給方向。「沒給方向」（影片沒講漲跌、沒有
/// 可驗證的說法）不算進命中率、也不算待驗證，自己一類。
enum YtVerdict {
  ok('對', '○'),
  half('半對', '△'),
  bad('不對', '✕'),
  none('沒給方向', '—');

  const YtVerdict(this.label, this.mark);
  final String label;
  final String mark;

  static YtVerdict? parse(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// 一部影片的評價紀錄（也可能只有「預測」、還沒評）。
///
/// 記在影片上、帶頻道 id 跟標題：統計要算每個頻道的命中率，影片不在
/// 目前載入的清單裡也要能算；換分類資料照樣留著。
class YtVideoRating {
  const YtVideoRating({
    required this.at,
    this.verdict,
    this.claim = '',
    this.dueAt,
    this.note = '',
    this.channelId = '',
    this.channelName = '',
    this.title = '',
    this.ratedAt,
  });

  /// 最後一次改的時間（同步時後改的贏）。
  final DateTime at;

  /// 評價；null＝還沒評（可能有預測在等驗證，也可能是清掉的墓碑）。
  final YtVerdict? verdict;

  /// 預測：影片說了什麼，等行情走完再驗證。
  final String claim;

  /// 預測要在哪天驗證。
  final DateTime? dueAt;

  final String note;
  final String channelId;
  final String channelName;
  final String title;

  /// 評價的時間（統計「最近評價」用）。
  final DateTime? ratedAt;

  /// 預測中、還沒評：待驗證。
  bool get pending => verdict == null && dueAt != null;

  /// 什麼都沒有（清掉了，留著當墓碑讓別台同步也清掉）。
  bool get isEmpty =>
      verdict == null && claim.isEmpty && dueAt == null && note.isEmpty;

  /// 已經到驗證日。
  bool isDue(DateTime now) => pending && !dueAt!.isAfter(now);

  YtVideoRating copyWith({
    DateTime? at,
    YtVerdict? verdict,
    bool clearVerdict = false,
    String? claim,
    DateTime? dueAt,
    bool clearDue = false,
    String? note,
    String? channelId,
    String? channelName,
    String? title,
    DateTime? ratedAt,
    bool clearRatedAt = false,
  }) => YtVideoRating(
    at: at ?? this.at,
    verdict: clearVerdict ? null : (verdict ?? this.verdict),
    claim: claim ?? this.claim,
    dueAt: clearDue ? null : (dueAt ?? this.dueAt),
    note: note ?? this.note,
    channelId: channelId ?? this.channelId,
    channelName: channelName ?? this.channelName,
    title: title ?? this.title,
    ratedAt: clearRatedAt ? null : (ratedAt ?? this.ratedAt),
  );

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    if (verdict != null) 'v': verdict!.name,
    if (claim.isNotEmpty) 'claim': claim,
    if (dueAt != null) 'due': dueAt!.toIso8601String(),
    if (note.isNotEmpty) 'note': note,
    if (channelId.isNotEmpty) 'ch': channelId,
    if (channelName.isNotEmpty) 'chn': channelName,
    if (title.isNotEmpty) 't': title,
    if (ratedAt != null) 'rat': ratedAt!.toIso8601String(),
  };

  factory YtVideoRating.fromJson(Map<String, dynamic> j) => YtVideoRating(
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000),
    verdict: YtVerdict.parse(j['v'] as String?),
    claim: j['claim'] as String? ?? '',
    dueAt: DateTime.tryParse(j['due'] as String? ?? ''),
    note: j['note'] as String? ?? '',
    channelId: j['ch'] as String? ?? '',
    channelName: j['chn'] as String? ?? '',
    title: j['t'] as String? ?? '',
    ratedAt: DateTime.tryParse(j['rat'] as String? ?? ''),
  );
}

/// 一個頻道的準度。
class YtAccuracy {
  const YtAccuracy({
    this.ok = 0,
    this.half = 0,
    this.bad = 0,
    this.none = 0,
    this.pending = 0,
  });

  final int ok, half, bad, none, pending;

  /// 已評（算命中率的）：對＋半對＋不對。沒給方向不算。
  int get rated => ok + half + bad;

  /// 命中率 0～100；一部都沒評是 null。
  double? get rate => rated == 0 ? null : (ok + half * 0.5) / rated * 100;

  /// 評價少於這個數就不給百分比／段位（樣本不足）。
  static const minSample = 3;

  bool get enough => rated >= minSample;

  /// 段位：S ≥80、A ≥65、B ≥50、C；樣本不足是 null。
  String? get grade {
    if (!enough) return null;
    final r = rate!;
    return r >= 80
        ? 'S'
        : r >= 65
        ? 'A'
        : r >= 50
        ? 'B'
        : 'C';
  }

  /// 畫面上的準度字，例如「S 100%」「資料少」。
  String get label => !enough ? '資料少' : '$grade ${rate!.round()}%';
}

/// 算準度（純函式，測試好測）。[channelId] 有給就只算那個頻道。
YtAccuracy ytAccuracyOf(Iterable<YtVideoRating> all, {String? channelId}) {
  var ok = 0, half = 0, bad = 0, none = 0, pending = 0;
  for (final r in all) {
    if (channelId != null && r.channelId != channelId) continue;
    switch (r.verdict) {
      case YtVerdict.ok:
        ok++;
      case YtVerdict.half:
        half++;
      case YtVerdict.bad:
        bad++;
      case YtVerdict.none:
        none++;
      case null:
        if (r.pending) pending++;
    }
  }
  return YtAccuracy(ok: ok, half: half, bad: bad, none: none, pending: pending);
}

/// 儲存＋雲端同步（跟 [YtVideoSongStore] 同一套：一部一部比改的時間，
/// 後改的贏；清掉的留墓碑一起傳）。
class YtVideoRatingStore {
  YtVideoRatingStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_rating.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'yt_video_ratings.json';

  /// 影片 id → 評價紀錄（含墓碑）。
  Future<Map<String, YtVideoRating>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    return decode(raw);
  }

  /// 沒被清掉的紀錄（畫面用這份）。
  Future<Map<String, YtVideoRating>> load() async => {
    for (final e in (await loadAll()).entries)
      if (!e.value.isEmpty) e.key: e.value,
  };

  Future<void> set(String videoId, YtVideoRating r) async {
    final all = await loadAll();
    all[videoId] = r;
    await saveAll(all);
  }

  Future<void> saveAll(Map<String, YtVideoRating> all) =>
      _store.write(_key, encode(all));

  static String encode(Map<String, YtVideoRating> all) =>
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()});

  static Map<String, YtVideoRating> decode(String raw) => {
    for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
      e.key: YtVideoRating.fromJson(e.value as Map<String, dynamic>),
  };

  /// 兩邊合併：同一部比改的時間，後改的贏。
  static Map<String, YtVideoRating> merge(
    Map<String, YtVideoRating> a,
    Map<String, YtVideoRating> b,
  ) {
    final out = {...a};
    for (final e in b.entries) {
      final mine = out[e.key];
      if (mine == null || e.value.at.isAfter(mine.at)) out[e.key] = e.value;
    }
    return out;
  }
}
