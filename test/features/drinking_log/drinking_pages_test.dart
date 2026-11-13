import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/theme/colors.dart';
import 'package:lume/data/repositories/drinking_repository.dart';
import 'package:lume/domain/models/drinking_entry.dart';
import 'package:lume/features/drinking_log/drinking_page.dart';
import 'package:lume/features/drinking_log/drinking_stats_page.dart';

import '../../support/poke.dart';

/// 喝酒記錄（2026-11-13 第 14 項；喝酒跟抽菸是分開的功能，各自一份測試）：
/// 沒紀錄；記一筆（選原因、直接記錄、點空白處不記）；先忍 10 分鐘（開始、取消）；
/// 月曆（上個月、下個月、點有紀錄跟沒紀錄的日子、1–2／3–4／5+ 次的顏色）；最近紀錄
/// （今天、昨天、更早；剛剛／分鐘前／小時前／天前；有沒有原因）；長按刪除（取消、確定）；
/// 統計頁（有資料、沒資料「去記一筆」回上一頁、一天超過 3 杯變紅）；390 寬不超出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  const size = Size(390, 2400);

  /// 塞一份紀錄：剛剛、20 分鐘前、5 小時前、昨天、3 天前，還有上個月 1 號 3 杯、
  /// 2 號 6 杯（月曆顏色），一筆刪掉的。
  Future<MemoryStore> seed(WidgetTester tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    await tester.runAsync(() async {
      final repo = DrinkingRepository(store);
      await repo.add(
        at: now.subtract(const Duration(seconds: 20)),
        reason: '壓力',
      );
      await repo.add(at: now.subtract(const Duration(minutes: 20)));
      await repo.add(at: now.subtract(const Duration(hours: 5)), reason: '慶祝');
      await repo.add(at: now.subtract(const Duration(days: 1)), reason: '無聊');
      await repo.add(at: now.subtract(const Duration(days: 3)));
      final prev = DateTime(now.year, now.month - 1);
      for (var i = 0; i < 3; i++) {
        await repo.add(at: DateTime(prev.year, prev.month, 1, 9 + i));
      }
      for (var i = 0; i < 6; i++) {
        await repo.add(
          at: DateTime(prev.year, prev.month, 2, 8 + i),
          reason: i.isEven ? '社交' : null,
        );
      }
      final gone = await repo.add(at: now.subtract(const Duration(days: 2)));
      await repo.delete(gone.id);
    });
    return store;
  }

  Future<List<DrinkingEntry>> entries(
    WidgetTester tester,
    MemoryStore s,
  ) async => (await tester.runAsync(() => DrinkingRepository(s).loadAll()))!;

  Future<void> open(WidgetTester tester, MemoryStore store) async {
    await pumpPage(tester, store, () => const DrinkingPage(), size: size);
    await settle(tester, 4);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f.first);
    await tester.pump();
    await tester.tap(f.first);
    await settle(tester, 4);
  }

  testWidgets('沒紀錄：計時器 --:--:--、最近紀錄跟這天都是空的', (tester) async {
    await open(tester, MemoryStore());
    expect(find.text('--:--:--'), findsOneWidget);
    expect(find.text('還沒有紀錄，喝完按下面的按鈕記一筆'), findsOneWidget);
    expect(find.text('還沒有紀錄'), findsOneWidget);
    expect(find.text('這天沒有紀錄'), findsOneWidget);
    expect(find.text('長按一筆可刪除'), findsNothing);
    // 每秒跳一次也不會壞。
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('記一筆：選原因、直接記錄、點空白處不記', (tester) async {
    final store = MemoryStore();
    await open(tester, store);
    await tapText(tester, '我剛喝了一杯（重新計時）');
    expect(find.text('為什麼想喝？（選填）'), findsOneWidget);
    await tapText(tester, '壓力');
    var all = await entries(tester, store);
    expect(all.single.reason, '壓力');
    expect(find.textContaining('今天已喝 1 杯'), findsOneWidget);
    expect(find.text('剛剛'), findsOneWidget);

    await tapText(tester, '我剛喝了一杯（重新計時）');
    await tapText(tester, '直接記錄');
    all = await entries(tester, store);
    expect(all.length, 2);
    expect(all.where((e) => e.reason == null).length, 1);
    expect(find.textContaining('今天最長撐過'), findsOneWidget);

    await tapText(tester, '我剛喝了一杯（重新計時）');
    await tester.tapAt(const Offset(195, 60));
    await settle(tester, 4);
    expect((await entries(tester, store)).length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('先忍 10 分鐘：倒數、取消；記一筆會停掉倒數', (tester) async {
    await open(tester, MemoryStore());
    await tapText(tester, '先忍 10 分鐘');
    expect(find.textContaining('冷靜中… 還剩'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tapText(tester, '取消');
    expect(find.text('先喝杯水，10 分鐘後還想喝再喝。'), findsOneWidget);
    await tapText(tester, '先忍 10 分鐘');
    await tapText(tester, '我剛喝了一杯（重新計時）');
    await tapText(tester, '直接記錄');
    expect(find.textContaining('冷靜中'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('月曆：上個月（3 杯、6 杯的顏色）、點日子、下個月；最近紀錄的各種時間', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    expect(find.text('剛剛'), findsOneWidget);
    expect(find.text('20 分鐘前'), findsOneWidget);
    expect(find.text('5 小時前'), findsOneWidget);
    expect(find.text('1 天前'), findsOneWidget);
    expect(find.text('3 天前'), findsOneWidget);
    expect(find.textContaining('昨天 '), findsOneWidget);
    expect(find.text('壓力'), findsOneWidget);
    expect(find.text('長按一筆可刪除'), findsOneWidget);
    // 刪掉的那筆不算。
    expect(find.text('2 天前'), findsNothing);

    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    await tester.ensureVisible(find.byIcon(Icons.chevron_left_rounded));
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await settle(tester, 2);
    expect(find.text('${prev.year} 年 ${prev.month} 月'), findsOneWidget);
    expect(
      find.text(
        '平均每天 ${(9 / DateTime(prev.year, prev.month + 1, 0).day).toStringAsFixed(1)} 次',
      ),
      findsOneWidget,
    );
    Color cell(String label) =>
        (tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(cell('3'), const Color(0xFFB8902F));
    expect(cell('6'), const Color(0xFFC65A52));
    await tester.tap(find.text('6').first);
    await settle(tester, 2);
    expect(find.text('${prev.month}/2・6 次'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    await tester.tap(find.text('15'));
    await settle(tester, 2);
    expect(find.text('這天沒有紀錄'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await settle(tester, 2);
    final next = DateTime(now.year, now.month + 1);
    expect(find.text('${next.year} 年 ${next.month} 月'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('長按刪除：取消不刪、確定刪掉', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    final n = (await entries(tester, store)).length;
    final row = find.text('20 分鐘前');
    await tester.ensureVisible(row);
    await tester.longPress(row);
    await settle(tester, 4);
    expect(find.text('刪除這筆紀錄？'), findsOneWidget);
    await tapText(tester, '取消');
    expect((await entries(tester, store)).length, n);
    await tester.longPress(find.text('20 分鐘前'));
    await settle(tester, 4);
    await tester.tap(find.text('刪除').last);
    await settle(tester, 4);
    expect((await entries(tester, store)).length, n - 1);
    expect(find.text('20 分鐘前'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('右上角統計按鈕開統計頁', (tester) async {
    await open(tester, MemoryStore());
    await tester.tap(find.byTooltip('統計'));
    await settle(tester, 4);
    expect(find.text('route:/drinking-log/stats'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('統計頁：今天、平均間隔、近 7 天（超過 3 杯變紅）、時段、原因比例', (tester) async {
    final store = await seed(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      // 4 天前喝了 4 杯：長條變紅。
      final d = now.subtract(const Duration(days: 4));
      for (var i = 0; i < 4; i++) {
        await DrinkingRepository(
          store,
        ).add(at: DateTime(d.year, d.month, d.day, 10 + i));
      }
    });
    await pumpPage(tester, store, () => const DrinkingStatsPage(), size: size);
    await settle(tester, 4);
    expect(find.text('喝酒記錄統計'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('近 7 天平均間隔'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('為什麼喝？'), findsOneWidget);
    expect(find.textContaining('社交'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);
    final red = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == AppColors.bad,
    );
    expect(red, findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await settle(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('統計頁：近 7 天只有一筆，平均間隔是「—」', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() => DrinkingRepository(store).add());
    await pumpPage(tester, store, () => const DrinkingStatsPage(), size: size);
    await settle(tester, 4);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('1 杯'), findsOneWidget);
  });

  testWidgets('統計頁沒資料：「去記一筆」回上一頁', (tester) async {
    await pumpPage(
      tester,
      MemoryStore(),
      () => const Scaffold(body: Text('記錄頁')),
      size: size,
    );
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => const DrinkingStatsPage()),
        );
    await settle(tester, 4);
    expect(find.text('還沒有紀錄'), findsOneWidget);
    await tester.tap(find.text('去記一筆'));
    await settle(tester, 4);
    expect(find.text('記錄頁'), findsOneWidget);
    expect(find.byType(DrinkingStatsPage), findsNothing);
  });

  testWidgets('資料：雲端合併（本機贏、刪除贏、回傳異動）；刪除找不到 id 不動', (tester) async {
    await tester.runAsync(() async {
      final repo = DrinkingRepository(MemoryStore());
      final a = await repo.add(reason: '本機');
      expect(await repo.mergeFromCloud(const []), 0);
      final n = await repo.mergeFromCloud([
        DrinkingEntry(id: a.id, at: a.at, reason: '雲端舊的'),
        DrinkingEntry(id: 'c', at: DateTime(2026, 1, 1)),
      ]);
      expect(n, 1);
      final all = await repo.loadAll();
      expect(all.firstWhere((e) => e.id == a.id).reason, '本機');
      await repo.delete('沒有');
      expect((await repo.allForUpload()).length, 2);
    });
  });
}
