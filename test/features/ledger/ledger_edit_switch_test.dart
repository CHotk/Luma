import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 2026-11-11 使用者：編輯也能在上面切支出／收入／轉帳、編輯支出要看得到分類；
/// 轉帳「從哪個帳戶」也能選 LineBank／富邦／虛擬貨幣；商家下拉不列刷卡的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LedgerRepository, LedgerAccount, LedgerAccount)> setup(
    WidgetTester tester,
    _MemoryStore store,
  ) async {
    final repo = LedgerRepository(store);
    final bank = await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime(2026, 11, 1),
    );
    final card = await repo.addAccount(
      name: '中信卡',
      type: LedgerAccountType.creditCard,
      opening: 50000,
      creditLimit: 50000,
      openingAt: DateTime(2026, 11, 1),
    );
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    return (repo, bank, card);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, _MemoryStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    await settle(tester);
  }

  testWidgets('編輯支出：看得到分類、上面能切成轉帳，存了變轉帳', (tester) async {
    final store = _MemoryStore();
    final (repo, bank, _) = await setup(tester, store);
    final now = DateTime.now();
    await repo.addTransaction(
      LedgerTx(
        id: 't1',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 9),
        amount: 300,
        accountId: bank.id,
        category: '餐飲',
        merchant: '早餐店',
      ),
    );
    await open(tester, store);
    await tester.tap(find.text('早餐店'));
    await settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle(tester);
    // 分類看得到、餐飲是選著的。
    final food = find.widgetWithText(ChoiceChip, '🍜 餐飲');
    await tester.ensureVisible(food.first);
    expect(tester.widget<ChoiceChip>(food.first).selected, isTrue);
    // 上面那排可以切。
    final transfer = find.widgetWithText(ChoiceChip, '轉帳');
    expect(transfer, findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '還錢'), findsNothing);
    await tester.ensureVisible(transfer);
    await tester.tap(transfer);
    await settle(tester);
    final lineBank = find.byKey(const ValueKey('toLineBank'));
    await tester.ensureVisible(lineBank);
    await tester.tap(lineBank);
    await settle(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    final tx = (await tester.runAsync(() => repo.loadBook()))!.txs.single;
    expect(tx.id, 't1');
    expect(tx.type, LedgerTxType.transfer);
    expect(tx.toName, 'LineBank');
    expect(tx.category, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轉帳從 LineBank 轉到中信活存：活存加錢、LineBank 推算扣掉、不算收入支出', (tester) async {
    final store = _MemoryStore();
    final (repo, bank, _) = await setup(tester, store);
    await open(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle(tester);
    final from = find.byKey(const ValueKey('srcExt_LineBank'));
    await tester.ensureVisible(from);
    await tester.tap(from);
    await settle(tester);
    expect(tester.widget<ChoiceChip>(from).selected, isTrue);
    // 轉到那排的 LineBank 不能選（同一個地方）。
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('toLineBank')))
          .onSelected,
      isNull,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '🏦 中信活存').last);
    await settle(tester);
    final amountField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
    );
    await tester.enterText(amountField, '1000');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('srcExtAfter')));
    expect(find.text('約 -\$1,000（照轉入轉出推算）'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final tx = book.txs.single;
    expect(tx.type, LedgerTxType.transfer);
    expect(tx.fromName, 'LineBank');
    expect(tx.accountId, '');
    expect(tx.toAccountId, bank.id);
    expect(
      book.stateOf(book.accounts.firstWhere((a) => a.id == bank.id))!.now,
      6000,
    );
    expect(book.extBalance('LineBank'), -1000);
    final s = book.statsWhere((_) => true);
    expect(s.spend, 0);
    expect(s.income, 0);
    expect(find.textContaining('LineBank → 中信活存'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('虛擬貨幣轉出：USDT 扣掉', () {
    final b = LedgerBook(
      accounts: const [],
      checkpoints: const [],
      budgets: const [],
      txs: [
        LedgerTx(
          id: 'a',
          type: LedgerTxType.transfer,
          occurredAt: DateTime(2026, 11, 1),
          amount: 3200,
          accountId: 'x',
          toName: '虛擬貨幣',
          extAmount: 100,
        ),
        LedgerTx(
          id: 'b',
          type: LedgerTxType.transfer,
          occurredAt: DateTime(2026, 11, 2),
          amount: 1600,
          accountId: '',
          fromName: '虛擬貨幣',
          toAccountId: 'x',
          extAmount: 50,
        ),
      ],
    );
    expect(b.usdtBalance(), 50);
    expect(b.fromLabel(b.txs.firstWhere((t) => t.id == 'b')), '虛擬貨幣');
  });

  testWidgets('商家下拉不列刷卡（信用卡）的商家', (tester) async {
    final store = _MemoryStore();
    final (repo, bank, card) = await setup(tester, store);
    final now = DateTime.now();
    await repo.addTransaction(
      LedgerTx(
        id: 'c1',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 8),
        amount: 99,
        accountId: card.id,
        merchant: 'PCHOME*刷卡怪名',
      ),
    );
    await repo.addTransaction(
      LedgerTx(
        id: 'b1',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 9),
        amount: 50,
        accountId: bank.id,
        merchant: '全家',
      ),
    );
    await open(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('merchantRecent')));
    await settle(tester);
    expect(find.text('全家'), findsWidgets);
    expect(find.text('PCHOME*刷卡怪名'), findsOneWidget, reason: '只在列表裡、下拉沒有');
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
