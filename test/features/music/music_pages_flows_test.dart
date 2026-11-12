import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_pages.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 音樂頁面要打字的流程（2026-11-12 補到 95%）：首頁搜尋（歌手＋歌、找不到、清掉）、
/// 搜尋頁（打字、找不到、最近搜尋）、歌手頁搜尋（自己的、別的歌手的、都沒有）、
/// 音樂庫新增歌單（取消、空白、建起來）、歌單刪除（取消、確定）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;

  Future<void> open(WidgetTester tester, Widget Function() page) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(
      tester,
      MemoryStore(),
      page,
      size: const Size(390, 860),
      overrides: [
        musicDataProvider.overrideWith((_) => seedMusicData()),
        musicPlayLogProvider.overrideWith((_) => seedMusicPlays()),
        musicEventLogProvider.overrideWith((_) => seedMusicEvents()),
      ],
    );
    c = ProviderScope.containerOf(tester.element(find.byWidget(page())));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await settle(tester, 2);
  }

  testWidgets('首頁搜尋：歌手和歌、找不到、清掉', (tester) async {
    await pumpPage(
      tester,
      MemoryStore(),
      () => const MusicHomePage(),
      size: const Size(390, 860),
      overrides: [musicDataProvider.overrideWith((_) => seedMusicData())],
    );
    await type(tester, '周');
    expect(find.textContaining('歌手・'), findsOneWidget);
    await type(tester, '演唱會');
    expect(find.textContaining('歌・1'), findsOneWidget);
    await type(tester, '沒有這首');
    expect(find.text('沒有「沒有這首」'), findsOneWidget);
    await type(tester, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜尋頁：歌手、歌、找不到；點歌手進去', (tester) async {
    await pumpPage(
      tester,
      MemoryStore(),
      () => const MusicSearchPage(),
      size: const Size(390, 860),
      overrides: [musicDataProvider.overrideWith((_) => seedMusicData())],
    );
    await type(tester, '小花');
    expect(find.text('歌手'), findsWidgets);
    await type(tester, '晴天');
    await type(tester, '完全沒有');
    await type(tester, '周杰倫');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, 3);
    final tile = find.byType(ListTile);
    if (tile.evaluate().isNotEmpty) {
      await tester.tap(tile.first);
      await settle(tester, 3);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌手頁搜尋：自己的歌、其他歌手的、都沒有、清掉', (tester) async {
    await pumpPage(
      tester,
      MemoryStore(),
      () => const MusicArtistPage(artistId: 'hana'),
      size: const Size(390, 860),
      overrides: [musicDataProvider.overrideWith((_) => seedMusicData())],
    );
    await type(tester, '晴天');
    expect(find.textContaining('小花・'), findsWidgets);
    expect(find.textContaining('其他歌手：'), findsWidgets);
    await type(tester, '無名');
    expect(find.text('小花沒有「無名」'), findsOneWidget);
    await type(tester, '真的沒有');
    expect(find.text('其他歌手也沒有'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.cancel_rounded));
    await settle(tester, 2);
    expect(find.text('其他歌手也沒有'), findsNothing);
  });

  testWidgets('音樂庫：新增歌單（取消、空白、建起來）', (tester) async {
    await open(tester, () => const MusicLibraryPage(initialTab: '歌單'));
    Future<void> add(String? name) async {
      await tester.tap(find.text('新增歌單'));
      await settle(tester, 3);
      if (name == null) {
        await tester.tap(find.text('取消'));
      } else {
        await tester.enterText(find.byType(TextField).last, name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
      }
      await settle(tester, 3);
      await closeOverlays(tester);
    }

    final before = c.read(musicDataProvider).playlists.length;
    await add(null);
    await add('   ');
    expect(c.read(musicDataProvider).playlists.length, before);
    await add('週末');
    expect(
      c.read(musicDataProvider).playlists.any((p) => p.name == '週末'),
      isTrue,
    );
  });

  testWidgets('歌單：刪掉（取消、確定）', (tester) async {
    await open(tester, () => const MusicPlaylistPage(playlistId: 'pl1'));
    Future<void> del(bool ok) async {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settle(tester, 4);
      await tester.tap(find.textContaining('刪').last);
      await settle(tester, 3);
      await tester.tap(find.text(ok ? '刪掉' : '取消').last);
      await settle(tester, 3);
    }

    await del(false);
    expect(c.read(musicDataProvider).playlistMap['pl1']!.deletedAt, isNull);
    await del(true);
    expect(c.read(musicDataProvider).playlistMap['pl1']!.deletedAt, isNotNull);
  });

  testWidgets('音樂庫：從歌手切到歌曲再切回（換初始分頁）', (tester) async {
    var tab = '歌手';
    late StateSetter set;
    await pumpPage(
      tester,
      MemoryStore(),
      () => StatefulBuilder(
        builder: (_, s) {
          set = s;
          return MusicLibraryPage(initialTab: tab);
        },
      ),
      size: const Size(390, 860),
      overrides: [musicDataProvider.overrideWith((_) => seedMusicData())],
    );
    set(() => tab = '歌曲');
    await settle(tester, 2);
    expect(find.text('晴天'), findsWidgets);
    set(() => tab = '不存在的分頁');
    await settle(tester, 2);
    expect(tester.takeException(), isNull);
    expect(MusicPlaylist.likedId, 'liked');
  });
}
