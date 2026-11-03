import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_log_page.dart';

/// 記帳操作紀錄頁：新的在前、依日期分隔、可搜尋、沒有任何刪除。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('顯示每一筆操作、可搜尋、沒有刪除鈕', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await tester.runAsync(() async {
      final b = await repo.loadBook();
      await repo.addTransaction(
        LedgerTx(
          id: 'x',
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, 5, 12),
          amount: 120,
          accountId: b.accounts.first.id,
          category: '餐飲',
          merchant: '鼎泰豐',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await repo.deleteTransaction('x');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerLogPage()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.textContaining('共 2 筆'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);
    expect(find.textContaining('只增不刪'), findsOneWidget);
    // 搜尋。
    await tester.enterText(find.byType(TextField), '不存在的字');
    await tester.pump();
    expect(find.text('沒有符合的紀錄'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '鼎泰豐');
    await tester.pump();
    expect(find.textContaining('符合 2 筆'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
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
