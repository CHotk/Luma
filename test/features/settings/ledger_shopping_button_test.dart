import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/settings/other_settings_page.dart';

/// 設定 → 記帳 →「購物併入生活」按鈕：確認後把購物的交易都改到生活。
void main() {
  testWidgets('按「轉移」→ 確認 → 購物的交易變生活，提示轉了幾筆', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final acct = book0!.accounts.first;
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, 2, 12),
          amount: 300,
          accountId: acct.id,
          category: '購物',
          merchant: '襪子',
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LedgerSettingsSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('購物併入生活'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('ledgerShoppingBtn')));
    await tester.tap(find.byKey(const ValueKey('ledgerShoppingBtn')));
    await tester.pumpAndSettle();
    // 先確認，取消就什麼都不動。
    expect(find.text('把購物併入生活？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    var book = await tester.runAsync(() => repo.loadBook());
    expect(book!.txs.single.category, '購物');
    // 確認 → 改掉。
    await tester.tap(find.byKey(const ValueKey('ledgerShoppingBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '轉移'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    book = await tester.runAsync(() => repo.loadBook());
    expect(book!.txs.single.category, '生活');
    expect(find.text('已轉移 1 筆到生活'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
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
