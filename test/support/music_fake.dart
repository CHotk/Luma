import 'package:lume/data/repositories/music_event_log_store.dart';
import 'package:lume/data/repositories/music_play_log_store.dart';
import 'package:lume/domain/models/music.dart';

/// 測試用的一整份音樂資料：三個歌手（男、女、沒填性別，有大頭貼、有裁切）、
/// 三首歌（一首有兩位原唱、一首沒原唱）、每種版本各一個（含不喜歡的、刪掉的、
/// 有發行年、有備註、有時長），兩份歌單（我的最愛、自己建的），刪掉的歌手／歌／歌單。
final musicT = DateTime(2026, 10, 1);

MusicVersion musicVersion(
  String id,
  String work,
  MusicVersionType type,
  List<String> by, {
  int? year,
  String note = '',
  int? duration,
  DateTime? disliked,
  DateTime? deleted,
  int daysAgo = 0,
}) => MusicVersion(
  id: id,
  workId: work,
  type: type,
  artistIds: by,
  videoTitle: '影片 $id',
  thumbnailUrl: '',
  uploaderName: '頻道 $id',
  publishedAt: musicT.subtract(Duration(days: daysAgo * 30)),
  addedAt: musicT.subtract(Duration(days: daysAgo)),
  updatedAt: musicT,
  releaseYear: year,
  note: note,
  durationSec: duration,
  dislikedAt: disliked,
  deletedAt: deleted,
);

MusicData seedMusicData() {
  var d = MusicData.empty
      .putArtist(
        MusicArtist(
          id: 'jay',
          name: '周杰倫',
          gender: 'm',
          avatarUrls: const ['https://img/jay1.png', 'https://img/jay2.png'],
          shownAvatar: 1,
          crops: const {
            'https://img/jay2.png': [0.1, -0.1, 1.4],
          },
          updatedAt: musicT,
        ),
      )
      .putArtist(
        MusicArtist(id: 'hana', name: '小花', gender: 'f', updatedAt: musicT),
      )
      .putArtist(MusicArtist(id: 'band', name: '樂團', updatedAt: musicT))
      .putArtist(
        MusicArtist(
          id: 'gone',
          name: '刪掉的歌手',
          updatedAt: musicT,
          deletedAt: musicT,
        ),
      )
      .putWork(
        MusicWork(
          id: 'w1',
          title: '晴天',
          originalArtistIds: const ['jay'],
          updatedAt: musicT,
        ),
      )
      .putWork(
        MusicWork(
          id: 'w2',
          title: '雙人舞',
          originalArtistIds: const ['jay', 'hana'],
          updatedAt: musicT,
        ),
      )
      .putWork(MusicWork(id: 'w3', title: '無名曲', updatedAt: musicT))
      .putWork(
        MusicWork(
          id: 'wx',
          title: '刪掉的歌',
          updatedAt: musicT,
          deletedAt: musicT,
        ),
      );
  final versions = [
    musicVersion(
      'v1',
      'w1',
      MusicVersionType.sing,
      ['jay'],
      year: 2003,
      duration: 269,
    ),
    musicVersion('v2', 'w1', MusicVersionType.cover, ['hana'], daysAgo: 3),
    musicVersion('v3', 'w2', MusicVersionType.duet, [
      'jay',
      'hana',
    ], year: 2010),
    musicVersion('v4', 'w1', MusicVersionType.live, ['jay'], note: '演唱會'),
    musicVersion('v5', 'w3', MusicVersionType.acapella, ['band'], daysAgo: 40),
    musicVersion(
      'v6',
      'w3',
      MusicVersionType.other,
      const [],
      disliked: musicT,
    ),
    musicVersion('v7', 'w2', MusicVersionType.cover, ['band'], deleted: musicT),
  ];
  for (final v in versions) {
    d = d.putVersion(v);
  }
  d = d
      .putPlaylist(
        MusicPlaylist(
          id: MusicPlaylist.likedId,
          name: '我的最愛',
          versionIds: const ['v1', 'v3'],
          updatedAt: musicT,
        ),
      )
      .putPlaylist(
        MusicPlaylist(
          id: 'pl1',
          name: '開車聽',
          versionIds: const ['v2', 'v4', 'v5'],
          updatedAt: musicT,
        ),
      )
      .putPlaylist(
        MusicPlaylist(
          id: 'pl0',
          name: '刪掉的歌單',
          updatedAt: musicT,
          deletedAt: musicT,
        ),
      );
  return d;
}

/// 播放紀錄：v1 很多次（不同方式、不同來源）、v2 一次。
Map<String, List<MusicPlay>> seedMusicPlays() {
  final now = DateTime.now();
  return {
    'v1': [
      for (var i = 0; i < 12; i++)
        MusicPlay(
          at: now.subtract(Duration(hours: i * 5)),
          from: i.isEven ? '歌手頁' : '首頁',
          mode: i % 3 == 0 ? 'youtube' : 'embedded',
        ),
    ],
    'v2': [MusicPlay(at: now.subtract(const Duration(days: 2)))],
    'v3': [MusicPlay(at: now.subtract(const Duration(days: 40)))],
  };
}

List<MusicEvent> seedMusicEvents() => [
  for (var i = 0; i < 6; i++)
    MusicEvent(
      id: 'e$i',
      at: DateTime.now().subtract(Duration(days: i)),
      text: '事件 $i',
      versionId: i.isEven ? 'v1' : null,
    ),
];
