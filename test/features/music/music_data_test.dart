import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_actions.dart';

/// 音樂功能資料（2026-10-19）：合併、自動判斷。
void main() {
  final t0 = DateTime(2026, 10, 1), t1 = DateTime(2026, 10, 2);
  MusicArtist a(String id, String name) =>
      MusicArtist(id: id, name: name, updatedAt: t0);
  final base = MusicData.empty
      .putArtist(a('jay', '周杰倫'))
      .putArtist(a('gem', '鄧紫棋'))
      .putWork(
        MusicWork(
          id: 'w1',
          title: '晴天',
          originalArtistIds: const ['jay'],
          updatedAt: t0,
        ),
      );

  test('合併：同一筆後改的贏，刪掉的墓碑也會傳過去', () {
    final local = base.putArtist(
      a('jay', '周杰倫').copyWith(name: 'Jay', updatedAt: t1),
    );
    final cloud = base.putArtist(
      a('gem', '鄧紫棋').copyWith(deletedAt: t1, updatedAt: t1),
    );
    final m = MusicData.merge(local, cloud);
    expect(m.artist('jay')!.name, 'Jay');
    expect(m.artist('gem'), isNull);
    expect(local.newerIn(m), 1); // 本機要從雲端拿 1 筆（鄧紫棋刪了）
    expect(cloud.newerIn(m), 1); // 雲端要從本機拿 1 筆（改名）
  });

  test('json 來回一樣', () {
    final d = MusicData.fromJson(base.toJson());
    expect(d.work('w1')!.originalArtistIds, ['jay']);
    expect(d.artists.length, 2);
  });

  test('自動判斷：翻唱、已有的歌 → 新版本，原唱不算演唱者', () {
    final g = MusicGuess.from(
      base,
      videoTitle: '【翻唱】晴天 - 周杰倫｜小花 Cover',
      channelName: '小花翻唱',
    );
    expect(g.type, MusicVersionType.cover);
    expect(g.workId, 'w1');
    expect(g.originalArtistIds, ['jay']);
    expect(g.artistIds, isEmpty);
    // 不自動拿上傳頻道當新歌手（使用者自己打名字）。
    expect(g.newArtistNames, isEmpty);
  });

  test('自動判斷：官方 MV，歌名從【】拿、英文副標拿掉', () {
    final g = MusicGuess.from(
      base,
      videoTitle: 'G.E.M.鄧紫棋【光年之外 LIGHT YEARS AWAY】Official MV',
      channelName: 'G.E.M. 鄧紫棋',
    );
    expect(g.type, MusicVersionType.sing);
    expect(g.title, '光年之外');
    expect(g.workId, isNull);
    expect(g.artistIds, ['gem']);
  });

  test('自動判斷：合唱、清唱、Live', () {
    expect(
      MusicGuess.guessType('五月天 x 周杰倫【倔強】演唱會合唱 Live'),
      MusicVersionType.duet,
    );
    expect(MusicGuess.guessType('周杰倫 突襲現場 清唱【稻香】'), MusicVersionType.acapella);
    expect(MusicGuess.guessType('周杰倫【晴天】2019 演唱會 Live'), MusicVersionType.live);
  });
}
