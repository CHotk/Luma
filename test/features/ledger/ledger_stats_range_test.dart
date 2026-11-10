import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 2026-11-10 使用者：統計也要有按鈕可以選「全部」或「指定月份～指定月份」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LedgerStatsRange：指定月份～月份含頭尾整個月，全部不限', () {
    LedgerTx t(int y, int m, int d, int amount) => LedgerTx(
      id: '$y$m$d',
      type: LedgerTxType.expense,
      occurredAt: DateTime(y, m, d, 12),
      amount: amount,
      accountId: 'x',
      category: '餐飲',
    );
    final txs = [
      t(2026, 8, 31, 1),
      t(2026, 9, 1, 10),
      t(2026, 10, 15, 100),
      t(2026, 11, 30, 1000),
      t(2026, 12, 1, 5),
    ];
    final book = LedgerBook(
      accounts: const [],
      txs: txs,
      checkpoints: const [],
      budgets: const [],
    );
    final r = LedgerStatsRange.between(DateTime(2026, 9), DateTime(2026, 11));
    expect(book.statsWhere(r.test).spend, 1110, reason: '9 月 1 日到 11 月 30 日都算');
    expect(book.statsWhere(const LedgerStatsRange.all().test).spend, 1116);
    // 同一個月～同一個月＝單月。
    expect(
      book
          .statsWhere(
            LedgerStatsRange.between(
              DateTime(2026, 10),
              DateTime(2026, 10),
            ).test,
          )
          .spend,
      100,
    );
  });

  testWidgets('統計：「統計範圍」按鈕選全部／指定月份，數字跟著變；選回單月恢復預算', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final acc = await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 100000,
      openingAt: DateTime(2026, 1, 1),
    );
    final now = DateTime.now();
    LedgerTx spend(String id, DateTime at, int amount) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: at,
      amount: amount,
      accountId: acc.id,
      category: '餐飲',
      merchant: '店$id',
    );
    await repo.addTransaction(
      spend('a', DateTime(now.year, now.month, 1, 9), 300),
    );
    await repo.addTransaction(
      spend('b', DateTime(now.year, now.month - 2, 10, 9), 700),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.stats)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    // 預設單月：只有這個月那一筆 300，有「剩餘可花」。
    expect(find.text('本月消費'), findsWidgets);
    expect(find.textContaining('剩餘可花'), findsOneWidget);
    expect(find.text('\$300'), findsWidgets);
    final btn = find.byKey(const ValueKey('statsRange'));
    expect(btn, findsOneWidget);
    // 選全部：兩筆加起來 1000，改成「區間消費／月平均」，沒有預算。
    await tester.tap(btn);
    await settle();
    await tester.tap(find.byKey(const ValueKey('statsRangeAll')));
    await settle();
    expect(find.text('區間消費'), findsWidgets);
    expect(find.text('\$1,000'), findsWidgets);
    expect(find.textContaining('月平均'), findsOneWidget);
    expect(find.textContaining('剩餘可花'), findsNothing);
    expect(find.textContaining('全部時間'), findsWidgets);
    // 指定月份～月份：預設帶「第一筆那個月 ～ 這個月」，套用後一樣 1000，按鈕顯示範圍。
    await tester.tap(find.byKey(const ValueKey('statsRange')));
    await settle();
    expect(find.byKey(const ValueKey('statsFrom')), findsOneWidget);
    expect(find.byKey(const ValueKey('statsTo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('statsRangeApply')));
    await settle();
    expect(find.textContaining('～'), findsWidgets);
    expect(find.text('\$1,000'), findsWidgets);
    // 回單月。
    await tester.tap(find.byKey(const ValueKey('statsRange')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('statsRangeMonth')));
    await settle();
    expect(find.text('本月消費'), findsWidgets);
    expect(find.textContaining('剩餘可花'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
