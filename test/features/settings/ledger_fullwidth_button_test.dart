import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/settings/other_settings_page.dart';

/// 設定 → 記帳 →「整理全形文字」按鈕：確認後把舊資料的全形英數字改成半形小寫。
void main() {
  testWidgets('按「整理」→ 確認 → 舊的 ＦＯＯＤＰＡＮＤＡ 變 foodpanda，提示改了幾筆', (tester) async {
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
          category: '餐飲',
          merchant: 'ＦＯＯＤＰＡＮＤＡ',
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
    expect(find.text('整理全形文字'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '整理'));
    await tester.tap(find.widgetWithText(OutlinedButton, '整理'));
    await tester.pumpAndSettle();
    // 先確認，取消就什麼都不動。
    expect(find.text('整理全形文字？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    var book = await tester.runAsync(() => repo.loadBook());
    expect(book!.txs.single.merchant, 'ＦＯＯＤＰＡＮＤＡ');
    // 確認 → 改掉。
    await tester.tap(find.widgetWithText(OutlinedButton, '整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '整理'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    book = await tester.runAsync(() => repo.loadBook());
    expect(book!.txs.single.merchant, 'foodpanda');
    expect(find.text('已整理 1 筆'), findsOneWidget);
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
