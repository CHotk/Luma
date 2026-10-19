/// 音樂功能的資料（2026-10-19 使用者定案，設計稿
/// `design-history/已選擇完成/音樂功能設計/2026-10-19_音樂功能最終版.html`）。
///
/// 三層：歌手、歌曲（一首作品）、版本（一部 YouTube 影片＝某人唱的某一版）。
/// 加進來的時候把影片資料**抄一份**存在這裡，之後跟 YT 管理無關——YT 那邊
/// 刪頻道、換分類，音樂裡的歌都還在。
///
/// 每一筆都有「改的時間」跟刪掉的墓碑，同步時一筆一筆比，後改的贏
/// （見 [MusicData.merge]）。
library;

/// 版本的種類。
enum MusicVersionType {
  sing('演唱', '歌手自己的正式版本（MV、錄音室）'),
  duet('合唱', '好幾個人一起唱'),
  cover('翻唱', '唱別人的歌'),
  live('Live', '現場、演唱會'),
  acapella('清唱', '沒有伴奏，綜藝、街頭'),
  other('其他', '伴奏、純音樂、教學…');

  const MusicVersionType(this.label, this.hint);
  final String label;
  final String hint;

  static MusicVersionType fromName(String? n) => MusicVersionType.values
      .firstWhere((t) => t.name == n, orElse: () => MusicVersionType.other);
}

// 時間存成 UTC、讀回來轉成這台裝置的時區（2026-10-19：以前存的是沒有時區的本地
// 時間，兩台裝置時區不同就會差好幾小時，「後改的贏」會判錯）。舊資料沒有時區
// 記號，照本地時間讀，不受影響。
DateTime _date(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime(2000);
DateTime? _dateOrNull(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toLocal();

/// 同步用的共同欄位。
abstract class MusicRecord {
  String get id;
  DateTime get updatedAt;
  DateTime? get deletedAt;
  Map<String, dynamic> toJson();
}

class MusicArtist implements MusicRecord {
  const MusicArtist({
    required this.id,
    required this.name,
    this.avatarUrls = const [],
    this.shownAvatar = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;

  /// 大頭貼網址，照順序：預設、備用 2、3、4、5（2026-10-19 使用者要求：可以
  /// 放好幾張，選要顯示哪一張；那張壞了就照順序換下一張）。
  final List<String> avatarUrls;

  /// 要顯示第幾張（[avatarUrls] 的索引）。跟著歌手一起同步。
  final int shownAvatar;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  static const maxAvatars = 5;

  /// 顯示的順序：選的那張先，壞了再照原本順序換其他張。
  List<String> get avatarOrder {
    final urls = avatarUrls.where((u) => u.trim().isNotEmpty).toList();
    if (urls.isEmpty) return const [];
    final i = shownAvatar.clamp(0, urls.length - 1);
    return [
      urls[i],
      for (var k = 0; k < urls.length; k++)
        if (k != i) urls[k],
    ];
  }

  /// 現在顯示的那張（沒有就是空字串）。
  String get avatarUrl => avatarOrder.firstOrNull ?? '';

  MusicArtist copyWith({
    String? name,
    List<String>? avatarUrls,
    int? shownAvatar,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => MusicArtist(
    id: id,
    name: name ?? this.name,
    avatarUrls: avatarUrls ?? this.avatarUrls,
    shownAvatar: shownAvatar ?? this.shownAvatar,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (avatarUrls.isNotEmpty) 'avatars': avatarUrls,
    if (shownAvatar != 0) 'shown': shownAvatar,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  factory MusicArtist.fromJson(Map<String, dynamic> j) => MusicArtist(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    avatarUrls: [
      for (final x in (j['avatars'] as List? ?? const [])) x as String,
      // 最早只存一張（avatarUrl）。
      if (j['avatars'] == null && (j['avatarUrl'] as String? ?? '').isNotEmpty)
        j['avatarUrl'] as String,
    ],
    shownAvatar: (j['shown'] as num?)?.toInt() ?? 0,
    updatedAt: _date(j['updatedAt']),
    deletedAt: _dateOrNull(j['deletedAt']),
  );
}

/// 一首歌（作品）：歌名、原唱。所有人唱的版本都掛在它底下。
class MusicWork implements MusicRecord {
  const MusicWork({
    required this.id,
    required this.title,
    this.originalArtistIds = const [],
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final List<String> originalArtistIds;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  MusicWork copyWith({
    String? title,
    List<String>? originalArtistIds,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => MusicWork(
    id: id,
    title: title ?? this.title,
    originalArtistIds: originalArtistIds ?? this.originalArtistIds,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'orig': originalArtistIds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  factory MusicWork.fromJson(Map<String, dynamic> j) => MusicWork(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    originalArtistIds: [
      for (final x in (j['orig'] as List? ?? const [])) x as String,
    ],
    updatedAt: _date(j['updatedAt']),
    deletedAt: _dateOrNull(j['deletedAt']),
  );
}

/// 一個版本＝一部 YouTube 影片。id 就是影片 id（同一部影片只會在音樂裡
/// 出現一次）。影片的標題、縮圖、長度、上傳頻道都抄一份。
class MusicVersion implements MusicRecord {
  const MusicVersion({
    required this.id,
    required this.workId,
    required this.type,
    required this.artistIds,
    this.note = '',
    required this.videoTitle,
    required this.thumbnailUrl,
    required this.uploaderName,
    this.durationSec,
    required this.publishedAt,
    required this.addedAt,
    required this.updatedAt,
    this.deletedAt,
    this.dislikedAt,
  });

  /// YouTube 影片 id。
  @override
  final String id;
  final String workId;
  final MusicVersionType type;

  /// 誰唱的（可以好幾個）。
  final List<String> artistIds;

  /// 版本備註（選填，例如「2019 嘉年華演唱會」「鋼琴版」），同一首歌好幾個
  /// 版本時用來分。YouTube 的長標題不顯示在列表上，只顯示歌名＋這個。
  final String note;

  /// 抄來的 YouTube 原標題（只在編輯時給使用者參考）。
  final String videoTitle;
  final String thumbnailUrl;
  final String uploaderName;
  final int? durationSec;
  final DateTime publishedAt;
  final DateTime addedAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  /// 標成「不喜歡」的時間（2026-10-19 使用者要求：音樂不做刪除——本意是記
  /// 這個歌手有哪些歌——不想聽的放「不喜歡」那一區）。null＝沒有。不喜歡的
  /// 不會出現在首頁、也不會被播放全部／隨機排進去。
  final DateTime? dislikedAt;

  bool get disliked => dislikedAt != null;

  String get videoId => id;

  MusicVersion copyWith({
    String? workId,
    MusicVersionType? type,
    List<String>? artistIds,
    String? note,
    bool? disliked,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => MusicVersion(
    id: id,
    workId: workId ?? this.workId,
    type: type ?? this.type,
    artistIds: artistIds ?? this.artistIds,
    note: note ?? this.note,
    videoTitle: videoTitle,
    thumbnailUrl: thumbnailUrl,
    uploaderName: uploaderName,
    durationSec: durationSec,
    publishedAt: publishedAt,
    addedAt: addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    dislikedAt: disliked == null
        ? dislikedAt
        : (disliked ? (dislikedAt ?? DateTime.now()) : null),
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'type': type.name,
    'artists': artistIds,
    if (note.isNotEmpty) 'note': note,
    'title': videoTitle,
    'thumb': thumbnailUrl,
    'uploader': uploaderName,
    if (durationSec != null) 'dur': durationSec,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'addedAt': addedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
    if (dislikedAt != null) 'dislikedAt': dislikedAt!.toUtc().toIso8601String(),
  };

  factory MusicVersion.fromJson(Map<String, dynamic> j) => MusicVersion(
    id: j['id'] as String,
    workId: j['workId'] as String? ?? '',
    type: MusicVersionType.fromName(j['type'] as String?),
    artistIds: [
      for (final x in (j['artists'] as List? ?? const [])) x as String,
    ],
    note: j['note'] as String? ?? '',
    videoTitle: j['title'] as String? ?? '',
    thumbnailUrl: j['thumb'] as String? ?? '',
    uploaderName: j['uploader'] as String? ?? '',
    durationSec: (j['dur'] as num?)?.toInt(),
    publishedAt: _date(j['publishedAt']),
    addedAt: _date(j['addedAt']),
    updatedAt: _date(j['updatedAt']),
    deletedAt: _dateOrNull(j['deletedAt']),
    dislikedAt: _dateOrNull(j['dislikedAt']),
  );
}

/// 歌單（「喜歡的歌」也是一份，id 固定 [likedId]）。存版本 id，新加的在最前面。
class MusicPlaylist implements MusicRecord {
  const MusicPlaylist({
    required this.id,
    required this.name,
    this.versionIds = const [],
    required this.updatedAt,
    this.deletedAt,
  });

  static const likedId = 'liked';

  @override
  final String id;
  final String name;
  final List<String> versionIds;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isLiked => id == likedId;

  MusicPlaylist copyWith({
    String? name,
    List<String>? versionIds,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => MusicPlaylist(
    id: id,
    name: name ?? this.name,
    versionIds: versionIds ?? this.versionIds,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ids': versionIds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  factory MusicPlaylist.fromJson(Map<String, dynamic> j) => MusicPlaylist(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    versionIds: [for (final x in (j['ids'] as List? ?? const [])) x as String],
    updatedAt: _date(j['updatedAt']),
    deletedAt: _dateOrNull(j['deletedAt']),
  );
}

/// 音樂的全部資料（含墓碑）。畫面用 [artists]／[works]／[versions]／
/// [playlists] 這幾個「還在的」。
class MusicData {
  const MusicData({
    this.artistMap = const {},
    this.workMap = const {},
    this.versionMap = const {},
    this.playlistMap = const {},
  });

  static const empty = MusicData();

  final Map<String, MusicArtist> artistMap;
  final Map<String, MusicWork> workMap;
  final Map<String, MusicVersion> versionMap;
  final Map<String, MusicPlaylist> playlistMap;

  static List<T> _alive<T extends MusicRecord>(Map<String, T> m) => [
    for (final r in m.values)
      if (r.deletedAt == null) r,
  ];

  List<MusicArtist> get artists => _alive(artistMap);
  List<MusicWork> get works => _alive(workMap);

  /// 新加的在前面。
  List<MusicVersion> get versions =>
      _alive(versionMap)..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  List<MusicPlaylist> get playlists => _alive(playlistMap);

  /// 沒標不喜歡的（首頁、播放全部、隨機用這份）。
  List<MusicVersion> get playable =>
      versions.where((v) => !v.disliked).toList();

  /// 標了不喜歡的。
  List<MusicVersion> get disliked => versions.where((v) => v.disliked).toList();

  MusicArtist? artist(String id) {
    final a = artistMap[id];
    return a == null || a.deletedAt != null ? null : a;
  }

  MusicWork? work(String id) {
    final w = workMap[id];
    return w == null || w.deletedAt != null ? null : w;
  }

  MusicVersion? version(String id) {
    final v = versionMap[id];
    return v == null || v.deletedAt != null ? null : v;
  }

  /// 這部 YouTube 影片在不在音樂裡（YT 管理的 ♫ 標記看這個）。
  bool hasVideo(String videoId) => version(videoId) != null;

  /// 音樂裡全部影片 id（YT 管理每一列看這份，查一下就知道）。
  Set<String> get videoIds => {for (final v in versions) v.id};

  List<MusicVersion> versionsOfWork(String workId) => [
    for (final v in versions)
      if (v.workId == workId) v,
  ];

  List<MusicVersion> versionsOfArtist(String artistId) => [
    for (final v in versions)
      if (v.artistIds.contains(artistId)) v,
  ];

  /// 這個歌手原唱的歌。
  List<MusicWork> worksByOriginal(String artistId) => [
    for (final w in works)
      if (w.originalArtistIds.contains(artistId)) w,
  ];

  MusicPlaylist get liked =>
      playlistMap[MusicPlaylist.likedId] ??
      MusicPlaylist(
        id: MusicPlaylist.likedId,
        name: '喜歡的歌',
        updatedAt: DateTime(2000),
      );

  String artistNames(MusicVersion v) =>
      [for (final id in v.artistIds) artist(id)?.name ?? '?'].join('、');

  MusicData copyWith({
    Map<String, MusicArtist>? artistMap,
    Map<String, MusicWork>? workMap,
    Map<String, MusicVersion>? versionMap,
    Map<String, MusicPlaylist>? playlistMap,
  }) => MusicData(
    artistMap: artistMap ?? this.artistMap,
    workMap: workMap ?? this.workMap,
    versionMap: versionMap ?? this.versionMap,
    playlistMap: playlistMap ?? this.playlistMap,
  );

  MusicData putArtist(MusicArtist a) =>
      copyWith(artistMap: {...artistMap, a.id: a});
  MusicData putWork(MusicWork w) => copyWith(workMap: {...workMap, w.id: w});
  MusicData putVersion(MusicVersion v) =>
      copyWith(versionMap: {...versionMap, v.id: v});
  MusicData putPlaylist(MusicPlaylist p) =>
      copyWith(playlistMap: {...playlistMap, p.id: p});

  Map<String, dynamic> toJson() => {
    'artists': [for (final a in artistMap.values) a.toJson()],
    'works': [for (final w in workMap.values) w.toJson()],
    'versions': [for (final v in versionMap.values) v.toJson()],
    'playlists': [for (final p in playlistMap.values) p.toJson()],
  };

  factory MusicData.fromJson(Map<String, dynamic> j) {
    Map<String, T> read<T extends MusicRecord>(
      String key,
      T Function(Map<String, dynamic>) f,
    ) => {
      for (final x in (j[key] as List? ?? const []))
        (x as Map<String, dynamic>)['id'] as String: f(x),
    };
    return MusicData(
      artistMap: read('artists', MusicArtist.fromJson),
      workMap: read('works', MusicWork.fromJson),
      versionMap: read('versions', MusicVersion.fromJson),
      playlistMap: read('playlists', MusicPlaylist.fromJson),
    );
  }

  /// 兩邊合併：同一筆比改的時間，後改的贏（刪掉的墓碑也是一筆）。
  static MusicData merge(MusicData a, MusicData b) {
    Map<String, T> m<T extends MusicRecord>(
      Map<String, T> x,
      Map<String, T> y,
    ) {
      final out = {...x};
      for (final e in y.entries) {
        final mine = out[e.key];
        if (mine == null || e.value.updatedAt.isAfter(mine.updatedAt)) {
          out[e.key] = e.value;
        }
      }
      return out;
    }

    return MusicData(
      artistMap: m(a.artistMap, b.artistMap),
      workMap: m(a.workMap, b.workMap),
      versionMap: m(a.versionMap, b.versionMap),
      playlistMap: m(a.playlistMap, b.playlistMap),
    ).mergeSameNameArtists();
  }

  /// 兩台裝置各自新增了同名的歌手（id 不一樣），同步合併後會變成兩個一模一樣的
  /// 人。這裡把同名的合成一個：留 id 最小的（每台裝置算出來都一樣，不會互相
  /// 打架），其他的標成刪除，歌／原唱裡指到它們的改指到留下的那個。改過的
  /// 紀錄時間一律設成「這一群裡最晚的時間再 +1 毫秒」，才贏得過還沒合併的裝置
  /// 送上來的舊版本，而且兩台算出來的時間也一樣。
  MusicData mergeSameNameArtists() {
    final groups = <String, List<MusicArtist>>{};
    for (final a in artists) {
      final n = a.name.trim();
      if (n.isNotEmpty) (groups[n] ??= []).add(a);
    }
    final remap = <String, String>{};
    final stamp = <String, DateTime>{};
    final artistMap = {...this.artistMap};
    for (final g in groups.values) {
      if (g.length < 2) continue;
      g.sort((x, y) => x.id.compareTo(y.id));
      final keeper = g.first;
      final t = g
          .map((x) => x.updatedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y)
          .add(const Duration(milliseconds: 1));
      for (final dup in g.skip(1)) {
        remap[dup.id] = keeper.id;
        artistMap[dup.id] = dup.copyWith(updatedAt: t, deletedAt: t);
        stamp[dup.id] = t;
      }
      // 留下的那個：沒有大頭貼就用重複那幾個的。
      if (keeper.avatarUrls.isEmpty) {
        final donor = g
            .skip(1)
            .where((x) => x.avatarUrls.isNotEmpty)
            .firstOrNull;
        if (donor != null) {
          artistMap[keeper.id] = keeper.copyWith(
            avatarUrls: donor.avatarUrls,
            shownAvatar: donor.shownAvatar,
            updatedAt: t,
          );
        }
      }
    }
    if (remap.isEmpty) return this;
    List<String> fix(List<String> ids) => [
      ...{for (final id in ids) remap[id] ?? id},
    ];
    DateTime later(DateTime old) {
      var best = old;
      for (final t in stamp.values) {
        if (t.isAfter(best)) best = t;
      }
      return best;
    }

    final workMap = {
      for (final e in this.workMap.entries)
        e.key: e.value.originalArtistIds.any(remap.containsKey)
            ? e.value.copyWith(
                originalArtistIds: fix(e.value.originalArtistIds),
                updatedAt: later(e.value.updatedAt),
              )
            : e.value,
    };
    final versionMap = {
      for (final e in this.versionMap.entries)
        e.key: e.value.artistIds.any(remap.containsKey)
            ? e.value.copyWith(
                artistIds: fix(e.value.artistIds),
                updatedAt: later(e.value.updatedAt),
              )
            : e.value,
    };
    return copyWith(
      artistMap: artistMap,
      workMap: workMap,
      versionMap: versionMap,
    );
  }

  /// 兩份有幾筆不一樣（同步回報用）：[other] 裡比這份新、或這份沒有的。
  int newerIn(MusicData other) {
    int c<T extends MusicRecord>(Map<String, T> mine, Map<String, T> theirs) =>
        theirs.entries
            .where(
              (e) =>
                  mine[e.key] == null ||
                  e.value.updatedAt.isAfter(mine[e.key]!.updatedAt),
            )
            .length;
    return c(artistMap, other.artistMap) +
        c(workMap, other.workMap) +
        c(versionMap, other.versionMap) +
        c(playlistMap, other.playlistMap);
  }
}
