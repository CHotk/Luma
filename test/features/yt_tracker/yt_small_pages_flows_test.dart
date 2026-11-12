import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_category_order_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_channel_log_store.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_category_order_page.dart';
import 'package:lume/features/yt_tracker/yt_channel_log_page.dart';
import 'package:lume/features/yt_tracker/yt_crypto_stats_page.dart';
import 'package:lume/features/yt_tracker/yt_playlists_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 幾個小頁的流程與邊界（2026-11-12 補到 95%）：播放清單（新建、改名、刪除、
/// 刪了回清單頁）、分類順序（拖拉存檔、看過但不喜歡固定最後、存過的順序）、
/// 頻道紀錄（每種事件的文字、沒事件時用頻道欄位補、分類篩選）、預測統計
/// （三種排序、單一頻道依評價篩、超過 30 筆）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  final now = DateTime.now();

  group('播放清單', () {
    final pl = YtPlaylist(
      id: 'pl1',
      name: '我的清單',
      createdAt: now,
      updatedAt: now,
    );

    testWidgets('清單頁：＋ 新建（取消不建）', (tester) async {
      final store = MemoryStore();
      await pumpPage(
        tester,
        store,
        () => const YtPlaylistsPage(),
        size: const Size(390, 860),
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, 3);
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, 3);
      await tester.enterText(find.byType(TextField), '追劇');
      await tester.tap(find.text('好'));
      await settle(tester, 3);
      expect(find.text('已建立「追劇」'), findsOneWidget);
      expect(find.text('追劇'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, 2);
    });

    testWidgets('一份清單：改名、刪除（取消、確定後回清單頁）', (tester) async {
      final store = MemoryStore();
      final router = await pumpPage(
        tester,
        store,
        () => const YtPlaylistPage(playlistId: 'pl1'),
        size: const Size(390, 860),
        overrides: [
          ytPlaylistsProvider.overrideWith(
            (_) => [YtPlaylist.emptyLater(), pl],
          ),
        ],
      );
      expect(router, isNotNull);
      Future<void> menu(String item) async {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await settle(tester, 4);
        await tester.tap(find.text(item));
        await settle(tester, 3);
      }

      await menu('改名');
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
      expect(find.text('我的清單'), findsWidgets);
      await menu('改名');
      await tester.enterText(find.byType(TextField), '新名字');
      await tester.tap(find.text('好'));
      await settle(tester, 3);
      expect(find.text('新名字'), findsWidgets);
      await menu('刪除清單');
      expect(find.textContaining('只是從清單拿掉'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
      await menu('刪除清單');
      await tester.tap(find.text('刪除'));
      await settle(tester, 4);
      expect(find.text('route:/yt-playlists'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, 2);
    });
  });

  testWidgets('分類順序：拖拉存檔、不喜歡固定最後；再開照存的順序', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      for (final (id, name) in [('c1', '投資'), ('c2', '音樂'), ('c3', '遊戲')]) {
        await repo.addCategory(
          YtCategory(id: id, name: name, colorValue: 0xFF5FC9A8),
        );
      }
      await repo.addCategory(
        const YtCategory(
          id: ytDislikedCategoryId,
          name: '看過但不喜歡',
          colorValue: 0xFF74738A,
        ),
      );
    });
    await pumpPage(
      tester,
      store,
      () => const YtCategoryOrderPage(),
      size: const Size(390, 860),
    );
    await settle(tester, 4);
    expect(find.text('固定最後'), findsOneWidget);
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    final before = [
      for (final t in tester.widgetList<ListTile>(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(ListTile),
        ),
      ))
        ((t.title as Text).data),
    ];
    // 第一個拖到最後（往下拖 newIndex 要多 1）、最後一個拖到最前。
    await tester.runAsync(() async {
      list.onReorder(0, before.length);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      list.onReorder(before.length - 1, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await settle(tester, 2);
    final saved = await tester.runAsync(
      () => YtCategoryOrderStore(store).load(),
    );
    expect(saved, isNotNull);
    expect(saved, isNot(contains(ytDislikedCategoryId)));

    // 再開一次：照存的順序。
    await pumpPage(
      tester,
      store,
      () => const YtCategoryOrderPage(),
      size: const Size(390, 860),
    );
    await settle(tester, 4);
    final after = [
      for (final t in tester.widgetList<ListTile>(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(ListTile),
        ),
      ))
        ((t.title as Text).data),
    ];
    expect(after.first, before.first);
  });

  group('頻道紀錄', () {
    YtChannel ch({String via = '', DateTime? deleted, DateTime? purged}) =>
        YtChannel(
          id: 'x',
          name: '頻道x',
          categoryId: null,
          youtubeChannelId: 'UCx',
          url: '',
          addedAt: now.subtract(const Duration(days: 3)),
          discoveredVia: via,
          deletedAt: deleted,
          purgedAt: purged,
        );

    YtChannelEvent ev(
      YtChannelEventType t, [
      Map<String, String> d = const {},
    ]) => YtChannelEvent(
      id: '${t.name}${d.length}',
      channelId: 'x',
      at: now,
      type: t,
      detail: d,
    );

    test('沒有事件時用頻道欄位補：挖掘加入、刪除、永久刪除', () {
      final items = buildYtChannelLog(
        channel: ch(via: '露營', deleted: now, purged: now),
        events: const [],
        watched: const [],
      );
      final texts = items.map((i) => i.text).toList();
      expect(texts, contains('加入（挖掘：露營）'));
      expect(texts, contains('刪除（移到垃圾桶）'));
      expect(texts.any((t) => t.contains('永久刪除')), isTrue);
    });

    test('每種事件都有文字', () {
      final events = [
        ev(YtChannelEventType.added, {'revived': 'true'}),
        ev(YtChannelEventType.added, {'via': '推薦', 'category': '投資'}),
        ev(YtChannelEventType.moved, {
          'from': 'A',
          'to': 'B',
          'reason': '分類刪了',
        }),
        ev(YtChannelEventType.renamed, {'from': '舊', 'to': '新'}),
        ev(YtChannelEventType.restored, {'fromPurged': 'true'}),
        ev(YtChannelEventType.restored),
        for (final t in YtChannelEventType.values) ev(t),
      ];
      final items = buildYtChannelLog(
        channel: ch(deleted: now, purged: now),
        events: events,
        watched: [
          (
            video: YoutubeVideo(
              videoId: 'v',
              title: '看過的',
              publishedAt: now,
              thumbnailUrl: '',
            ),
            openedAt: [now, now],
          ),
        ],
      );
      final texts = items.map((i) => i.text).join('｜');
      expect(texts, contains('手動新增，從永久刪除救回'));
      expect(texts, contains('加入（挖掘：推薦）'));
      expect(texts, contains('從「A」移到「B」'));
      expect(texts, contains('改名：舊 → 新'));
      expect(texts, contains('從永久刪除還原'));
      expect(texts, contains('從垃圾桶還原'));
      expect(texts, contains('從待評鑑放到一般'));
      expect(items.where((i) => i.isWatch), isNotEmpty);
    });

    for (final ids in [
      {'c1'},
      {ytUncategorizedId},
      {'c1', 'c2'},
      {'不存在'},
    ]) {
      testWidgets('全部頻道的紀錄、從分類頁進來（$ids）：只看這些分類可以切', (tester) async {
        final store = MemoryStore();
        await seedYt(tester, store);
        await pumpPage(
          tester,
          store,
          () => YtChannelLogPage(categoryIds: ids),
          size: const Size(390, 860),
        );
        await settle(tester, 4);
        final chip = find.byWidgetPredicate(
          (w) => w is FilterChip && (w.label as Text).data!.startsWith('只看'),
        );
        expect(chip, findsOneWidget);
        tester.widget<FilterChip>(chip).onSelected!(false);
        await settle(tester, 2);
        tester.widget<FilterChip>(chip).onSelected!(true);
        await settle(tester, 2);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('預測統計', () {
    Map<String, YtVideoRating> ratings() => {
      for (var i = 0; i < 42; i++)
        'v$i': YtVideoRating(
          at: now.subtract(Duration(hours: i)),
          verdict: i % 6 == 5 ? null : YtVerdict.values[i % 4],
          ratedAt: i % 6 == 5 ? null : now.subtract(Duration(hours: i)),
          claim: i % 3 == 0 ? '會漲 $i' : '',
          note: i % 4 == 0 ? '備註 $i' : '',
          dueAt: i % 6 == 5
              ? now.add(Duration(days: i % 2 == 0 ? -1 : 3))
              : null,
          channelId: ['a', 'b', 'm'][i % 3],
          channelName: '頻道${['a', 'b', 'm'][i % 3]}',
          title: '影片 $i',
        ),
    };

    testWidgets('全部頻道：三種排序、超過 30 筆', (tester) async {
      await pumpPage(
        tester,
        MemoryStore(),
        () => const YtCryptoStatsPage(
          channelNames: {'a': '頻道a', 'b': '頻道b', 'm': '頻道m'},
        ),
        size: const Size(390, 860),
        overrides: [ytVideoRatingsProvider.overrideWith((_) => ratings())],
      );
      for (final label in ['評價數 多→少', '待驗證 多→少', '準度 高→低']) {
        final f = find.textContaining(label.split(' ').first);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first, warnIfMissed: false);
          await settle(tester, 2);
        }
      }
      await tester.dragUntilVisible(
        find.textContaining('筆沒列出來'),
        find.byType(Scrollable).last,
        const Offset(0, -400),
      );
      expect(find.textContaining('筆沒列出來'), findsOneWidget);
    });

    testWidgets('單一頻道：依評價篩（全部、待驗證、每種評價、再按取消）、沒符合的', (tester) async {
      await pumpPage(
        tester,
        MemoryStore(),
        () => const YtCryptoStatsPage(channelId: 'a', channelName: '頻道a'),
        size: const Size(390, 860),
        overrides: [ytVideoRatingsProvider.overrideWith((_) => ratings())],
      );
      Future<void> chip(String text) async {
        final f = find.text(text);
        await tester.ensureVisible(f.first);
        await tester.tap(f.first, warnIfMissed: false);
        await settle(tester, 2);
      }

      await chip('🎯 待驗證');
      await chip('🎯 待驗證');
      for (final v in YtVerdict.values) {
        await chip('${v.mark} ${v.label}');
      }
      await chip('${YtVerdict.none.mark} ${YtVerdict.none.label}');
      await chip('全部');
      expect(tester.takeException(), isNull);
    });

    testWidgets('單一頻道沒有任何評價：沒有符合的影片', (tester) async {
      await pumpPage(
        tester,
        MemoryStore(),
        () => const YtCryptoStatsPage(channelId: 'zz', channelName: '頻道zz'),
        size: const Size(390, 860),
      );
      expect(find.text('沒有符合的影片'), findsWidgets);
    });
  });
}
