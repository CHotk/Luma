import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/music_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/add_to_music_sheet.dart';
import 'package:lume/features/music/music_pages.dart';
import 'package:lume/features/music/music_player.dart';

/// 音樂功能畫面（2026-10-19）。
void main() {
  final t = DateTime(2026, 10, 1);
  MusicVersion v(String id, String w, MusicVersionType type, List<String> by) =>
      MusicVersion(
        id: id,
        workId: w,
        type: type,
        artistIds: by,
        videoTitle: '影片 $id',
        thumbnailUrl: '',
        uploaderName: '頻道',
        publishedAt: t,
        addedAt: t,
        updatedAt: t,
      );
  final seed = MusicData.empty
      .putArtist(MusicArtist(id: 'jay', name: '周杰倫', updatedAt: t))
      .putArtist(MusicArtist(id: 'hana', name: '小花', updatedAt: t))
      .putWork(MusicWork(id: 'w1', title: '晴天', originalArtistIds: const ['jay'], updatedAt: t))
      .putVersion(v('v1', 'w1', MusicVersionType.sing, ['jay']))
      .putVersion(v('v2', 'w1', MusicVersionType.cover, ['hana']));

  Future<ProviderContainer> pump(WidgetTester tester, Widget page, {MusicData? data}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        musicDataProvider.overrideWith((ref) => data ?? seed),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: MaterialApp(home: page)),
    );
    await tester.pump();
    return c;
  }

  testWidgets('音樂庫：歌手、歌曲兩種看法', (tester) async {
    await pump(tester, const MusicLibraryPage(initialTab: '歌手'));
    expect(find.text('周杰倫'), findsOneWidget);
    expect(find.textContaining('演唱 1'), findsOneWidget);
    await tester.tap(find.text('歌曲'));
    await tester.pump();
    expect(find.text('晴天'), findsOneWidget);
    expect(find.textContaining('2 個版本'), findsOneWidget);
  });

  testWidgets('歌曲頁：照種類分段，列出誰唱的', (tester) async {
    await pump(tester, const MusicWorkPage(workId: 'w1'));
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('依序聽每個版本'), findsOneWidget);
    expect(find.text('小花'), findsWidgets);
    expect(find.text('翻唱'), findsWidgets);
  });

  testWidgets('歌手頁、首頁、空的音樂庫畫得出來', (tester) async {
    await pump(tester, const MusicArtistPage(artistId: 'jay'));
    expect(find.text('隨機播放'), findsOneWidget);
    expect(find.text('他原唱的歌'), findsOneWidget);
    await pump(tester, const MusicHomePage());
    expect(find.text('快速選曲'), findsOneWidget);
    await pump(tester, const MusicHomePage(), data: MusicData.empty);
    expect(find.text('音樂庫還是空的'), findsOneWidget);
  });

  testWidgets('加到音樂功能：已有的歌 → 加成新版本，存檔', (tester) async {
    late WidgetRef r;
    final c = await pump(
      tester,
      Consumer(
        builder: (context, ref, _) {
          r = ref;
          return Scaffold(
            body: TextButton(
              onPressed: () => showAddToMusicSheet(
                context,
                ref,
                videoId: 'v3',
                videoTitle: '周杰倫【晴天】2019 演唱會 Live',
                thumbnailUrl: '',
                channelName: '周杰倫',
                publishedAt: t,
              ),
              child: const Text('加'),
            ),
          );
        },
      ),
    );
    expect(r, isNotNull);
    await tester.tap(find.text('加'));
    await tester.pumpAndSettle();
    expect(find.textContaining('音樂裡已經有《晴天》'), findsOneWidget);
    await tester.ensureVisible(find.text('加到《晴天》'));
    await tester.tap(find.text('加到《晴天》'));
    await tester.pumpAndSettle();
    final d = c.read(musicDataProvider);
    expect(d.version('v3')!.workId, 'w1');
    expect(d.version('v3')!.type, MusicVersionType.live);
    expect(d.version('v3')!.artistIds, ['jay']);
    expect(c.read(musicVideoIdsProvider), contains('v3'));
    final saved = await MusicStore(c.read(keyValueStoreProvider)).load();
    expect(saved.version('v3'), isNotNull);
    await tester.pump(const Duration(seconds: 4));
  });

  test('播放佇列：下一首、重複、刪掉正在播的', () {
    final p = MusicPlayer();
    p.playList(['a', 'b', 'c'], 'b');
    expect(p.current, 'b');
    p.next();
    expect(p.current, 'c');
    p.next(auto: true); // 最後一首播完、不重複 → 停
    expect(p.playing, isFalse);
    p.cycleRepeat(); // 重複整個佇列
    p.next(auto: true);
    expect(p.current, 'a');
    p.playNext('c');
    expect(p.queue, ['a', 'c', 'b']);
    p.removeFromQueue('a');
    expect(p.current, 'c');
    p.close();
    expect(p.current, isNull);
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}
