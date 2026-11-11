import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_glass_button.dart';
import 'package:lume/features/ledger/ledger_page.dart';
import 'package:lume/features/ledger/ledger_ui.dart' show showLedgerTermsDialog;

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
      '中信信用卡｜2026-11-03 12:00｜餐飲｜鼎泰豐｜250\n'
      '中信信用卡｜2026-11-03 15:00｜餐飲｜某店｜80\n'
      '中信信用卡｜2026-11-03 15:00｜餐飲｜某店｜80\n'
      '中信信用卡｜2026-11-03 12:00｜餐飲｜別的店名｜250',
    );
    expect(lines[0].duplicate, isTrue);
    expect(lines[0].duplicateTx?.merchant, '鼎泰豐');
    // 同一分鐘同金額但商店不同（2026-11-10）：不算重複。
    expect(lines[3].duplicate, isFalse);
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
    // 貼一行跟已經記過的同帳戶、同一分鐘、同金額、同商店（2026-11-10：商店也要一樣）。
    final paste = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '貼上一行文字，下面自動填（選填）',
    );
    expect(paste, findsOneWidget);
    await tester.enterText(paste, '中信信用卡｜2026-11-03 12:00｜餐飲｜鼎泰豐｜250');
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
    await tester.enterText(merchant.at(2), '福利社');
    final amt = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0',
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
    await tester.enterText(merchant.at(2), '麵包店');
    await tester.enterText(
      find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == '0',
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
  accountMatchTests();

  Finder amountField() => find
      .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '0')
      .first;
  // 輸入框順序：貼上(0)、金額(1)、商家(2)。
  Finder merchantField() => find.byType(TextField).at(2);

  testWidgets('記一筆：預設不選分類；金額在商家上面；每個欄位右邊都有統一的毛玻璃按鈕', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    // 支出、收入都沒有預設選好的分類。
    for (final c in ledgerExpenseCats.entries) {
      final chip = find.widgetWithText(ChoiceChip, '${c.value.$1} ${c.key}');
      if (chip.evaluate().isEmpty) continue;
      expect(tester.widget<ChoiceChip>(chip).selected, isFalse, reason: c.key);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
    await settle(tester);
    for (final c in ledgerIncomeCats.entries) {
      final chip = find.widgetWithText(ChoiceChip, '${c.value.$1} ${c.key}');
      if (chip.evaluate().isEmpty) continue;
      expect(tester.widget<ChoiceChip>(chip).selected, isFalse, reason: c.key);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, '支出'));
    await settle(tester);
    // 金額在商家名稱上面。
    final amountY = tester.getTopLeft(amountField()).dy;
    final merchantY = tester.getTopLeft(find.text('商家／名稱')).dy;
    expect(amountY, lessThan(merchantY));
    // 時間「不確定」、金額「−」、商家下拉：同一種玻璃按鈕。
    for (final k in ['timeUnknown', 'signToggle', 'merchantRecent']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      expect(
        find.byKey(ValueKey(k)).evaluate().first.widget,
        isA<LedgerGlassButton>(),
        reason: k,
      );
    }
    // 不選分類直接記：存成「未分類」。
    await tester.enterText(amountField(), '55');
    await tester.enterText(merchantField(), '路邊攤');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    ))!;
    final t = book.txs.firstWhere((x) => x.merchant == '路邊攤');
    expect(t.category, '未分類');
    expect(tester.takeException(), isNull);
  });

  testWidgets('記一筆：商家旁的下拉列出最近用過的商家（照添加順序、不重複、最多 20 個），點了就填進去', (tester) async {
    final store = await seeded();
    final repo = LedgerRepository(store);
    final book0 = await repo.loadBook();
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3)),
      );
      await repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: noon,
          amount: 10 + i,
          accountId: book0.accounts.first.id,
          category: '餐飲',
          merchant: i == 24 ? '鼎泰豐' : '店$i',
        ),
      );
    }
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('merchantRecent')));
    await tester.pumpAndSettle();
    // 最新的「鼎泰豐」排最前（舊的那筆同名不重複），店0～店4 擠出 20 個之外。
    expect(find.text('鼎泰豐'), findsWidgets);
    expect(find.text('店23'), findsOneWidget);
    expect(find.text('店0'), findsNothing);
    await tester.tap(find.text('店23'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '店23',
      ),
      findsOneWidget,
    );
  });

  testWidgets('收入選「平轉」要選來源戶頭（LineBank、富邦）；選別的分類就不用', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
    await settle(tester);
    expect(find.byKey(const ValueKey('fromExt_LineBank')), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await tester.tap(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await settle(tester);
    expect(find.byKey(const ValueKey('fromExt_LineBank')), findsOneWidget);
    expect(find.byKey(const ValueKey('fromExt_富邦')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('incomeSource')));
    await settle(tester);
    await tester.tap(find.text('其他').last);
    await settle(tester);
    await tester.enterText(amountField(), '5000');
    await tester.pump();
    // 沒選來源戶頭按新增：不會存。
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    var book = (await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    ))!;
    expect(book.txs.where((t) => t.type == LedgerTxType.income), isEmpty);
    await tester.tap(find.byKey(const ValueKey('fromExt_富邦')));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    book = (await tester.runAsync(() => LedgerRepository(store).loadBook()))!;
    final t = book.txs.firstWhere((t) => t.type == LedgerTxType.income);
    expect(t.category, ledgerFlatTransfer);
    expect(t.toName, '富邦');
    expect(tester.takeException(), isNull);
  });

  testWidgets('轉帳選「他人戶頭」：還是轉帳、填誰的戶頭、不出現支出分類；本身算一筆支出（轉給他人）', (tester) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('toOtherAccount')));
    await tester.tap(find.byKey(const ValueKey('toOtherAccount')));
    await settle(tester);
    expect(find.text('誰的戶頭'), findsOneWidget);
    expect(find.text('買什麼（分類）'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '🍜 餐飲'), findsNothing);
    await tester.enterText(amountField(), '1200');
    await tester.enterText(merchantField(), '阿明');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    ))!;
    final t = book.txs.firstWhere((x) => x.merchant == '阿明');
    expect(t.type, LedgerTxType.transfer, reason: '還是轉帳，不是支出');
    expect(t.toOther, isTrue);
    expect(t.toName, '阿明');
    expect(t.toAccountId, isNull);
    expect(t.amount, 1200);
    // 轉帳本身算支出：不算消費、算總支出（轉給他人）。
    final st = book.statsWhere((x) => x.id == t.id);
    expect(st.spend, 0);
    expect(st.out, 1200);
    expect(st.extra[ledgerToOtherCat], 1200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轉帳：「從哪個帳戶」不列信用卡；「轉到」多富邦、虛擬貨幣（平轉，不算支出）', (tester) async {
    final store = await seeded(); // 中信信用卡、現金
    await LedgerRepository(store).addAccount(
      name: '中信帳戶',
      type: LedgerAccountType.bank,
      opening: 10000,
      openingAt: DateTime(2026, 11, 1),
    );
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle(tester);
    // 「從哪個帳戶」那一排：沒有信用卡。
    final fromRow = find
        .ancestor(of: find.text('從哪個帳戶'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: fromRow, matching: find.textContaining('中信信用卡')),
      findsNothing,
    );
    expect(
      find.descendant(of: fromRow, matching: find.textContaining('中信帳戶')),
      findsOneWidget,
    );
    for (final k in ['toLineBank', 'toExt_富邦', 'toExt_虛擬貨幣']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('toExt_虛擬貨幣')));
    await tester.tap(find.byKey(const ValueKey('toExt_虛擬貨幣')));
    await settle(tester);
    await tester.enterText(amountField(), '3000');
    await tester.pump();
    // 虛擬貨幣那邊用 USDT：填 USDT，旁邊寫 ×32 粗估台幣；「這筆之後」也是 USDT。
    expect(find.byKey(const ValueKey('usdtField')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('usdtField')), '93.75');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('usdtTwd'))).data,
      contains('\$3,000'),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('extAfter'))).data,
      contains('93.75 USDT'),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    ))!;
    final t = book.txs.firstWhere((x) => x.amount == 3000);
    expect(t.type, LedgerTxType.transfer);
    expect(t.toName, '虛擬貨幣');
    expect(t.extAmount, 93.75);
    expect(t.toAccountId, isNull);
    expect(book.accountName(t.accountId), '中信帳戶');
    expect(book.statsWhere((x) => x.id == t.id).spend, 0);
    expect(tester.takeException(), isNull);
  });

  test('支出分類順序：創業兩個放最底下，最後一個是未分類', () {
    final keys = ledgerExpenseCats.keys.toList();
    expect(keys.last, '未分類');
    expect(keys.sublist(keys.length - 3), ['創業魔物童話', '創業交友APP', '未分類']);
  });

  testWidgets('首頁「最近記帳」照添加順序：後來補記的舊日期帳排在最上面', (tester) async {
    final store = await seeded();
    final repo = LedgerRepository(store);
    final book0 = await repo.loadBook();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await repo.addTransaction(
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 10, 1, 9, 0), // 比鼎泰豐早一個月
        amount: 77,
        accountId: book0.accounts.first.id,
        category: '餐飲',
        merchant: '補記的舊帳',
      ),
    );
    await pump(tester, store);
    // 首頁很長：「最近記帳」在下面，畫面拉高才會建出來。
    tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
    await tester.pump();
    final old = tester.getTopLeft(find.textContaining('補記的舊帳').first).dy;
    final dtf = tester.getTopLeft(find.textContaining('鼎泰豐').first).dy;
    expect(old, lessThan(dtf), reason: '剛添加的在上面，不是照交易時間排');
  });

  testWidgets('記支出：分類有「還款」，選了之後商家欄變成下拉選單（中信信貸／台新信貸／當鋪／Jet／JUJI）', (
    tester,
  ) async {
    final store = await seeded();
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    // 還沒選還款：商家是一般輸入框。
    expect(find.byKey(const ValueKey('incomeSource')), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '💸 還款'));
    await tester.tap(find.widgetWithText(ChoiceChip, '💸 還款'));
    await settle(tester);
    final dd = find.byKey(const ValueKey('incomeSource'));
    expect(dd, findsOneWidget);
    await tester.ensureVisible(dd);
    await tester.pumpAndSettle();
    expect(find.text('還給誰'), findsOneWidget);
    await tester.tap(dd);
    await settle(tester);
    for (final n in ledgerRepayTargets) {
      expect(find.text(n), findsWidgets);
    }
    await tester.tap(find.text('台新信貸').last);
    await settle(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '0',
      ),
      '8000',
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    ))!;
    final t = book.txs.first;
    expect(t.category, '還款');
    expect(t.merchant, '台新信貸');
    expect(t.amount, 8000);
    expect(tester.takeException(), isNull);
  });

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
        (w) => w is TextField && w.decoration?.hintText == '0',
      ),
      '58000',
    );
    await tester.pump();
    // 收入分類也有「未分類」（不知道算什麼收入時選）。
    expect(find.widgetWithText(ChoiceChip, '❔ 未分類'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await tester.tap(find.widgetWithText(ChoiceChip, '🔁 平轉'));
    await tester.pump();
    // 平轉要選來源戶頭（2026-11-11）。
    await tester.ensureVisible(find.byKey(const ValueKey('fromExt_LineBank')));
    await tester.tap(find.byKey(const ValueKey('fromExt_LineBank')));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = await LedgerRepository(store).loadBook();
    final t = book.txs.firstWhere((x) => x.amount == 58000);
    expect(t.toName, 'LineBank');
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

/// 貼上匯入第 1 欄寫「台新銀行」要對到台新卡（2026-11-10 使用者），不是第一張卡。
void accountMatchTests() {
  test('貼上匯入：第 1 欄的銀行名稱對到同銀行的信用卡（支出）／活存（收入）', () async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final zhong = await repo.addAccount(
      name: '中信信用卡',
      type: LedgerAccountType.creditCard,
      opening: 90000,
      openingAt: DateTime(2026, 11, 1),
      creditLimit: 100000,
    );
    final taishin = await repo.addAccount(
      name: '台新卡',
      type: LedgerAccountType.creditCard,
      opening: 50000,
      openingAt: DateTime(2026, 11, 1),
      creditLimit: 60000,
    );
    final taishinBank = await repo.addAccount(
      name: '台新活存',
      type: LedgerAccountType.bank,
      opening: 1000,
      openingAt: DateTime(2026, 11, 1),
    );
    final book = await repo.loadBook();
    final l = book.parseImport(
      '台新銀行｜2026/10/06 10:52｜帳單｜聯徵查詢費｜80｜｜｜｜｜｜Cen調聯徵費用\n'
      '台新銀行｜2026/10/07 10:52｜收入存款｜某人｜500\n'
      '郵局｜2026/10/08 10:52｜餐飲｜便當｜100',
    );
    expect(l[0].tx!.type, LedgerTxType.expense);
    expect(l[0].tx!.accountId, taishin.id);
    expect(l[1].tx!.type, LedgerTxType.income);
    expect(l[1].tx!.accountId, taishinBank.id);
    // 對不到的銀行還是記在第一張信用卡。
    expect(l[2].tx!.accountId, zhong.id);
  });
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
      '中信活存｜2026-11-10 11:00｜ATM存入｜ATM｜300\n'
      '中信銀行｜2026/07/01 11:06｜收入存款｜未分類｜6000｜｜｜｜｜｜存款入帳\n'
      '中信銀行｜2026/07/01 12:06｜帳戶存款｜未分類｜700',
    );
    expect(v[3].tx!.category, '其他收入');
    expect(v[4].tx!.type, LedgerTxType.income);
    expect(v[4].tx!.category, '其他收入');
    // 收入＋分類一次寫好；單獨的「未分類」「其他」仍是支出。
    final w = book.parseImport(
      '中信銀行｜2026/07/02 10:00｜收入/未分類｜某人｜100\n'
      '中信銀行｜2026/07/02 10:01｜收入未分類｜某人｜101\n'
      '中信銀行｜2026/07/02 10:02｜ATM存款／平轉｜ATM｜102\n'
      '中信銀行｜2026/07/02 10:03｜收入-薪資｜公司｜103\n'
      '中信銀行｜2026/07/02 10:04｜收入｜某人｜104\n'
      '中信銀行｜2026/07/02 10:05｜未分類｜某店｜105',
    );
    expect(w.take(5).every((l) => l.tx!.type == LedgerTxType.income), isTrue);
    expect(w.take(5).map((l) => l.tx!.category).toList(), [
      '未分類',
      '未分類',
      '平轉',
      '薪資',
      '其他收入',
    ]);
    expect(w[5].tx?.type, isNot(LedgerTxType.income));
    // 收入第 11 欄（品項名稱的位置）有字、備註沒寫 → 當備註；兩個都有就用第 10 欄的備註。
    final n = book.parseImport(
      '中信銀行｜2026/07/06 01:06｜收入/未分類｜未分類｜10000｜｜｜｜｜｜存款入帳\n'
      '中信銀行｜2026/07/06 01:07｜收入/未分類｜未分類｜10001｜｜｜｜｜自己寫的備註｜存款入帳',
    );
    expect(n[0].tx!.type, LedgerTxType.income);
    expect(n[0].tx!.category, '未分類');
    expect(n[0].tx!.note, '存款入帳');
    expect(n[1].tx!.note, '自己寫的備註');
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

  testWidgets('設定裡「消費、總支出、收入怎麼算」說明打得開', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showLedgerTermsDialog(c),
            child: const Text('開'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    expect(find.text('消費、總支出、收入怎麼算'), findsOneWidget);
    expect(find.textContaining('總支出＝消費＋幫別人付'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(find.textContaining('總支出＝'), findsNothing);
  });
}
