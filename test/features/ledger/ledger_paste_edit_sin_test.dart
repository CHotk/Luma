import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 2026-11-10 使用者：
/// 1. 記一筆時貼文字，偵測到已經記過同一筆，直接變成編輯那一筆（不用再看「按記下來也不會加」）。
/// 2. 金額剛好 110 或 1100 且分類不是菸酒，儲存前問要不要改成菸酒（設定可關）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final noon = DateTime(2026, 11, 3, 12, 0);

  Future<_MemoryStore> seeded() async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final card = await repo.addAccount(
      name: '中信信用卡',
      type: LedgerAccountType.creditCard,
      opening: 90000,
      openingAt: DateTime(2026, 11, 1),
      creditLimit: 100000,
    );
    await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 2000,
      openingAt: DateTime(2026, 11, 1),
    );
    await repo.addTransaction(
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.expense,
        occurredAt: noon,
        amount: 250,
        accountId: card.id,
        category: '餐飲',
        merchant: '鼎泰豐',
      ),
    );
    return store;
  }

  test('貼上匯入：重複的是已經記過的哪一筆（duplicateTx）；這次貼的兩行重複沒有', () async {
    final store = await seeded();
    final book = await LedgerRepository(store).loadBook();
    final lines = book.parseImport(
      '中信信用卡｜2026-11-03 12:00｜餐飲｜別的店名｜250\n'
      '中信信用卡｜2026-11-03 15:00｜餐飲｜某店｜80\n'
      '中信信用卡｜2026-11-03 15:00｜餐飲｜某店｜80',
    );
    expect(lines[0].duplicate, isTrue);
    expect(lines[0].duplicateTx?.merchant, '鼎泰豐');
    expect(lines[1].duplicate, isFalse);
    expect(lines[1].duplicateTx, isNull);
    expect(lines[2].duplicate, isTrue); // 這次貼的第 2 行
    expect(lines[2].duplicateTx, isNull);
  });

  Future<void> pump(WidgetTester tester, _MemoryStore store) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.home)),
      ),
    );
    await settle(tester);
  }

  testWidgets('記一筆貼上同一筆：直接變成編輯那一筆', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('記一筆'), findsOneWidget);
    // 貼一行跟已經記過的同帳戶、同一分鐘、同金額（商家不同也算）。
    final paste = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '貼上一行文字，下面自動填（選填）',
    );
    expect(paste, findsOneWidget);
    await tester.enterText(paste, '中信信用卡｜2026-11-03 12:00｜餐飲｜別的店名｜250');
    await settle(tester);
    // 記一筆的表單關掉，換成「編輯支出」，裡面是原本那筆（鼎泰豐）。
    expect(find.text('記一筆'), findsNothing);
    expect(find.text('編輯支出'), findsOneWidget);
    expect(find.text('鼎泰豐'), findsWidgets);
    expect(find.textContaining('已經有同一筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> fillAndSave(
    WidgetTester tester, {
    required String amount,
  }) async {
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    final fields = find.byType(TextField);
    // 商家、金額：用輸入框順序不穩，改用 hint／標籤找不到的話就依序填。
    final merchant = find.byType(TextField);
    await tester.enterText(merchant.at(1), '福利社');
    final amt = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.prefixText == '\$ ',
    );
    await tester.enterText(amt.first, amount);
    await tester.pump();
    expect(fields, findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
  }

  testWidgets('金額 110：儲存前問要不要改成菸酒，按「改成菸酒」分類就變菸酒', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await fillAndSave(tester, amount: '110');
    expect(find.text('要改成菸酒嗎？'), findsOneWidget);
    await tester.tap(find.text('改成菸酒'));
    await settle(tester);
    final book = await LedgerRepository(store).loadBook();
    final t = book.txs.firstWhere((x) => x.merchant == '福利社');
    expect(t.amount, 110);
    expect(t.category, '菸酒');
  });

  testWidgets('金額 1100：按「不用」就維持原分類；金額 120 不會問', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await fillAndSave(tester, amount: '1100');
    expect(find.text('要改成菸酒嗎？'), findsOneWidget);
    await tester.tap(find.text('不用'));
    await settle(tester);
    var book = await LedgerRepository(store).loadBook();
    expect(
      book.txs.firstWhere((x) => x.merchant == '福利社').category,
      isNot('菸酒'),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    // 另外開一筆 120：沒有彈窗。
    final merchant = find.byType(TextField);
    await tester.enterText(merchant.at(1), '麵包店');
    await tester.enterText(
      find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.prefixText == '\$ ',
          )
          .first,
      '120',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    expect(find.text('要改成菸酒嗎？'), findsNothing);
    book = await LedgerRepository(store).loadBook();
    expect(book.txs.any((x) => x.merchant == '麵包店'), isTrue);
  });

  incomeTests();

  testWidgets('記收入：來源是下拉選單，分類有「平轉」（不算本月收入）', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
    await settle(tester);
    // 來源不是輸入框，是下拉選單：點開選「ATM存款」。
    final dd = find.byKey(const ValueKey('incomeSource'));
    expect(dd, findsOneWidget);
    await tester.tap(dd);
    await settle(tester);
    expect(find.text('薪資轉帳'), findsWidgets);
    await tester.tap(find.text('ATM存款').last);
    await settle(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.prefixText == r'$ ',
      ),
      '58000',
    );
    await tester.pump();
    // 收入分類也有「未分類」（不知道算什麼收入時選）。
    expect(find.widgetWithText(ChoiceChip, '❔ 未分類'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await tester.tap(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = await LedgerRepository(store).loadBook();
    final t = book.txs.firstWhere((x) => x.amount == 58000);
    expect(t.type, LedgerTxType.income);
    expect(t.merchant, 'ATM存款');
    expect(t.category, '平轉');
    expect(book.statsWhere((_) => true).income, 0);
  });

  testWidgets('設定關掉「110／1100 問要不要改成菸酒」就不問', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    ProviderScope.containerOf(
      tester.element(find.byType(LedgerPage)),
    ).read(ledgerSinAskProvider.notifier).state = false;
    await fillAndSave(tester, amount: '110');
    expect(find.text('要改成菸酒嗎？'), findsNothing);
    final book = await LedgerRepository(store).loadBook();
    expect(book.txs.any((x) => x.merchant == '福利社' && x.amount == 110), isTrue);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
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

/// 貼上匯入記收入（2026-11-10 使用者：轉帳、ATM存款、薪資轉帳）。
void incomeTests() {
  test('貼上匯入：薪資轉帳、ATM存款、轉入都是收入，錢進第一欄的帳戶', () async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final bank = await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 1000,
      openingAt: DateTime(2026, 11, 1),
    );
    final cash = await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 0,
      openingAt: DateTime(2026, 11, 1),
    );
    final book = await repo.loadBook();
    final lines = book.parseImport(
      '中信活存｜2026-11-05 09:00｜薪資轉帳｜某某公司｜50000\n'
      '中信活存｜2026-11-06 10:00｜ATM存款｜ATM｜3000\n'
      '中信活存｜2026-11-07 11:00｜轉入｜朋友還款｜800｜｜｜｜｜午餐錢\n'
      '現金｜2026-11-08 12:00｜獎金｜紅包｜600\n'
      '中信活存｜2026-11-09 13:00｜轉帳｜中信活存｜10',
    );
    final t0 = lines[0].tx!;
    expect(t0.type, LedgerTxType.income);
    expect(t0.category, '薪資');
    expect(t0.accountId, bank.id);
    expect(t0.merchant, '某某公司');
    expect(lines[1].tx!.category, '其他收入');
    expect(lines[2].tx!.type, LedgerTxType.income);
    expect(lines[2].tx!.note, '午餐錢');
    expect(lines[3].tx!.accountId, cash.id);
    expect(lines[3].tx!.category, '獎金');
    // 全形、空白、小寫也認得。
    final v = book.parseImport(
      '中信活存｜2026-11-10 09:00｜ＡＴＭ存款｜ATM｜100\n'
      '中信活存｜2026-11-10 10:00｜atm 存款｜ATM｜200\n'
      '中信活存｜2026-11-10 11:00｜ATM存入｜ATM｜300',
    );
    expect(
      v.every((l) => l.willImport && l.tx!.type == LedgerTxType.income),
      isTrue,
    );
    // 平轉：記成收入分類「平轉」，錢進帳戶、但不算本月收入。
    final f = book.parseImport(
      '中信銀行｜2026/06/29 20:09｜平轉｜ATM存款｜58000｜｜｜｜｜｜存款入帳\n'
      '中信活存｜2026/06/30 09:00｜薪資轉帳｜某某公司｜40000',
    );
    expect(f[0].tx!.type, LedgerTxType.income);
    expect(f[0].tx!.category, '平轉');
    expect(f[0].tx!.accountId, bank.id);
    final withTx = LedgerBook(
      accounts: book.accounts,
      txs: [f[0].tx!, f[1].tx!],
      checkpoints: const [],
      budgets: const [],
    );
    expect(withTx.statsWhere((_) => true).income, 40000); // 平轉的 58000 不算收入
    // 「轉帳」還是轉出去：轉到自己的同一個帳戶是錯的。
    expect(lines[4].error, isNotNull);
    expect(lines.take(4).every((l) => l.willImport), isTrue);
  });
}
