import '../../domain/simplified_to_traditional.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/music_event_log_store.dart';
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

  /// 寫一筆異動紀錄（2026-10-19 使用者要求：加了哪首、改了什麼都要記，一筆
  /// 都不刪）。
  Future<void> _log(String text, {String? versionId}) async {
    final now = DateTime.now();
    final e = MusicEvent(
      id: 'e${now.microsecondsSinceEpoch}',
      at: now,
      text: text,
      versionId: versionId,
    );
    final next = [..._ref.read(musicEventLogProvider), e];
    _ref.read(musicEventLogProvider.notifier).state = next;
    await MusicEventLogStore(_ref.read(keyValueStoreProvider)).save(next);
  }

  static String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}';

  String _names(List<String> ids) =>
      [for (final id in ids) data.artist(id)?.name ?? '?'].join('、');

  String _orNone(String s) => s.isEmpty ? '（沒有）' : s;

  String _title(MusicVersion v) => data.work(v.workId)?.title ?? v.videoTitle;

  static List<String> _clean(List<String> urls) => [
    for (final u in urls)
      if (u.trim().isNotEmpty) u.trim(),
  ].take(MusicArtist.maxAvatars).toList();

  /// 新增歌手（同名的已經有就直接用那個；那個還沒有大頭貼就補上）。
  Future<String> ensureArtist(
    String name, {
    List<String> avatarUrls = const [],
    int shownAvatar = 0,
    String? gender,
  }) async {
    final n = name.trim();
    final urls = _clean(avatarUrls);
    final hit = data.artists.where((a) => a.name == n).firstOrNull;
    if (hit != null) {
      // 使用者特地貼了大頭貼網址：跟現有的不一樣就以這次為準（以前已經有大頭貼
      // 就整個忽略，貼了沒存、也就不會同步）。
      if (gender != null && gender != hit.gender) {
        await _set(
          data.putArtist(
            hit.copyWith(gender: gender, updatedAt: DateTime.now()),
          ),
        );
      }
      if (urls.isNotEmpty && urls.join('|') != hit.avatarUrls.join('|')) {
        await _log('歌手「${hit.name}」大頭貼改成 ${urls.length} 張');
        await _set(
          data.putArtist(
            hit.copyWith(
              avatarUrls: urls,
              shownAvatar: shownAvatar,
              updatedAt: DateTime.now(),
            ),
          ),
        );
      }
      return hit.id;
    }
    final a = MusicArtist(
      id: _newId('a'),
      name: n,
      avatarUrls: urls,
      shownAvatar: shownAvatar.clamp(0, urls.isEmpty ? 0 : urls.length - 1),
      gender: gender,
      updatedAt: DateTime.now(),
    );
    await _set(data.putArtist(a));
    await _log('新增歌手「$n」${urls.isEmpty ? '' : '（大頭貼 ${urls.length} 張）'}');
    return a.id;
  }

  /// 改歌手的名字、大頭貼（好幾張、照順序）、顯示哪一張（2026-10-19 使用者
  /// 要求：歌手自己打名字、貼網址，不從 YT 頻道挑）。
  Future<void> updateArtist(
    String id, {
    required String name,
    required List<String> avatarUrls,
    required int shownAvatar,
    String? gender,
  }) async {
    final a = data.artist(id);
    final n = name.trim();
    final urls = _clean(avatarUrls);
    final shown = shownAvatar.clamp(0, urls.isEmpty ? 0 : urls.length - 1);
    if (a == null || n.isEmpty) return;
    final changes = <String>[
      if (n != a.name) '名字「${a.name}」→「$n」',
      if (urls.join('|') != a.avatarUrls.join('|')) '大頭貼改成 ${urls.length} 張',
      if (urls.isNotEmpty && shown != a.shownAvatar) '改顯示第 ${shown + 1} 張大頭貼',
      if (gender != null && gender != a.gender)
        '性別改成${gender == 'm' ? '男' : '女'}',
    ];
    if (changes.isEmpty) return;
    await _set(
      data.putArtist(
        a.copyWith(
          name: n,
          avatarUrls: urls,
          shownAvatar: shown,
          gender: gender,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    await _log('歌手「${a.name}」：${changes.join('，')}');
  }

  Future<void> renameArtist(String id, String name) async {
    final a = data.artist(id);
    final n = name.trim();
    if (a == null || n.isEmpty || n == a.name) return;
    await _set(data.putArtist(a.copyWith(name: n, updatedAt: DateTime.now())));
    await _log('歌手「${a.name}」改名成「$n」');
  }

  Future<void> editWork(
    String id, {
    String? title,
    List<String>? originalArtistIds,
  }) async {
    final w = data.work(id);
    if (w == null) return;
    final t = title?.trim();
    final newTitle = t == null || t.isEmpty ? w.title : t;
    final newOrig = originalArtistIds ?? w.originalArtistIds;
    final oldNames = _names(w.originalArtistIds), newNames = _names(newOrig);
    final changes = <String>[
      if (newTitle != w.title) '歌名「${w.title}」→「$newTitle」',
      if (oldNames != newNames)
        '原唱 ${_orNone(oldNames)} → ${_orNone(newNames)}',
    ];
    if (changes.isEmpty) return;
    await _set(
      data.putWork(
        w.copyWith(
          title: newTitle,
          originalArtistIds: newOrig,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    await _log('《${w.title}》：${changes.join('，')}');
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
    int? releaseYear,
  }) async {
    final now = DateTime.now();
    var d = data;
    var wid = workId;
    var isNewWork = false;
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
      isNewWork = true;
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
      releaseYear: releaseYear,
      publishedAt: publishedAt,
      addedAt: now,
      updatedAt: now,
    );
    await _set(d.putVersion(v));
    final n = note.trim();
    await _log(
      '加入《${d.work(wid)!.title}》${isNewWork ? '（新歌曲）' : ''}：'
      '${type.label}・${_names(artistIds)}${n.isEmpty ? '' : '・$n'}，'
      '來自「$uploaderName」',
      versionId: videoId,
    );
    return v;
  }

  Future<void> editVersion(
    String id, {
    MusicVersionType? type,
    List<String>? artistIds,
    String? workId,
    String? note,
    int? releaseYear,
    bool setYear = false,
  }) async {
    final v = data.version(id);
    if (v == null) return;
    final n = note?.trim();
    final yearChanged = setYear && releaseYear != v.releaseYear;
    final changes = <String>[
      if (type != null && type != v.type) '種類 ${v.type.label} → ${type.label}',
      if (artistIds != null && _names(artistIds) != _names(v.artistIds))
        '誰唱 ${_names(v.artistIds)} → ${_names(artistIds)}',
      if (n != null && n != v.note) '備註「${_orNone(v.note)}」→「${_orNone(n)}」',
      if (yearChanged) '發行年份 ${v.releaseYear ?? '—'} → ${releaseYear ?? '—'}',
    ];
    if (changes.isEmpty && workId == null) return;
    await _set(
      data.putVersion(
        v.copyWith(
          type: type,
          artistIds: artistIds,
          workId: workId,
          note: n,
          releaseYear: yearChanged ? releaseYear : null,
          clearReleaseYear: yearChanged && releaseYear == null,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    if (changes.isNotEmpty) {
      await _log('《${_title(v)}》：${changes.join('，')}', versionId: id);
    }
  }

  /// 這個版本改成屬於歌名 [title] 的那首歌：已經有同名的歌就併過去，沒有就
  /// 新增一首（原唱沿用原本那首）。原本那首沒有別的版本了就收起來（版本
  /// 一直都在，只是歌曲換了一首）。
  Future<void> moveVersionToTitle(String id, String title) async {
    final v = data.version(id);
    final t = title.trim();
    if (v == null || t.isEmpty) return;
    final old = data.work(v.workId);
    if (old != null && old.title == t) return;
    final now = DateTime.now();
    var d = data;
    var target = d.works.where((w) => w.title == t).firstOrNull;
    final merged = target != null;
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
    await _log(
      '歌名「${old?.title ?? v.videoTitle}」→「$t」${merged ? '（併到已有的《$t》）' : ''}',
      versionId: id,
    );
  }

  /// 不喜歡／取消不喜歡（音樂不做刪除，見 [MusicVersion.dislikedAt]）。
  Future<void> toggleDislike(String id) async {
    final v = data.version(id);
    if (v == null) return;
    final to = !v.disliked;
    await _set(
      data.putVersion(v.copyWith(disliked: to, updatedAt: DateTime.now())),
    );
    if (to) {
      // 不喜歡就不留在「喜歡的歌」。
      final l = data.liked;
      if (l.versionIds.contains(id)) {
        await _set(
          data.putPlaylist(
            l.copyWith(
              versionIds: l.versionIds.where((x) => x != id).toList(),
              updatedAt: DateTime.now(),
            ),
          ),
        );
      }
    }
    await _log(
      '《${_title(v)}》（${_names(v.artistIds)}）${to ? '標成不喜歡' : '取消不喜歡'}',
      versionId: id,
    );
  }

  bool isLiked(String versionId) => data.liked.versionIds.contains(versionId);

  Future<void> toggleLike(String versionId) =>
      togglePlaylistItem(MusicPlaylist.likedId, versionId);

  Future<String> createPlaylist(String name) async {
    final p = MusicPlaylist(
      id: _newId('p'),
      name: name.trim(),
      updatedAt: DateTime.now(),
    );
    await _set(data.putPlaylist(p));
    await _log('新增歌單「${p.name}」');
    return p.id;
  }

  Future<void> togglePlaylistItem(String playlistId, String versionId) async {
    final p = playlistId == MusicPlaylist.likedId
        ? data.liked
        : data.playlistMap[playlistId];
    final v = data.version(versionId);
    if (p == null) return;
    final removing = p.versionIds.contains(versionId);
    final ids = removing
        ? p.versionIds.where((x) => x != versionId).toList()
        : [versionId, ...p.versionIds];
    await _set(
      data.putPlaylist(p.copyWith(versionIds: ids, updatedAt: DateTime.now())),
    );
    final name = v == null
        ? versionId
        : '《${_title(v)}》（${_names(v.artistIds)}）';
    await _log(
      p.isLiked
          ? '$name${removing ? '取消喜歡' : '標成喜歡'}'
          : '$name${removing ? '移出' : '加進'}歌單「${p.name}」',
      versionId: versionId,
    );
  }

  Future<void> deletePlaylist(String id) async {
    final p = data.playlistMap[id];
    if (p == null || p.isLiked) return;
    final now = DateTime.now();
    await _set(data.putPlaylist(p.copyWith(deletedAt: now, updatedAt: now)));
    await _log('刪掉歌單「${p.name}」（歌都還在）');
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
    // 簡體標題先轉繁體再猜歌名（2026-10-21 使用者要求）
    final t = toTraditional(videoTitle);
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
    // 不自動拿上傳頻道當新歌手（2026-10-19 使用者要求：歌手自己打名字跟大頭貼）。
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
