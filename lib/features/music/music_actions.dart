import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/music_store.dart';
import '../../domain/models/music.dart';

/// 改音樂資料都走這裡：改記憶體裡的 [musicDataProvider]、順便存檔。每一筆都蓋
/// 上改的時間，跨裝置同步才知道誰新。
class MusicActions {
  MusicActions(this._ref);

  final WidgetRef _ref;

  MusicData get data => _ref.read(musicDataProvider);

  Future<void> _set(MusicData next) async {
    _ref.read(musicDataProvider.notifier).state = next;
    await MusicStore(_ref.read(keyValueStoreProvider)).save(next);
  }

  static String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}';

  /// 新增歌手（同名的已經有就直接用那個）。
  Future<String> ensureArtist(String name, {String avatarUrl = ''}) async {
    final n = name.trim();
    final hit = data.artists.where((a) => a.name == n).firstOrNull;
    if (hit != null) {
      if (hit.avatarUrl.isEmpty && avatarUrl.isNotEmpty) {
        await _set(
          data.putArtist(
            hit.copyWith(avatarUrl: avatarUrl, updatedAt: DateTime.now()),
          ),
        );
      }
      return hit.id;
    }
    final a = MusicArtist(
      id: _newId('a'),
      name: n,
      avatarUrl: avatarUrl,
      updatedAt: DateTime.now(),
    );
    await _set(data.putArtist(a));
    return a.id;
  }

  Future<void> renameArtist(String id, String name) async {
    final a = data.artist(id);
    if (a == null || name.trim().isEmpty) return;
    await _set(
      data.putArtist(a.copyWith(name: name.trim(), updatedAt: DateTime.now())),
    );
  }

  Future<void> editWork(
    String id, {
    String? title,
    List<String>? originalArtistIds,
  }) async {
    final w = data.work(id);
    if (w == null) return;
    await _set(
      data.putWork(
        w.copyWith(
          title: title?.trim().isEmpty ?? true ? null : title!.trim(),
          originalArtistIds: originalArtistIds,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  /// 把一部 YouTube 影片加進音樂（抄一份影片資料）。[workId] 給了就加成那首
  /// 歌的新版本，沒給就用 [newWorkTitle] 新增一首。
  Future<MusicVersion> addVersion({
    required String videoId,
    required String videoTitle,
    required String thumbnailUrl,
    required String uploaderName,
    int? durationSec,
    required DateTime publishedAt,
    String? workId,
    String newWorkTitle = '',
    List<String> originalArtistIds = const [],
    required MusicVersionType type,
    required List<String> artistIds,
    String note = '',
  }) async {
    final now = DateTime.now();
    var d = data;
    var wid = workId;
    if (wid == null || d.work(wid) == null) {
      final w = MusicWork(
        id: _newId('w'),
        title: newWorkTitle.trim().isEmpty ? videoTitle : newWorkTitle.trim(),
        originalArtistIds: originalArtistIds.isNotEmpty
            ? originalArtistIds
            : artistIds.take(1).toList(),
        updatedAt: now,
      );
      d = d.putWork(w);
      wid = w.id;
    }
    final v = MusicVersion(
      id: videoId,
      workId: wid,
      type: type,
      artistIds: artistIds,
      note: note.trim(),
      videoTitle: videoTitle,
      thumbnailUrl: thumbnailUrl,
      uploaderName: uploaderName,
      durationSec: durationSec,
      publishedAt: publishedAt,
      addedAt: now,
      updatedAt: now,
    );
    await _set(d.putVersion(v));
    return v;
  }

  Future<void> editVersion(
    String id, {
    MusicVersionType? type,
    List<String>? artistIds,
    String? workId,
    String? note,
  }) async {
    final v = data.version(id);
    if (v == null) return;
    await _set(
      data.putVersion(
        v.copyWith(
          type: type,
          artistIds: artistIds,
          workId: workId,
          note: note?.trim(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  /// 這個版本改成屬於歌名 [title] 的那首歌：已經有同名的歌就併過去，沒有就
  /// 新增一首（原唱沿用原本那首）。原本那首沒有別的版本了就拿掉。
  Future<void> moveVersionToTitle(String id, String title) async {
    final v = data.version(id);
    final t = title.trim();
    if (v == null || t.isEmpty) return;
    final old = data.work(v.workId);
    if (old != null && old.title == t) return;
    final now = DateTime.now();
    var d = data;
    var target = d.works.where((w) => w.title == t).firstOrNull;
    if (target == null) {
      target = MusicWork(
        id: _newId('w'),
        title: t,
        originalArtistIds: old?.originalArtistIds ?? const [],
        updatedAt: now,
      );
      d = d.putWork(target);
    }
    d = d.putVersion(v.copyWith(workId: target.id, updatedAt: now));
    if (old != null && d.versionsOfWork(old.id).isEmpty) {
      d = d.putWork(old.copyWith(deletedAt: now, updatedAt: now));
    }
    await _set(d);
  }

  /// 從音樂刪掉（YT 管理不動）。那首歌沒有別的版本了，歌也一起拿掉。
  Future<void> deleteVersion(String id) async {
    final v = data.version(id);
    if (v == null) return;
    final now = DateTime.now();
    var d = data.putVersion(v.copyWith(deletedAt: now, updatedAt: now));
    if (d.versionsOfWork(v.workId).isEmpty) {
      final w = d.work(v.workId);
      if (w != null) d = d.putWork(w.copyWith(deletedAt: now, updatedAt: now));
    }
    await _set(d);
  }

  bool isLiked(String versionId) => data.liked.versionIds.contains(versionId);

  Future<void> toggleLike(String versionId) async {
    final l = data.liked;
    final ids = l.versionIds.contains(versionId)
        ? l.versionIds.where((x) => x != versionId).toList()
        : [versionId, ...l.versionIds];
    await _set(
      data.putPlaylist(l.copyWith(versionIds: ids, updatedAt: DateTime.now())),
    );
  }

  Future<String> createPlaylist(String name) async {
    final p = MusicPlaylist(
      id: _newId('p'),
      name: name.trim(),
      updatedAt: DateTime.now(),
    );
    await _set(data.putPlaylist(p));
    return p.id;
  }

  Future<void> togglePlaylistItem(String playlistId, String versionId) async {
    final p = playlistId == MusicPlaylist.likedId
        ? data.liked
        : data.playlistMap[playlistId];
    if (p == null) return;
    final ids = p.versionIds.contains(versionId)
        ? p.versionIds.where((x) => x != versionId).toList()
        : [versionId, ...p.versionIds];
    await _set(
      data.putPlaylist(p.copyWith(versionIds: ids, updatedAt: DateTime.now())),
    );
  }

  Future<void> deletePlaylist(String id) async {
    final p = data.playlistMap[id];
    if (p == null || p.isLiked) return;
    final now = DateTime.now();
    await _set(data.putPlaylist(p.copyWith(deletedAt: now, updatedAt: now)));
  }
}

/// 從 YouTube 影片標題跟上傳頻道猜：哪首歌、哪一種、誰唱的。猜不準沒關係，
/// 加的面板上都能改。
class MusicGuess {
  const MusicGuess({
    required this.title,
    this.workId,
    required this.type,
    required this.artistIds,
    required this.newArtistNames,
    required this.originalArtistIds,
    required this.why,
  });

  /// 猜的歌名（新歌曲用）。
  final String title;

  /// 音樂裡已經有這首歌就給它的 id。
  final String? workId;
  final MusicVersionType type;

  /// 已經有的歌手裡，猜是誰唱的。
  final List<String> artistIds;

  /// 還沒有的歌手（建議新增，例如上傳頻道本人）。
  final List<String> newArtistNames;
  final List<String> originalArtistIds;

  /// 為什麼這樣猜（面板上寫給使用者看）。
  final String why;

  static MusicVersionType guessType(String t) {
    final s = t.toLowerCase();
    if (s.contains('翻唱') || s.contains('cover')) return MusicVersionType.cover;
    if (s.contains(' x ') || s.contains('feat') || s.contains('合唱')) {
      return MusicVersionType.duet;
    }
    if (s.contains('清唱') || s.contains('街頭')) return MusicVersionType.acapella;
    if (s.contains('live') || s.contains('演唱會') || s.contains('現場')) {
      return MusicVersionType.live;
    }
    if (s.contains('official') ||
        s.contains(' mv') ||
        s.contains('music video') ||
        s.contains('mv】') ||
        s.contains('mv]')) {
      return MusicVersionType.sing;
    }
    return MusicVersionType.other;
  }

  /// 歌名：【】《》[]「」裡的字（不是「翻唱」那種）；沒有就拿掉常見的字。
  static String guessTitle(String t, Iterable<String> names) {
    final m = RegExp(r'[【《\[「]\s*([^】》\]」]+?)\s*[】》\]」]').allMatches(t);
    for (final x in m) {
      final inside = x.group(1)!.trim();
      if (!RegExp(
        r'翻唱|cover|official|mv',
        caseSensitive: false,
      ).hasMatch(inside)) {
        return _clean(inside, names);
      }
    }
    var s = t.replaceAll(
      RegExp(
        r'翻唱|cover|official( music)? (video|mv)|lyric video|mv|live|演唱會|\|.*$|｜.*$|-.*$',
        caseSensitive: false,
      ),
      ' ',
    );
    return _clean(s, names);
  }

  static String _clean(String s, Iterable<String> names) {
    var out = s.replaceAll(RegExp(r'[【】《》\[\]「」()（）]'), ' ');
    for (final n in names) {
      if (n.isNotEmpty) out = out.replaceAll(n, ' ');
    }
    // 英文副標（例如「晴天 Sunny Day」）留中文那段就好。
    final parts = out.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final cjk = parts.where((p) => RegExp(r'[一-龥ぁ-んァ-ン]').hasMatch(p));
    return (cjk.isNotEmpty ? cjk.first : parts.firstOrNull ?? s).trim();
  }

  static MusicGuess from(
    MusicData data, {
    required String videoTitle,
    required String channelName,
  }) {
    final t = videoTitle;
    final type = guessType(t);
    final named = [
      for (final a in data.artists)
        if (a.name.isNotEmpty && (t.contains(a.name) || a.name == channelName))
          a.id,
    ];
    final title = guessTitle(t, [
      for (final a in data.artists) a.name,
      channelName,
    ]);
    final work = data.works.where((w) => w.title == title).firstOrNull;
    var by = named;
    var orig = work?.originalArtistIds ?? const <String>[];
    final newNames = <String>[];
    if (type == MusicVersionType.cover) {
      // 翻唱：原唱不算演唱者。
      final o =
          work?.originalArtistIds ??
          named.where((id) => data.artist(id)?.name != channelName).toList();
      orig = o;
      by = named.where((id) => !o.contains(id)).toList();
    }
    if (by.isEmpty &&
        channelName.isNotEmpty &&
        !data.artists.any((a) => a.name == channelName)) {
      newNames.add(channelName);
    }
    final why = [
      switch (type) {
        MusicVersionType.cover => '標題有「翻唱／cover」',
        MusicVersionType.duet => '標題有「x／feat／合唱」',
        MusicVersionType.acapella => '標題有「清唱／街頭」',
        MusicVersionType.live => '標題有「Live／演唱會／現場」',
        MusicVersionType.sing => '標題有 Official MV',
        MusicVersionType.other => '看不出是哪一種',
      },
      work != null ? '「$title」已經在音樂裡 → 加成它的新版本' : '歌名猜「$title」',
    ].join('；');
    return MusicGuess(
      title: title,
      workId: work?.id,
      type: type,
      artistIds: by,
      newArtistNames: newNames,
      originalArtistIds: orig,
      why: why,
    );
  }
}
