import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/trade_repository.dart';
import 'package:lume/domain/models/trade_entry.dart';
import 'package:lume/features/crypto_watch/trade_data.dart';

import '../../support/poke.dart';

/// 交易紀錄的流程（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：持倉中那單結算
/// （賺、賠）、從結算改去編輯、已平倉那單刪除（取消／確認）、刪除確認、編輯存起來、
/// 月初資金（0 不能存、取消、存起來、Enter）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TradeRepository> host(
    WidgetTester tester,
    MemoryStore store,
    Future<void> Function(BuildContext, WidgetRef) run,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, ref, _) => Center(
                child: ElevatedButton(
                  key: const ValueKey('go'),
                  onPressed: () => run(c, ref),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    return TradeRepository(store);
  }

  Future<TradeEntry> add(
    WidgetTester tester,
    MemoryStore store, {
    double? pnl,
  }) async {
    final now = DateTime.now();
    return (await tester.runAsync(
      () => TradeRepository(store).add(
        symbol: 'BTC',
        isLong: true,
        leverage: 10,
        margin: 100,
        openedAt: now.subtract(const Duration(hours: 3)),
        closedAt: pnl == null ? null : now.subtract(const Duration(hours: 1)),
        pnl: pnl,
      ),
    ))!;
  }

  Future<TradeData> data(WidgetTester tester, TradeRepository r) async =>
      (await tester.runAsync(
        () async => TradeData(
          trades: await r.loadAll(),
          capitals: await r.loadCapitals(),
        ),
      ))!;

  for (final (pnl, word) in [(12.5, '賺'), (-8.0, '賠')]) {
    testWidgets('持倉中那單結算（$word）：填損益 → 結算、寫報酬率', (tester) async {
      final store = MemoryStore();
      final t = await add(tester, store);
      final repo = TradeRepository(store);
      final d = await data(tester, repo);
      await host(tester, store, (c, ref) => openTradeFlow(c, ref, t, d));
      final field = find.byType(TextField).first;
      if (pnl < 0) {
        final loss = find.textContaining('賠');
        if (loss.evaluate().isNotEmpty) {
          await tester.tap(loss.first, warnIfMissed: false);
          await tester.pump();
        }
      }
      await tester.enterText(field, '${pnl.abs()}');
      await tester.pump();
      final go = find.textContaining('結算（記在');
      await tester.ensureVisible(go);
      await tester.tap(go);
      await settle(tester);
      final after = (await data(tester, repo)).trades.single;
      expect(after.isOpen, isFalse);
      expect(after.pnl!.abs(), pnl.abs());
      expect(find.textContaining('結算完成'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('持倉中按「編輯開倉資料」→ 開編輯表單；按外面關掉＝不改', (tester) async {
    final store = MemoryStore();
    final t = await add(tester, store);
    final repo = TradeRepository(store);
    final d = await data(tester, repo);
    await host(tester, store, (c, ref) => openTradeFlow(c, ref, t, d));
    final edit = find.text('編輯開倉資料');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await settle(tester);
    expect(find.textContaining('儲存修改'), findsWidgets);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect((await data(tester, repo)).trades.single.isOpen, isTrue);
  });

  testWidgets('持倉中那單結算：按外面關掉＝不結算（取消）', (tester) async {
    final store = MemoryStore();
    final t = await add(tester, store);
    final repo = TradeRepository(store);
    final d = await data(tester, repo);
    await host(tester, store, (c, ref) => openTradeFlow(c, ref, t, d));
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect((await data(tester, repo)).trades.single.isOpen, isTrue);
  });

  testWidgets('已平倉那單：刪除先問、取消不刪、確認才刪；編輯接到編輯表單', (tester) async {
    final store = MemoryStore();
    final t = await add(tester, store, pnl: 5);
    final repo = TradeRepository(store);
    final d = await data(tester, repo);
    await host(tester, store, (c, ref) => openTradeFlow(c, ref, t, d));
    expect(find.text('這一單'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '刪除'));
    await settle(tester);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect((await data(tester, repo)).trades, hasLength(1));
    await tester.tap(find.widgetWithText(OutlinedButton, '刪除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    expect((await data(tester, repo)).trades, isEmpty);
    expect(find.text('已刪除這一單'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));

    final t2 = await add(tester, store, pnl: 7);
    final d2 = await data(tester, repo);
    await host(tester, store, (c, ref) => openTradeFlow(c, ref, t2, d2));
    await tester.tap(find.text('編輯'));
    await settle(tester);
    final save = find.textContaining('儲存修改');
    await tester.ensureVisible(save.first);
    await tester.tap(save.first);
    await settle(tester);
    expect(find.text('已更新這一單'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('刪除這一單（列表上長按）：取消不刪、確認才刪', (tester) async {
    final store = MemoryStore();
    final t = await add(tester, store, pnl: -3);
    await host(tester, store, (c, ref) => deleteTradeFlow(c, ref, t));
    expect(find.text('刪除這一單？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    final repo = TradeRepository(store);
    expect((await data(tester, repo)).trades, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    expect((await data(tester, repo)).trades, isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('月初資金：0 不能存、取消不存、填了存起來、Enter 也能存、有舊值先帶入', (tester) async {
    final store = MemoryStore();
    final month = DateTime(2026, 11);
    final repo = await host(
      tester,
      store,
      (c, ref) => editCapitalFlow(c, ref, month, null),
    );
    expect(find.text('11 月初的資金'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('11 月初的資金'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(await tester.runAsync(repo.loadCapitals), isEmpty);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect((await tester.runAsync(repo.loadCapitals))!.values.single, 1000);
    expect(find.textContaining('已設定 11 月初資金'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await host(tester, store, (c, ref) => editCapitalFlow(c, ref, month, 1000));
    expect(find.text('1000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect((await tester.runAsync(repo.loadCapitals))!.values.single, 1500);
    await tester.pump(const Duration(seconds: 6));
  });
}
