import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_pages.dart';
import 'package:lume/features/music/music_player.dart';
import 'package:lume/features/music/music_player_layer.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 音樂每一頁（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：有男女和沒填性別
/// 的歌手、每種版本（含不喜歡、刪掉的）、我的最愛和自己的歌單、播放紀錄、事件紀錄，
/// 每一頁每個控制項點一次（表單裡填字、按確定或取消）不會壞；沒資料時也不會壞。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Override> data({bool empty = false}) => [
    musicDataProvider.overrideWith(
      (_) => empty ? MusicData.empty : seedMusicData(),
    ),
    musicPlayLogProvider.overrideWith((_) => empty ? {} : seedMusicPlays()),
    musicEventLogProvider.overrideWith((_) => empty ? [] : seedMusicEvents()),
  ];

  final pages = <String, Widget Function()>{
    '首頁': () => const MusicHomePage(),
    '搜尋': () => const MusicSearchPage(),
    '音樂庫（歌手）': () => const MusicLibraryPage(initialTab: '歌手'),
    '音樂庫（男）': () =>
        const MusicLibraryPage(initialTab: '歌手', initialGender: 'm'),
    '音樂庫（歌曲）': () => const MusicLibraryPage(initialTab: '歌曲'),
    '音樂庫（歌單）': () => const MusicLibraryPage(initialTab: '歌單'),
    '歌手頁': () => const MusicArtistPage(artistId: 'jay'),
    '歌手頁（沒性別）': () => const MusicArtistPage(artistId: 'band'),
    '歌手頁（找不到）': () => const MusicArtistPage(artistId: '沒有'),
    '歌曲頁': () => const MusicWorkPage(workId: 'w1'),
    '歌曲頁（兩位原唱）': () => const MusicWorkPage(workId: 'w2'),
    '歌曲頁（沒原唱）': () => const MusicWorkPage(workId: 'w3'),
    '歌曲頁（找不到）': () => const MusicWorkPage(workId: '沒有'),
    '我的最愛': () => const MusicPlaylistPage(playlistId: MusicPlaylist.likedId),
    '歌單': () => const MusicPlaylistPage(playlistId: 'pl1'),
    '歌單（找不到）': () => const MusicPlaylistPage(playlistId: '沒有'),
    '事件紀錄': () => const MusicEventLogPage(),
  };

  void mockClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'https://www.youtube.com/watch?v=abcdefghijk'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  for (final MapEntry(key: name, value: page) in pages.entries) {
    testWidgets('音樂「$name」：每個控制項點一次', (tester) async {
      mockClipboard(tester);
      final router = await pumpPage(
        tester,
        MemoryStore(),
        page,
        size: const Size(390, 860),
        overrides: data(),
      );
      await pokeAll(tester, router, max: 160, deep: true);
      final e = tester.takeException();
      expect(e, isNull, reason: '$e');
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('沒有任何音樂資料：每一頁都有空狀態、不會壞', (tester) async {
    mockClipboard(tester);
    for (final page in pages.values) {
      final router = await pumpPage(
        tester,
        MemoryStore(),
        page,
        size: const Size(390, 860),
        overrides: data(empty: true),
      );
      await pokeAll(tester, router, max: 30);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  for (final expanded in [false, true]) {
    testWidgets('播放器（${expanded ? '全螢幕' : '迷你列'}）：每個控制項點一次', (tester) async {
      final router = await pumpPage(
        tester,
        MemoryStore(),
        () => const Stack(
          children: [
            MusicHomePage(),
            MusicPlayerLayer(miniBottom: 0, hideMini: false),
          ],
        ),
        size: const Size(390, 860),
        overrides: data(),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(MusicPlayerLayer)),
      );
      final p = c.read(musicPlayerProvider);
      p.playList(['v1', 'v2', 'v3'], 'v2', from: '測試');
      if (expanded) p.expanded = true;
      p.notifyListeners();
      await settle(tester, 3);
      await pokeAll(
        tester,
        router,
        max: 80,
        deep: true,
        // 只點播放器裡的，不點底下首頁的。
        skip: (w) => false,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
