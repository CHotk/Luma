import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';

/// 記帳的算法（docs/記帳功能構想.md）：轉帳不算支出、幫別人付只算自己的、
/// 別人還錢不算收入、退款扣回分類、對帳差額、補記／調整後差額消失、
/// 貼上匯入、預算沿用。
void main() {
  final start = DateTime(2026, 10, 1);
  const bank = LedgerAccount(
    id: 'bank',
    name: '中信活存',
    type: LedgerAccountType.bank,
    order: 1,
  );
  const card = LedgerAccount(
    id: 'card',
    name: '中信信用卡',
    type: LedgerAccountType.creditCard,
    creditLimit: 100000,
    order: 2,
  );
  const cash = LedgerAccount(
    id: 'cash',
    name: '現金',
    type: LedgerAccountType.cash,
    order: 3,
  );
  final openings = [
    LedgerCheckpoint(id: 's1', accountId: 'bank', at: start, balance: 45000),
    LedgerCheckpoint(
      id: 's2',
      accountId: 'card',
      at: start,
      creditLimit: 100000,
      available: 87600,
    ),
    LedgerCheckpoint(id: 's3', accountId: 'cash', at: start, balance: 2000),
  ];
  var n = 0;
  LedgerTx tx(
    LedgerTxType type,
    int day,
    int amount,
    String account, {
    String? to,
    String? category = '餐飲',
    String merchant = '',
    String? linked,
    PaidFor? paidFor,
    String? dir,
    String? id,
  }) => LedgerTx(
    id: id ?? 't${++n}',
    type: type,
    occurredAt: DateTime(2026, 10, day, 12),
    amount: amount,
    accountId: account,
    toAccountId: to,
    category: category,
    merchant: merchant,
    linkedId: linked,
    paidFor: paidFor,
    dir: dir,
  );

  LedgerBook book(
    List<LedgerTx> txs, {
    List<LedgerCheckpoint> extra = const [],
    List<LedgerBudget> budgets = const [],
  }) => LedgerBook(
    accounts: const [bank, card, cash],
    txs: txs,
    checkpoints: [...openings, ...extra],
    budgets: budgets,
  );

  test('ATM 提款、繳卡費是轉帳：帳戶照動，但不算支出', () {
    final b = book([
      tx(LedgerTxType.transfer, 5, 3000, 'bank', to: 'cash', category: null),
      tx(LedgerTxType.transfer, 10, 12400, 'bank', to: 'card', category: null),
      tx(LedgerTxType.expense, 6, 120, 'cash'),
    ]);
    expect(b.monthStats(2026, 10).spend, 120);
    expect(b.stateOf(bank)!.now, 45000 - 3000 - 12400);
    expect(b.stateOf(cash)!.now, 2000 + 3000 - 120);
    // 信用卡已占用：起始 12,400，繳完卡費歸零。
    expect(b.stateOf(card)!.now, 0);
    expect(b.stateOf(card)!.available, 100000);
  });

  test('幫別人付：帳戶照整筆，消費只算自己的；別人還錢不算收入、扣掉還欠', () {
    final b = book([
      tx(
        LedgerTxType.expense,
        9,
        1000,
        'card',
        id: 'din',
        paidFor: const PaidFor(amount: 600, people: '小美'),
      ),
      tx(
        LedgerTxType.repayment,
        14,
        250,
        'bank',
        linked: 'din',
        category: null,
      ),
    ]);
    final st = b.monthStats(2026, 10);
    expect(st.spend, 400);
    expect(st.income, 0);
    expect(b.stateOf(card)!.now, 12400 + 1000);
    expect(b.stateOf(bank)!.now, 45000 + 250);
    expect(b.oweTotal, 350);
    expect(b.owes.single.left, 350);
  });

  test('標記已還清就不算進「別人還欠你」', () {
    final b = book([
      tx(
        LedgerTxType.expense,
        9,
        1000,
        'card',
        paidFor: const PaidFor(amount: 600, people: '小美', settled: true),
      ),
    ]);
    expect(b.owes, isEmpty);
  });

  test('退款從原本那筆的分類扣回，信用卡占用也回來', () {
    final b = book([
      tx(LedgerTxType.expense, 13, 1290, 'card', category: '購物', id: 'shp'),
      tx(LedgerTxType.expense, 14, 500, 'card', category: '購物'),
      tx(LedgerTxType.refund, 18, 1290, 'card', linked: 'shp', category: null),
    ]);
    expect(b.monthStats(2026, 10).byCategory['購物'], 500);
    expect(b.stateOf(card)!.now, 12400 + 500);
    expect(b.refundable.map((t) => t.id), isNot(contains('shp')));
  });

  test('對帳：銀行少了錢＝可能漏記支出；補記在對帳之前，差額消失', () {
    final txs = [tx(LedgerTxType.expense, 21, 599, 'bank', category: '帳單')];
    final cp = LedgerCheckpoint(
      id: 'c1',
      accountId: 'bank',
      at: DateTime(2026, 10, 24, 20),
      balance: 45000 - 599 - 630,
    );
    var b = book(txs, extra: [cp]);
    expect(b.stateOf(bank)!.miss, 630);
    expect(b.checkpointDiff(bank, cp)!.miss, 630);

    // 補記一筆（時間在對帳前一分鐘）。
    b = book(
      [
        ...txs,
        LedgerTx(
          id: 'fix',
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 10, 24, 19, 59),
          amount: 630,
          accountId: 'bank',
          category: '未分類',
          cpId: 'c1',
        ),
      ],
      extra: [cp],
    );
    expect(b.stateOf(bank)!.miss, 0);
  });

  test('對帳：信用卡用可用額度算占用，多占了＝可能漏記刷卡', () {
    final txs = [tx(LedgerTxType.expense, 16, 189, 'card')];
    final cp = LedgerCheckpoint(
      id: 'c1',
      accountId: 'card',
      at: DateTime(2026, 10, 24, 20),
      creditLimit: 100000,
      // 實際占用 12,400 + 189 + 295 漏記。
      available: 100000 - (12400 + 189 + 295),
    );
    final b = book(txs, extra: [cp]);
    expect(b.stateOf(card)!.miss, 295);
  });

  test('對帳：現金差額直接調成未分類，算進消費、差額歸零', () {
    final cp = LedgerCheckpoint(
      id: 'c1',
      accountId: 'cash',
      at: DateTime(2026, 10, 15, 21),
      balance: 2000 - 180,
    );
    expect(book([], extra: [cp]).stateOf(cash)!.miss, 180);
    final b = book(
      [
        LedgerTx(
          id: 'adj',
          type: LedgerTxType.adjustment,
          dir: 'out',
          occurredAt: DateTime(2026, 10, 15, 20, 59),
          amount: 180,
          accountId: 'cash',
          category: '未分類',
          source: 'adjust',
        ),
      ],
      extra: [cp],
    );
    expect(b.stateOf(cash)!.miss, 0);
    expect(b.monthStats(2026, 10).byCategory['未分類'], 180);
  });

  test('預授權：這次先多占、下次對帳少占，兩次加起來差額自己抵掉', () {
    final cp1 = LedgerCheckpoint(
      id: 'c1',
      accountId: 'card',
      at: DateTime(2026, 10, 10),
      creditLimit: 100000,
      available: 100000 - 12400 - 3000, // 飯店先占 3,000
    );
    final cp2 = LedgerCheckpoint(
      id: 'c2',
      accountId: 'card',
      at: DateTime(2026, 10, 20),
      creditLimit: 100000,
      available: 100000 - 12400 - 2500, // 真的請款 2,500
    );
    expect(book([], extra: [cp1]).stateOf(card)!.miss, 3000);
    final b = book(
      [tx(LedgerTxType.expense, 15, 2500, 'card', category: '購物')],
      extra: [cp1, cp2],
    );
    expect(b.stateOf(card)!.miss, 0);
  });

  test('貼上匯入：提款變轉帳、重複的跳過、起始日前標出來、看不懂的報錯', () {
    final b = book([
      LedgerTx(
        id: 'ktv',
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 10, 12, 21, 10),
        amount: 1267,
        accountId: 'card',
        category: '娛樂',
        merchant: '凱悅KTV新莊店',
      ),
    ]);
    final lines = b.parseImport('''
中信銀行｜2026/10/22 12:05｜餐飲｜foodpanda｜NT\$295
中信銀行｜2026/10/12 21:10｜娛樂｜凱悅KTV新莊店｜NT\$1,267
中信銀行｜2026/07/27 19:02｜提款｜ATM提款｜NT\$3,000
中信銀行｜2026/09/22 10:40｜奇怪分類｜綠界科技｜NT\$125
中信銀行｜2026/10/22 12:05｜餐飲｜foodpanda｜NT\$295
只有一欄
''');
    expect(lines, hasLength(6));
    expect(lines[0].willImport, isTrue);
    expect(lines[0].tx!.accountId, 'card');
    expect(lines[1].duplicate, isTrue);
    expect(lines[2].tx!.type, LedgerTxType.transfer);
    expect(lines[2].tx!.accountId, 'bank');
    expect(lines[2].tx!.toAccountId, 'cash');
    expect(lines[2].beforeStart, isTrue);
    expect(lines[3].tx!.category, '未分類');
    expect(lines[3].unknownCategory, '奇怪分類');
    expect(lines[4].duplicate, isTrue, reason: '同一次貼兩行一樣的');
    expect(lines[5].error, isNotNull);
  });

  test('貼上匯入：第一欄寫帳戶名稱就記那裡；第 6、7 欄是跟誰、對方要給', () {
    final lines = book([]).parseImport('''
現金｜2026/11/03 12:30｜餐飲｜便當｜120
中信銀行｜2026/11/02 19:30｜餐飲｜鼎泰豐｜1000｜小美｜700
中信活存｜2026/11/01 09:00｜帳單｜中華電信｜599
中信銀行｜2026/11/02 20:00｜餐飲｜火鍋｜500｜小美｜900
''');
    expect(lines[0].tx!.accountId, 'cash');
    expect(lines[1].tx!.accountId, 'card');
    expect(lines[1].tx!.paidFor!.people, '小美');
    expect(lines[1].tx!.paidFor!.amount, 700);
    expect(lines[1].tx!.ownSpend, 300);
    expect(lines[2].tx!.accountId, 'bank');
    expect(lines[3].error, isNotNull, reason: '對方要給不能超過整筆');
  });

  test('防重複：同一個帳戶、同一分鐘、同金額就算重複，商家不一樣也是', () {
    final b = book([
      LedgerTx(
        id: 'a',
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 11, 2, 19, 30, 12),
        amount: 1000,
        accountId: 'card',
        category: '餐飲',
        merchant: '鼎泰豐',
      ),
    ]);
    expect(
      b.sameMinute('card', DateTime(2026, 11, 2, 19, 30, 50), 1000),
      isNotNull,
    );
    expect(b.sameMinute('card', DateTime(2026, 11, 2, 19, 31), 1000), isNull);
    expect(b.sameMinute('card', DateTime(2026, 11, 2, 19, 30), 999), isNull);
    expect(b.sameMinute('cash', DateTime(2026, 11, 2, 19, 30), 1000), isNull);
    expect(
      b.sameMinute('card', DateTime(2026, 11, 2, 19, 30), 1000, exceptId: 'a'),
      isNull,
    );
    final lines = b.parseImport('''
中信銀行｜2026/11/02 19:30｜餐飲｜DIN TAI FUNG｜NT\$1,000
中信銀行｜2026/11/02 19:45｜餐飲｜甜點｜NT\$200
中信銀行｜2026/11/02 19:45｜購物｜另一家｜NT\$200
''');
    expect(lines[0].duplicate, isTrue, reason: '跟已經記的同分鐘同金額');
    expect(lines[1].duplicate, isFalse);
    expect(lines[2].duplicate, isTrue, reason: '同一次貼的兩行同分鐘同金額');
  });

  test('貼上匯入「轉帳」：轉到自己的帳戶不算支出；轉給別人算支出', () {
    final lines = book([]).parseImport('''
中信活存｜2026/11/01 11:00｜轉帳｜現金｜5000
中信活存｜2026/11/01 12:00｜轉帳｜小美｜800
中信活存｜2026/11/01 13:00｜轉帳｜中信活存｜100
''');
    expect(lines[0].tx!.type, LedgerTxType.transfer);
    expect(lines[0].tx!.accountId, 'bank');
    expect(lines[0].tx!.toAccountId, 'cash');
    expect(lines[1].tx!.type, LedgerTxType.expense);
    expect(lines[1].tx!.merchant, '轉給 小美');
    expect(lines[1].tx!.ownSpend, 800);
    expect(lines[2].error, isNotNull);
  });

  test('沒填餘額的帳戶：不算餘額、不參與對帳，但交易照樣算消費', () {
    final b = LedgerBook(
      accounts: const [bank],
      txs: [tx(LedgerTxType.expense, 3, 200, 'bank')],
      checkpoints: const [],
      budgets: const [],
    );
    expect(b.stateOf(bank), isNull);
    expect(b.states, isEmpty);
    expect(b.monthStats(2026, 10).spend, 200);
  });

  test('起始日前匯入的紀錄只算消費，不影響對帳', () {
    final b = book([
      LedgerTx(
        id: 'old',
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 9, 23),
        amount: 295,
        accountId: 'card',
        category: '餐飲',
      ),
    ]);
    expect(b.monthStats(2026, 9).spend, 295);
    expect(b.stateOf(card)!.now, 12400);
  });

  test('預算：這個月沒設就沿用上一個有設的月份；設 0 代表不限制', () {
    final b = book(
      [],
      budgets: const [
        LedgerBudget(month: '2026-10', category: null, amount: 30000),
        LedgerBudget(month: '2026-10', category: '餐飲', amount: 6000),
        LedgerBudget(month: '2026-10', category: '娛樂', amount: 0),
      ],
    );
    final oct = b.budgetOf(2026, 10);
    expect(oct.total, 30000);
    expect(oct.byCategory, {'餐飲': 6000});
    expect(oct.carriedFrom, isNull);
    final dec = b.budgetOf(2026, 12);
    expect(dec.total, 30000);
    expect(dec.carriedFrom, '2026-10');
    expect(b.budgetOf(2026, 9).total, 0);
  });

  test('刪除的交易不算', () {
    final b = book([
      tx(
        LedgerTxType.expense,
        3,
        486,
        'card',
      ).copyWith(deletedAt: DateTime(2026, 10, 4)),
    ]);
    expect(b.monthStats(2026, 10).spend, 0);
    expect(b.stateOf(card)!.now, 12400);
  });

  test('JSON 來回：時間帶時區、金額整數、paidFor 保留', () {
    final t = tx(
      LedgerTxType.expense,
      9,
      2400,
      'card',
      paidFor: const PaidFor(amount: 1200, people: '阿明、小華'),
    );
    final j = t.toJson();
    expect(j['occurredAt'] as String, matches(RegExp(r'[+-]\d\d:\d\d$')));
    final back = LedgerTx.fromJson(j);
    expect(back.occurredAt, t.occurredAt);
    expect(back.paidFor!.amount, 1200);
    expect(back.ownSpend, 1200);
    expect(ledgerId(), matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
