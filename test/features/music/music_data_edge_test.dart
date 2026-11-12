import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/music_event_log_store.dart';
import 'package:lume/data/repositories/music_play_log_store.dart';
import 'package:lume/data/repositories/music_play_mode_store.dart';
import 'package:lume/domain/models/music.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 音樂資料的邊界（2026-11-12 補到 95%）：事件紀錄存讀、壞資料、聯集去重；播放紀錄
/// 壞資料；播放方式存讀（預設 YouTube）；同名歌手合併（大頭貼收進來、歌與原唱改指、
/// 只有一個的不動、空名字不算）。
void main() {
  test('事件紀錄：存讀、沒存過、壞掉的 json、缺時間的那筆丟掉、聯集照 id 去重', () async {
    final s = MemoryStore();
    final store = MusicEventLogStore(s);
    expect(await store.load(), isEmpty);
    final events = seedMusicEvents();
    await store.save(events);
    final back = await store.load();
    expect(back.map((e) => e.id), events.map((e) => e.id));
    expect(back.first.versionId, 'v1');
    s.data['music.event_log.v1'] = '{壞掉';
    expect(await store.load(), isEmpty);
    final decoded = MusicEventLogStore.decode(
      '[{"at":"bad"}, 3, {"at":"2026-10-01T00:00:00Z","text":"沒 id"}]',
    );
    expect(decoded, hasLength(1));
    expect(decoded.single.id, isNotEmpty);
    final merged = MusicEventLogStore.merge(events, [
      events.first,
      MusicEvent(id: 'new', at: DateTime(2000), text: '很舊的'),
    ]);
    expect(merged.length, events.length + 1);
    expect(merged.first.id, 'new');
  });

  test('播放紀錄：壞掉的 json 當沒有', () async {
    final s = MemoryStore();
    final store = MusicPlayLogStore(s);
    expect(await store.load(), isEmpty);
    s.data['music.play_log.v1'] = '不是 json';
    expect(await store.load(), isEmpty);
  });

  test('播放方式：預設 YouTube、存了記住', () async {
    final store = MusicPlayModeStore(MemoryStore());
    expect(await store.load(), MusicPlayMode.youtube);
    await store.save(MusicPlayMode.embedded);
    expect(await store.load(), MusicPlayMode.embedded);
    expect(MusicPlayMode.fromName(null), MusicPlayMode.youtube);
  });

  test('同名歌手合併：留 id 最小的、大頭貼收進來、歌與原唱改指過去', () {
    var d = seedMusicData()
        .putArtist(
          MusicArtist(
            id: 'zjay',
            name: '周杰倫',
            avatarUrls: const ['https://img/z.png', 'https://img/jay1.png'],
            shownAvatar: 1,
            updatedAt: musicT.add(const Duration(days: 1)),
          ),
        )
        .putArtist(MusicArtist(id: 'aa', name: '小花', updatedAt: musicT))
        .putArtist(MusicArtist(id: 'blank', name: '  ', updatedAt: musicT))
        .putArtist(MusicArtist(id: 'blank2', name: '', updatedAt: musicT));
    d = d.putVersion(
      musicVersion('vz', 'w1', MusicVersionType.cover, ['zjay', 'jay']),
    );
    d = d.putWork(
      MusicWork(
        id: 'wz',
        title: '新',
        originalArtistIds: const ['zjay'],
        updatedAt: musicT,
      ),
    );
    final m = d.mergeSameNameArtists();
    expect(m.artistMap['zjay']!.deletedAt, isNotNull);
    expect(m.artist('jay')!.avatarUrls, contains('https://img/z.png'));
    expect(m.version('vz')!.artistIds, ['jay']);
    expect(m.work('wz')!.originalArtistIds, ['jay']);
    // 小花：id 'aa' 比 'hana' 小，留 aa；hana 的版本改指 aa。
    expect(m.artistMap['hana']!.deletedAt, isNotNull);
    expect(m.version('v2')!.artistIds, ['aa']);
    // 沒有同名的：原封不動。
    final single = MusicData.empty.putArtist(
      MusicArtist(id: 'x', name: '獨一無二', updatedAt: musicT),
    );
    expect(identical(single.mergeSameNameArtists(), single), isTrue);
    // 留下的那個本來沒大頭貼：沿用捐的那個顯示第幾張。
    final noPic = MusicData.empty
        .putArtist(MusicArtist(id: 'a1', name: '同', updatedAt: musicT))
        .putArtist(
          MusicArtist(
            id: 'a2',
            name: '同',
            avatarUrls: const ['https://img/1.png', 'https://img/2.png'],
            shownAvatar: 1,
            updatedAt: musicT,
          ),
        )
        .mergeSameNameArtists();
    expect(noPic.artist('a1')!.shownAvatar, 1);
  });
}
