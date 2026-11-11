import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';
import 'package:lume/features/ledger/ledger_ui.dart';

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
    await pickDefaultAccount(tester);
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

  testWidgets('快捷「虛擬貨幣入金」：選好 LineBank → 虛擬貨幣、名稱自動帶；兩邊都能填這筆之後、旁邊有推算', (
    tester,
  ) async {
    final store = _MemoryStore();
    final (repo, _, _) = await setup(tester, store);
    await open(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cryptoDeposit')));
    await settle(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('srcExt_LineBank')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('toExt_虛擬貨幣')))
          .selected,
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '虛擬貨幣入金',
      ),
      findsOneWidget,
    );
    final amountField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
    );
    await tester.enterText(amountField, '3200');
    await tester.pump();
    // 金額寫的是轉出的台幣；USDT 一定要填，下面寫多少換多少。
    expect(find.text('轉出台幣'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('usdtTwd'))).data,
      startsWith('要填換到多少 USDT'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('usdtField')));
    await tester.enterText(find.byKey(const ValueKey('usdtField')), '100');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('usdtTwd'))).data,
      r'$3,200 → 100 USDT・1 USDT ≈ $32.00',
    );
    final from = find.byKey(const ValueKey('srcExtAfter'));
    final to = find.byKey(const ValueKey('extAfter'));
    await tester.ensureVisible(to);
    expect(from, findsOneWidget);
    expect(to, findsOneWidget);
    // 沒填：旁邊寫推算。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('srcExtAfterNote'))).data,
      contains('還沒填過 LineBank'),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('extAfterNote'))).data,
      contains('還沒填過 虛擬貨幣'),
    );
    await tester.enterText(from, '12000');
    await tester.enterText(to, '250.5');
    await tester.pump();
    await pickDefaultAccount(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final tx = book.txs.single;
    expect(tx.merchant, '虛擬貨幣入金');
    expect(tx.fromName, 'LineBank');
    expect(tx.toName, '虛擬貨幣');
    expect(tx.fromAfter, 12000);
    expect(tx.toAfter, 250.5);
    expect(book.fxLine(tx), r'$3,200 → 100 USDT・1 USDT ≈ $32.00');
    // 有填就是新的起點。
    expect(book.extBalance('LineBank'), 12000);
    expect(book.usdtBalance(), 250.5);
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
    // 反過來也寫多少換多少：賣掉 50 USDT 拿回 $1,600。
    expect(
      b.fxLine(b.txs.firstWhere((t) => t.id == 'b')),
      r'50 USDT → $1,600・1 USDT ≈ $32.00',
    );
    expect(b.fromLabel(b.txs.firstWhere((t) => t.id == 'b')), '虛擬貨幣');
  });

  testWidgets('編輯拆分：每一份的分類是毛玻璃按鈕，點了用毛玻璃選單換分類', (tester) async {
    final store = _MemoryStore();
    final (repo, bank, _) = await setup(tester, store);
    final now = DateTime.now();
    await repo.addTransaction(
      LedgerTx(
        id: 's1',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 9),
        amount: 300,
        accountId: bank.id,
        category: '餐飲',
        merchant: '全聯',
        splits: const [
          LedgerSplit(category: '餐飲', amount: 200),
          LedgerSplit(category: '旅遊', amount: 100),
        ],
      ),
    );
    await open(tester, store);
    await tester.tap(find.text('全聯'));
    await settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle(tester);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final second = find.byKey(const ValueKey('splitCat_1'));
    await tester.ensureVisible(second);
    expect(
      find.descendant(of: second, matching: find.text('旅遊')),
      findsOneWidget,
      reason: '舊分類照顯示',
    );
    await tester.tap(second);
    await settle(tester);
    await tester.tap(find.text('🚕 交通').last);
    await settle(tester);
    expect(
      find.descendant(of: second, matching: find.text('🚕 交通')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    final tx = (await tester.runAsync(() => repo.loadBook()))!.txs.single;
    expect(tx.splits.map((s) => s.category), ['餐飲', '交通']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒確認的右上角有小藍點；點進明細「標成已確認」存起來、進操作紀錄、藍點消失；篩選「未確認」', (tester) async {
    final store = _MemoryStore();
    final (repo, bank, _) = await setup(tester, store);
    final now = DateTime.now();
    for (final (id, m) in [('a', '早餐店'), ('b', '全家')]) {
      await repo.addTransaction(
        LedgerTx(
          id: id,
          type: LedgerTxType.expense,
          occurredAt: DateTime(now.year, now.month, now.day, 9),
          amount: id == 'a' ? 80 : 50,
          accountId: bank.id,
          category: '餐飲',
          merchant: m,
        ),
      );
    }
    await open(tester, store);
    expect(find.byKey(const ValueKey('unconfirmed_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('unconfirmed_b')), findsOneWidget);
    await tester.tap(find.text('早餐店'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirmToggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('unconfirmed_a')), findsNothing);
    expect(find.byKey(const ValueKey('unconfirmed_b')), findsOneWidget);
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    expect(book.tx('a')!.confirmed, isTrue);
    expect(book.tx('b')!.confirmed, isFalse);
    final log = (await tester.runAsync(() => repo.loadLog()))!;
    expect(log.any((e) => e.action == '已確認'), isTrue);
    // 篩選「未確認」：早餐店（已確認）不見、全家還在。
    await tester.tap(find.byKey(const ValueKey('filterBtn')));
    await settle(tester);
    await tester.tap(find.textContaining('未確認'));
    await settle(tester);
    expect(find.text('早餐店'), findsNothing);
    expect(find.text('全家'), findsOneWidget);
    // ✕ 取消篩選。
    await tester.tap(find.byKey(const ValueKey('filterClear')));
    await settle(tester);
    expect(find.text('早餐店'), findsOneWidget);
    // 再點進去「取消確認」。
    await tester.tap(find.text('早餐店'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirmToggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('unconfirmed_a')), findsOneWidget);
    expect(
      (await tester.runAsync(() => repo.loadBook()))!.tx('a')!.confirmed,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  test('品牌圖示：ATM 維持 🏧、LineBank、中信卡、中信帳戶轉出', () {
    const bank = LedgerAccount(
      id: 'bank',
      name: '中信活存',
      type: LedgerAccountType.bank,
    );
    const card = LedgerAccount(
      id: 'card',
      name: '中信卡',
      type: LedgerAccountType.creditCard,
    );
    const cash = LedgerAccount(
      id: 'cash',
      name: '現金',
      type: LedgerAccountType.cash,
    );
    LedgerTx tx(
      LedgerTxType ty, {
      String acc = 'bank',
      String? to,
      String toName = '',
      String fromName = '',
    }) => LedgerTx(
      id: 'x',
      type: ty,
      occurredAt: DateTime(2026, 11, 1),
      amount: 100,
      accountId: acc,
      toAccountId: to,
      toName: toName,
      fromName: fromName,
    );
    final b = LedgerBook(
      accounts: const [bank, card, cash],
      checkpoints: const [],
      budgets: const [],
      txs: const [],
    );
    String? a(LedgerTx t) => ledgerBrandOf(b, t)?.asset.split('/').last;
    expect(a(tx(LedgerTxType.transfer, to: 'cash')), isNull, reason: 'ATM');
    // icon 由錢從哪裡出去決定：中信帳戶平轉到 LineBank＝中信；從 LineBank 轉出＝LINE Bank。
    expect(a(tx(LedgerTxType.transfer, toName: 'LineBank')), 'ctbc.png');
    expect(
      a(tx(LedgerTxType.transfer, acc: 'cash', toName: 'LineBank')),
      isNull,
      reason: '轉出那邊（現金）沒有品牌就用原本的，不看轉入',
    );
    expect(
      a(tx(LedgerTxType.transfer, acc: '', fromName: 'LineBank', to: 'bank')),
      'linebank.png',
    );
    expect(a(tx(LedgerTxType.expense, acc: 'card')), 'ctbc_linepay.png');
    // 錢從中信帳戶出去的支出也是中信 logo。
    expect(a(tx(LedgerTxType.expense)), 'ctbc.png');
    // 純收款看哪邊收錢：薪水進中信帳戶＝中信；進現金＝原本的。
    expect(a(tx(LedgerTxType.income)), 'ctbc.png');
    expect(a(tx(LedgerTxType.income, acc: 'cash')), isNull);
    expect(
      a(tx(LedgerTxType.transfer, to: 'card')),
      'ctbc.png',
      reason: '繳卡費看轉出的中信帳戶',
    );
    expect(
      a(tx(LedgerTxType.transfer, acc: 'cash', to: 'card')),
      isNull,
      reason: '從現金繳卡費，錢從現金出去',
    );
    expect(
      a(tx(LedgerTxType.transfer, toName: '虛擬貨幣')),
      'ctbc.png',
      reason: '中信帳戶轉出',
    );
    expect(
      ledgerBrandOf(b, tx(LedgerTxType.transfer, toName: '虛擬貨幣'))!.pad,
      isTrue,
    );
    expect(a(tx(LedgerTxType.expense, acc: 'cash')), isNull);
    expect(ledgerAccountBrand(card)!.asset, endsWith('ctbc_linepay.png'));
    expect(ledgerAccountBrand(cash), isNull);
  });

  test('虛擬貨幣餘額跟推算有差：算出差多少 USDT，確認是盈虧的存起來', () {
    LedgerTx tr(String id, int day, {double? after, bool ok = false}) =>
        LedgerTx(
          id: id,
          type: LedgerTxType.transfer,
          occurredAt: DateTime(2026, 11, day),
          amount: 3200,
          accountId: 'bank',
          toName: '虛擬貨幣',
          extAmount: 100,
          toAfter: after,
          extPnlOk: ok,
        );
    final b = LedgerBook(
      accounts: const [],
      checkpoints: const [],
      budgets: const [],
      txs: [
        tr('a', 1, after: 100),
        tr('b', 2, after: 230, ok: true),
        tr('c', 3),
      ],
    );
    // 第二筆前面 100 + 這筆 100 = 推算 200，填 230 → 多 30（盈利）。
    expect(b.usdtDiffOf(b.tx('b')!), closeTo(30, 1e-9));
    expect(b.usdtDiffOf(b.tx('a')!), isNull);
    // 有填就是新起點：230 + 100。
    expect(b.usdtBalance(), closeTo(330, 1e-9));
    final j = LedgerTx.fromJson(b.tx('b')!.toJson());
    expect(j.extPnlOk, isTrue);
    expect(j.toAfter, 230);
  });

  testWidgets('新記一筆不預選帳戶、不預選分類', (tester) async {
    final store = _MemoryStore();
    await setup(tester, store);
    await open(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    String label(ChoiceChip c) => (c.label as Text).data ?? '';
    final selected = [
      for (final c in chips)
        if (c.selected) label(c),
    ];
    expect(selected, ['支出'], reason: '只有上面的類型是選著的');
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
        merchant: 'PCHOME*刷卡',
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
    expect(find.text('PCHOME*刷卡'), findsOneWidget, reason: '只在列表裡、下拉沒有');
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

/// 2026-11-11 起新記的不預選帳戶（使用者：不要預設選中信卡）：測試照以前的預設自己點
/// （支出＝第一張信用卡、收入＝第一個戶頭；轉帳照舊會自己帶）。已經選了就不動。
Future<void> pickDefaultAccount(WidgetTester tester) async {
  bool on(String t) => tester
      .widgetList<ChoiceChip>(find.widgetWithText(ChoiceChip, t))
      .any((c) => c.selected);
  if (on('轉帳')) return;
  final income = on('收入');
  final title = find.text(income ? '進哪個帳戶' : '用哪個付');
  if (title.evaluate().isEmpty) return;
  final row = find.ancestor(of: title.first, matching: find.byType(Row)).first;
  final chips = find.descendant(of: row, matching: find.byType(ChoiceChip));
  final list = tester.widgetList<ChoiceChip>(chips).toList();
  if (list.isEmpty || list.any((c) => c.selected)) return;
  String label(ChoiceChip c) => (c.label as Text).data ?? '';
  var i = list.indexWhere((c) => label(c).startsWith(income ? '🏦' : '💳'));
  if (i < 0) i = 0;
  await tester.ensureVisible(chips.at(i));
  await tester.tap(chips.at(i));
  await tester.pump();
}
