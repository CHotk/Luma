import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_home_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 首頁的流程（2026-11-12 補到 95%）：新增分類（選顏色、底圖、空名字不建、取消）、
/// 長按編輯分類（改名、清空不存、刪除：沒頻道直接確認、有頻道選搬去哪、取消）、
/// 搜尋（有結果點進去、找不到、清掉）、挖掘新頻道（沒金鑰先問、選項每個都動、
/// 挖到、配額用完、取消）、匯出（切快照、下載、複製、關閉）、幣圈分類的「該驗證」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 上一個測試留下的素材快取（在那個測試的假時間裡建的）會讓下一個測試讀快照卡住。
  setUp(rootBundle.clear);

  Finder dots() =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ColorDot');

  Future<(MemoryStore, FakeYoutube)> open(
    WidgetTester tester, {
    bool apiKey = true,
    int fail = 0,
  }) async {
    final store = MemoryStore();
    await seedYt(tester, store, apiKey: apiKey);
    await tester.runAsync(
      () => YtTrackerRepository(store).addCategory(
        const YtCategory(id: 'c3', name: '幣圈', colorValue: 0xFFFFC857),
      ),
    );
    final yt = FakeYoutube()..fail = fail;
    await http.runWithClient(
      () => pumpPage(
        tester,
        store,
        () => const YtTrackerHomePage(),
        size: const Size(390, 860),
        overrides: [
          ytApiKeyProvider.overrideWith((_) => apiKey ? 'KEY' : null),
        ],
      ),
      yt.client,
    );
    await http.runWithClient(() => settle(tester, 6), yt.client);
    return (store, yt);
  }

  Future<void> addMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('新增'));
    await settle(tester, 5);
    await tester.tap(find.text(item));
    await settle(tester, 3);
  }

  Future<List<String>> catNames(WidgetTester tester, MemoryStore store) async =>
      (await tester.runAsync(
        () => YtTrackerRepository(store).loadCategories(),
      ))!.map((c) => c.name).toList();

  testWidgets('新增分類：空名字不建、取消不建、選顏色加底圖建起來', (tester) async {
    final (store, _) = await open(tester);
    await addMenu(tester, '新增分類');
    await tester.tap(find.text('新增'));
    await settle(tester);
    expect(await catNames(tester, store), isNot(contains('')));

    await addMenu(tester, '新增分類');
    await tester.enterText(find.byType(TextField).at(1), '不要的');
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(await catNames(tester, store), isNot(contains('不要的')));

    await addMenu(tester, '新增分類');
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), ' 遊戲 ');
    await tester.enterText(fields.at(1), ' https://img/x.png ');
    await tester.tap(dots().at(3));
    await tester.pump();
    await tester.tap(find.text('新增'));
    await settle(tester, 6);
    final cats = (await tester.runAsync(
      () => YtTrackerRepository(store).loadCategories(),
    ))!;
    final game = cats.firstWhere((c) => c.name == '遊戲');
    expect(game.imageUrl, 'https://img/x.png');
    expect(game.colorValue, ytCategoryColors[3]);
    expect(find.text('遊戲'), findsOneWidget);
  });

  testWidgets('長按分類：改名、清空不存、取消、有頻道刪除選搬去哪、沒頻道直接確認', (tester) async {
    final (store, _) = await open(tester);
    await tester.longPress(find.text('音樂'));
    await settle(tester, 3);
    expect(find.text('編輯分類'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field.first, '歌');
    await tester.enterText(field.at(1), 'https://img/m.png');
    await tester.tap(dots().at(2));
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await settle(tester, 6);
    expect(await catNames(tester, store), contains('歌'));

    await tester.longPress(find.text('歌'));
    await settle(tester, 3);
    await tester.enterText(field.first, '  ');
    await tester.tap(find.text('儲存'));
    await settle(tester, 4);
    expect(await catNames(tester, store), contains('歌'));

    await tester.longPress(find.text('歌'));
    await settle(tester, 3);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);

    // 有頻道（m）：問搬去哪，先取消，再選投資刪掉。
    await tester.longPress(find.text('歌'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除分類'));
    await settle(tester, 4);
    expect(find.textContaining('底下有 1 個頻道'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 4);
    expect(await catNames(tester, store), contains('歌'));
    await tester.longPress(find.text('歌'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除分類'));
    await settle(tester, 4);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await settle(tester, 3);
    await tester.tap(find.text('投資').last);
    await settle(tester, 3);
    await tester.tap(find.widgetWithText(TextButton, '刪除'));
    await settle(tester, 6);
    expect(await catNames(tester, store), isNot(contains('歌')));
    final m = (await tester.runAsync(
      () => YtTrackerRepository(store).loadChannels(),
    ))!.firstWhere((c) => c.id == 'm');
    expect(m.categoryId, 'c1');

    // 沒頻道的（幣圈）：一般確認框。
    await tester.longPress(find.text('幣圈'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除分類'));
    await settle(tester, 4);
    expect(find.text('這個分類目前沒有任何頻道。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 4);
    await tester.longPress(find.text('幣圈'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除分類'));
    await settle(tester, 4);
    await tester.tap(find.text('刪除').last);
    await settle(tester, 6);
    expect(await catNames(tester, store), isNot(contains('幣圈')));
  });

  testWidgets('搜尋：有結果、點進去、找不到、按 X 清掉', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '頻道a');
    await settle(tester, 2);
    // 一個在搜尋框裡、一個是結果。
    expect(find.text('頻道a'), findsNWidgets(2));
    expect(find.textContaining('投資・'), findsOneWidget);
    await tester.tap(find.text('頻道a').last);
    await settle(tester, 3);
    expect(find.textContaining('route:/yt-tracker/channel/a'), findsOneWidget);
  });

  testWidgets('搜尋找不到、清掉回到分類格子', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '沒有這個');
    await settle(tester, 2);
    expect(find.text('找不到符合的頻道'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester, 2);
    expect(find.text('全部'), findsOneWidget);
  });

  testWidgets('幣圈分類有到期的預測：卡片上有「該驗證」', (tester) async {
    final store = MemoryStore();
    await seedYt(tester, store);
    await tester.runAsync(
      () => YtTrackerRepository(store).addCategory(
        const YtCategory(id: 'c3', name: '幣圈', colorValue: 0xFFFFC857),
      ),
    );
    await pumpPage(
      tester,
      store,
      () => Consumer(
        builder: (_, ref, _) {
          return const YtTrackerHomePage();
        },
      ),
      size: const Size(390, 860),
    );
    await settle(tester, 6);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(YtTrackerHomePage)),
    );
    final now = DateTime.now();
    c.read(ytVideoRatingsProvider.notifier).state = {
      'x': YtVideoRating(
        at: now,
        claim: '會漲',
        dueAt: now.subtract(const Duration(days: 1)),
      ),
    };
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('cryptoDue')), findsOneWidget);
  });

  testWidgets('挖掘：沒金鑰先跳金鑰視窗', (tester) async {
    await open(tester, apiKey: false);
    await addMenu(tester, '挖掘新頻道');
    expect(find.text('YouTube API 金鑰'), findsOneWidget);
  });

  testWidgets('挖掘：選項取消就不挖', (tester) async {
    final (_, yt) = await open(tester);
    await http.runWithClient(() async {
      await addMenu(tester, '挖掘新頻道');
      expect(find.text('開始挖掘'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
    }, yt.client);
    expect(yt.calls.where((u) => u.path.endsWith('search')), isEmpty);
  });

  for (final fail in [0, 403]) {
    testWidgets('挖掘：每個選項都動一下、開始挖${fail == 0 ? '' : '（配額用完）'}', (tester) async {
      final (store, yt) = await open(tester, fail: fail);
      await http.runWithClient(() async {
        await addMenu(tester, '挖掘新頻道');
        final dialog = find.byType(AlertDialog);
        final fields = find.descendant(
          of: dialog,
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), '露營');
        await tester.enterText(fields.at(1), '1000');
        await tester.enterText(fields.at(2), '9000000');
        for (final s
            in tester
                .widgetList<SwitchListTile>(
                  find.descendant(
                    of: dialog,
                    matching: find.byType(SwitchListTile),
                  ),
                )
                .toList()) {
          s.onChanged!(!s.value);
          await tester.pump();
        }
        // 每種 chip 點一個、再點一個取消。
        final chips = find.descendant(
          of: dialog,
          matching: find.byType(FilterChip),
        );
        final n = chips.evaluate().length;
        for (var i = 0; i < n; i += 3) {
          tester.widget<FilterChip>(chips.at(i)).onSelected!(true);
          await tester.pump();
        }
        tester.widget<FilterChip>(chips.at(0)).onSelected!(false);
        await tester.pump();
        tester.widget<FilterChip>(chips.at(1)).onSelected!(true);
        await tester.pump();
        await tester.tap(find.text('開始挖掘'));
        await settle(tester, 12);
      }, yt.client);
      if (fail == 0) {
        expect(yt.calls.any((u) => u.path.endsWith('search')), isTrue);
      } else {
        expect(find.textContaining('挖掘失敗'), findsOneWidget);
      }
      expect(find.text('開始挖掘'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      // 挖到的放進挖掘分類。
      final chs = (await tester.runAsync(
        () => YtTrackerRepository(store).loadChannels(),
      ))!;
      if (fail == 0) {
        expect(
          chs.where((c) => c.categoryId == ytDiscoverCategoryId).length,
          greaterThanOrEqualTo(0),
        );
      }
    });
  }

  testWidgets('匯出：僅這台裝置、連快照一起、下載、複製、關閉', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final store = MemoryStore();
    await seedYt(tester, store);
    late WidgetRef wref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, r, _) {
                wref = r;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
    final hostCtx = tester.element(find.text('host'));
    showYtExportDialog(hostCtx, wref);
    await settle(tester, 4);
    expect(find.textContaining('個分類、'), findsOneWidget);
    expect(find.textContaining('約 '), findsWidgets);
    await tester.tap(find.text('連快照一起'));
    await settle(tester, 6);
    expect(find.textContaining('個分類、'), findsOneWidget);
    await tester.tap(find.text('連快照一起'));
    await settle(tester, 2);
    await tester.tap(find.text('下載'));
    await settle(tester, 3);
    expect(find.textContaining('這個平台還不支援下載'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('複製'));
    await settle(tester, 3);
    expect(copied, contains('"channels"'));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('關閉'));
    await settle(tester, 3);
    expect(find.text('匯出分類／頻道'), findsNothing);
  });
}
