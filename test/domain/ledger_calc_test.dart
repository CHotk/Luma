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

  test('貼上匯入第 11 欄是品項名稱：支出、轉給別人有，太長擋下，提款沒有', () {
    final b = book(const []);
    final lines = b.parseImport('''
現金｜2026/11/05 18:00｜餐飲｜全家｜35｜｜｜｜｜｜御飯糰
現金｜2026/11/05 19:00｜餐飲｜便當店｜80
現金｜2026/11/05 20:00｜餐飲｜超商｜60｜｜｜｜｜｜${'字' * 51}
中信活存｜2026/11/05 21:00｜轉帳｜小美｜500｜｜｜｜｜｜幫買飲料
''');
    expect(lines[0].tx!.item, '御飯糰');
    expect(lines[0].tx!.note, '');
    expect(lines[1].tx!.item, '');
    expect(lines[2].error, contains('品項名稱太長'));
    expect(lines[3].tx!.item, '幫買飲料');
  });

  test('繳卡費：戶頭餘額、可刷額兩邊都填，任何一邊對不上這筆都掛漏記', () {
    // 起始：戶頭 45,000、卡占用 12,400。10/10 繳卡費 12,400。
    final pay = tx(
      LedgerTxType.transfer,
      10,
      12400,
      'bank',
      to: 'card',
      category: null,
      id: 'pay',
    );
    LedgerCheckpoint cp(String acc, {int? balance, int? available}) =>
        LedgerCheckpoint(
          id: 'c-$acc',
          accountId: acc,
          at: pay.occurredAt,
          txId: 'pay',
          balance: balance,
          available: available,
          creditLimit: acc == 'card' ? 100000 : null,
        );
    // 兩邊都對：沒有缺。
    var b = book(
      [pay],
      extra: [cp('bank', balance: 32600), cp('card', available: 100000)],
    );
    expect(b.gapOfTx('pay'), isNull);
    // 戶頭少了 500（中間有支出沒記），卡那邊是對的：還是要掛。
    b = book(
      [pay],
      extra: [cp('bank', balance: 32100), cp('card', available: 100000)],
    );
    expect(b.gapOfTx('pay')?.miss, 500);
    // 戶頭對、卡的可刷額比預期少 300：卡那邊對不上也要掛。
    b = book(
      [pay],
      extra: [cp('bank', balance: 32600), cp('card', available: 99700)],
    );
    expect(b.gapOfTx('pay')?.miss, 300);
  });

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

  test('幫別人全額刷 500：不算我的消費，但可刷卡餘額照扣；他給了（只標記）卡的餘額不變', () {
    final swipe = tx(
      LedgerTxType.expense,
      9,
      500,
      'card',
      id: 'allForHim',
      paidFor: const PaidFor(amount: 500, people: '小美'),
    );
    var b = book([swipe]);
    expect(b.monthStats(2026, 10).spend, 0, reason: '不算我的消費');
    expect(b.stateOf(card)!.now, 12400 + 500, reason: '卡的占用照加');
    expect(b.stateOf(card)!.available, 100000 - 12400 - 500, reason: '可刷卡餘額照扣');
    expect(b.oweTotal, 500);
    // 他給了：只標記，卡的可刷卡餘額不變（他的錢怎麼給你、你怎麼繳卡費是另一回事）。
    b = book([
      swipe.copyWith(paidFor: () => swipe.paidFor!.copyWith(settled: true)),
    ]);
    expect(b.stateOf(card)!.available, 100000 - 12400 - 500);
    expect(b.oweTotal, 0);
    expect(b.monthStats(2026, 10).spend, 0);
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

  test('貼上匯入：提款變轉帳、重複的跳過、起始日前標出來、不認得的分類跟看不懂的報錯', () {
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
    expect(lines[3].tx, isNull, reason: 'App 沒有的分類要擋下來');
    expect(lines[3].error, contains('奇怪分類'));
    expect(lines[3].error, contains('創業魔物童話'), reason: '要列出可用的分類');
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
    expect(lines[1].tx!.paidFor!.settled, isFalse);
    final given = book(
      [],
    ).parseImport('中信銀行｜2026/11/01 20:00｜餐飲｜火鍋｜900｜小美｜450｜已給');
    expect(given.single.tx!.paidFor!.settled, isTrue);
    expect(given.single.tx!.ownSpend, 450);
    final bad = book([]).parseImport('''
中信銀行｜2026/11/02 19:30｜餐飲｜鼎泰豐｜1000｜|｜已給
中信銀行｜2026/11/02 19:40｜餐飲｜鼎泰豐｜1000｜｜700
中信銀行｜2026/11/02 19:50｜餐飲｜鼎泰豐｜1000｜小美
中信銀行｜2026/11/02 20:00｜餐飲｜鼎泰豐｜1000｜｜
''');
    expect(bad[0].error, isNotNull);
    expect(bad[1].error, isNotNull);
    expect(bad[2].error, isNotNull);
    expect(bad[3].tx!.paidFor, isNull, reason: '後面欄位全空就是一般消費');
  });

  test('防重複：同一個帳戶、同一分鐘、同金額、同商店才算重複；商店不同是兩筆', () {
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
    // 商店也要一樣（2026-11-10 使用者）：忽略空白、大小寫；沒給商店就不比；其中一邊沒寫商店當一樣。
    final at = DateTime(2026, 11, 2, 19, 30);
    expect(b.sameMinute('card', at, 1000, merchant: '鼎泰豐'), isNotNull);
    expect(b.sameMinute('card', at, 1000, merchant: ' 鼎 泰豐 '), isNotNull);
    expect(b.sameMinute('card', at, 1000, merchant: '別家店'), isNull);
    expect(b.sameMinute('card', at, 1000, merchant: ''), isNotNull);
    expect(LedgerBook.sameShop('Starbucks', 'starbucks'), isTrue);
    expect(LedgerBook.sameShop('星巴克', '路易莎'), isFalse);
    final lines = b.parseImport(r'''
中信銀行｜2026/11/02 19:30｜餐飲｜鼎泰豐｜NT$1,000
中信銀行｜2026/11/02 19:30｜餐飲｜DIN TAI FUNG｜NT$1,000
中信銀行｜2026/11/02 19:45｜餐飲｜甜點｜NT$200
中信銀行｜2026/11/02 19:45｜生活｜另一家｜NT$200
中信銀行｜2026/11/02 19:45｜餐飲｜甜點｜NT$200
''');
    expect(lines[0].duplicate, isTrue, reason: '跟已經記的同分鐘同金額同商店');
    expect(lines[1].duplicate, isFalse, reason: '商店不同（銀行英文名）不當重複');
    expect(lines[2].duplicate, isFalse);
    expect(lines[3].duplicate, isFalse, reason: '同分鐘同金額但不同店是兩筆');
    expect(lines[4].duplicate, isTrue, reason: '同一次貼的兩行同分鐘同金額同商店');
  });

  test('餘額附在交易上：下一筆餘額對不上就掛漏記，補上中間那筆標籤就消失', () {
    LedgerTx spend(String id, int day, int amount) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, day, 12),
      amount: amount,
      accountId: 'bank',
      category: '餐飲',
    );
    LedgerCheckpoint after(String txId, int day, int balance) =>
        LedgerCheckpoint(
          id: 'cp$txId',
          accountId: 'bank',
          at: DateTime(2026, 11, day, 12),
          balance: balance,
          txId: txId,
        );
    LedgerBook make(List<LedgerTx> txs, List<LedgerCheckpoint> cps) =>
        LedgerBook(
          accounts: const [bank],
          txs: txs,
          checkpoints: cps,
          budgets: const [],
        );
    final t1 = spend('a', 1, 100), t2 = spend('b', 2, 100);
    // 第一筆餘額 1000 是起點；第二筆花 100 餘額卻剩 400 → 漏記 500。
    var b = make([t1, t2], [after('a', 1, 1000), after('b', 2, 400)]);
    expect(b.gapOfTx('a'), isNull, reason: '第一個餘額是起點');
    expect(b.gapOfTx('b')!.miss, 500);
    // 補上中間漏掉的 500（時間放在兩個餘額中間）：標籤消失。
    final fix = LedgerTx(
      id: 'fix',
      type: LedgerTxType.expense,
      occurredAt: b.fixTimeFor(b.checkpointOfTx('b')!),
      amount: 500,
      accountId: 'bank',
      category: '未分類',
    );
    expect(fix.occurredAt.isAfter(DateTime(2026, 11, 1, 12)), isTrue);
    expect(fix.occurredAt.isBefore(DateTime(2026, 11, 2, 12)), isTrue);
    b = make([t1, t2, fix], [after('a', 1, 1000), after('b', 2, 400)]);
    expect(b.gapOfTx('b'), isNull);
    // 前面的缺失不會污染後面：第三筆照第二筆的實際餘額算，對得上就沒標籤。
    final t3 = spend('c', 3, 50);
    b = make(
      [t1, t2, t3],
      [after('a', 1, 1000), after('b', 2, 400), after('c', 3, 350)],
    );
    expect(b.gapOfTx('b')!.miss, 500);
    expect(b.gapOfTx('c'), isNull);
    // 沒填餘額的交易沒有標籤。
    expect(make([t1], [after('a', 1, 1000)]).gapOfTx('zzz'), isNull);
  });

  test('時間不確定的同一天：餘額、對帳照排序數字線性計算（不是看列表、也不是同一個時間點）', () {
    LedgerTx spend(String id, int amount, {int order = 0, int h = 12}) =>
        LedgerTx(
          id: id,
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, 5, h),
          amount: amount,
          accountId: 'bank',
          category: '餐飲',
          timeUnknown: h == 12 && order != -1,
          timeOrder: order < 0 ? 0 : order,
          createdAt: DateTime(2026, 11, 5, 20, amount % 60),
        );
    LedgerCheckpoint after(String txId, int balance) => LedgerCheckpoint(
      id: 'cp$txId',
      accountId: 'bank',
      at: DateTime(2026, 11, 5, 12), // 存的時間都是中午，算的時候依排序換成當天的位置
      balance: balance,
      txId: txId,
    );
    LedgerBook make(List<LedgerTx> txs, List<LedgerCheckpoint> cps) =>
        LedgerBook(
          accounts: const [bank],
          txs: txs,
          checkpoints: cps,
          budgets: const [],
        );
    // 依序花：a 排序 3（餘額 1000 當起點）→ b 排序 5 花 200 剩 800 → c 排序 25（當天最後）花 50 剩 750。
    final a = spend('a', 100, order: 3);
    final b = spend('b', 200, order: 5);
    final c = spend('c', 50, order: 25);
    final cps = [after('a', 1000), after('b', 800), after('c', 750)];
    var book = make([a, b, c], cps);
    expect(book.gapOfTx('b'), isNull, reason: 'a(3) → b(5)：1000 − 200 = 800');
    expect(book.gapOfTx('c'), isNull, reason: 'b(5) → c(25)：800 − 50 = 750');
    // 目前餘額照最後一個餘額點（c）算＝750。
    expect(book.stateOf(bank)!.now, 750);
    // 把 b 的排序改成 2（排到 a 前面）：順序變 b → a → c，a 花 100 應該剩 700、卻記 1000 → 對不上。
    book = make([a, spend('b', 200, order: 2), c], cps);
    expect(
      book.gapOfTx('a')!.miss,
      -300,
      reason: 'b(2) 剩 800 → a(3) 花 100 應 700，記 1000：多出 300',
    );
    // 沒設排序（0）也不會平手：照建立先後，每一筆位置都不一樣。
    final t = make([spend('x', 10), spend('y', 20), spend('z', 30)], const []);
    final times = t.txs.map(t.calcAtOf).toSet();
    expect(times.length, 3);
    // 列表順序跟計算順序一樣：新的在前＝排序大的在前。
    expect(make([a, b, c], cps).txs.map((e) => e.id).toList(), ['c', 'b', 'a']);
  });

  test('同一個時間點的好幾筆（轉帳轉出、刷卡剛好同一分鐘）：照建立先後線性計算，轉出的錢要扣到、不會誤報漏記', () {
    const cash = LedgerAccount(
      id: 'cash',
      name: '現金',
      type: LedgerAccountType.cash,
      order: 3,
    );
    final at = DateTime(2026, 11, 5, 12, 0);
    LedgerTx tx(
      String id,
      LedgerTxType type,
      int amount,
      int createdMin, {
      String? to,
    }) => LedgerTx(
      id: id,
      type: type,
      occurredAt: at,
      amount: amount,
      accountId: 'bank',
      toAccountId: to,
      category: type == LedgerTxType.expense ? '餐飲' : null,
      createdAt: DateTime(2026, 11, 5, 12, createdMin),
    );
    LedgerCheckpoint cp(String txId, String acc, int bal) => LedgerCheckpoint(
      id: 'cp$txId$acc',
      accountId: acc,
      at: at,
      balance: bal,
      txId: txId,
    );
    // 起點：銀行 1000（11/1 手動對帳）；12:00 先轉 300 到現金（銀行剩 700、現金剩 300），
    // 同一分鐘又花 100（銀行剩 600）。
    final start = LedgerCheckpoint(
      id: 'start',
      accountId: 'bank',
      at: DateTime(2026, 11, 1),
      balance: 1000,
    );
    final cashStart = LedgerCheckpoint(
      id: 'cashStart',
      accountId: 'cash',
      at: DateTime(2026, 11, 1),
      balance: 0,
    );
    final book = LedgerBook(
      accounts: const [bank, cash],
      txs: [
        tx('t', LedgerTxType.transfer, 300, 1, to: 'cash'),
        tx('e', LedgerTxType.expense, 100, 2),
      ],
      checkpoints: [
        start,
        cashStart,
        cp('t', 'bank', 700),
        cp('t', 'cash', 300),
        cp('e', 'bank', 600),
      ],
      budgets: const [],
    );
    expect(book.gapOfTx('t'), isNull);
    expect(
      book.gapOfTx('e'),
      isNull,
      reason: '轉出 300 跟刷 100 同一分鐘，兩筆都要扣：1000−300−100=600',
    );
    expect(book.stateOf(bank)!.now, 600);
    expect(book.stateOf(cash)!.now, 300);
    final times = book.txs.map(book.calcAtOf).toSet();
    expect(times.length, 2, reason: '同一個時間點也分得出先後');
  });

  test('信用卡餘額附在交易上：刷卡後可用額度對不上＝漏記刷卡', () {
    LedgerTx swipe(String id, int day, int amount) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, day, 12),
      amount: amount,
      accountId: 'card',
      category: '餐飲',
    );
    LedgerCheckpoint avail(String txId, int day, int a) => LedgerCheckpoint(
      id: 'cp$txId',
      accountId: 'card',
      at: DateTime(2026, 11, day, 12),
      creditLimit: 100000,
      available: a,
      txId: txId,
    );
    final b = LedgerBook(
      accounts: const [card],
      txs: [swipe('a', 1, 100), swipe('b', 2, 100)],
      checkpoints: [avail('a', 1, 99900), avail('b', 2, 99300)],
      budgets: const [],
    );
    // 第二筆刷 100，可用額度卻少 600 → 漏記 500 的刷卡。
    expect(b.gapOfTx('b')!.miss, 500);
  });

  test('信用卡不用總額度：只填可用額度也能抓漏記；退款原路退回算進推算', () {
    LedgerTx swipe(String id, int day, int amount, {String acc = 'card'}) =>
        LedgerTx(
          id: id,
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, day, 12),
          amount: amount,
          accountId: acc,
          category: '購物',
        );
    LedgerCheckpoint avail(String txId, int day, int a) => LedgerCheckpoint(
      id: 'cp$txId',
      accountId: 'card',
      at: DateTime(2026, 11, day, 12),
      available: a, // 沒有 creditLimit
      txId: txId,
    );
    LedgerBook make(List<LedgerTx> txs, List<LedgerCheckpoint> cps) =>
        LedgerBook(
          accounts: const [
            LedgerAccount(
              id: 'card',
              name: '卡',
              type: LedgerAccountType.creditCard,
            ),
            bank,
          ],
          txs: txs,
          checkpoints: cps,
          budgets: const [],
        );
    final a = swipe('a', 1, 1000), b = swipe('b', 2, 200);
    // 刷 1000 後可用 50000；刷 200 後該是 49800。
    expect(
      make([a, b], [avail('a', 1, 50000), avail('b', 2, 49800)]).gapOfTx('b'),
      isNull,
    );
    // 中間有 1290 的刷卡被退款原路退回但沒記：可用額度多出來 → 缺負數＝多出 1290。
    final shop = swipe('shop', 1, 1290);
    var bk = make(
      [a, shop, b],
      [avail('a', 1, 50000), avail('b', 2, 49800 + 1290)],
    );
    // shop 時間在 a 同一天 12:00，同分鐘同帳戶同金額規則不影響這裡的推算。
    expect(bk.gapOfTx('b'), isNotNull);
    // 實際上沒有 shop 這筆，只是退款沒記：多出 1290，提示「是不是退款沒記」。
    bk = make([a, b], [avail('a', 1, 50000), avail('b', 2, 49800 + 1290)]);
    expect(bk.gapOfTx('b')!.miss, -1290);
    final refund = LedgerTx(
      id: 'r',
      type: LedgerTxType.refund,
      occurredAt: DateTime(2026, 11, 2, 11),
      amount: 1290,
      accountId: 'card',
      linkedId: 'shop',
    );
    // 有記退款：額度推算回來，標籤消失。
    bk = make(
      [a, shop.copyWith(occurredAt: DateTime(2026, 10, 30)), b, refund],
      [avail('a', 1, 50000), avail('b', 2, 49800 + 1290)],
    );
    expect(bk.gapOfTx('b'), isNull);
  });

  test('缺的數字剛好對得上某筆：時間記錯、記錯帳戶、退款沒記，各自提示', () {
    LedgerTx spend(String id, DateTime at, int amount, String acc) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: at,
      amount: amount,
      accountId: acc,
      category: '餐飲',
    );
    LedgerCheckpoint cp(String txId, int day, int bal) => LedgerCheckpoint(
      id: 'cp$txId',
      accountId: 'bank',
      at: DateTime(2026, 11, day, 12),
      balance: bal,
      txId: txId,
    );
    LedgerBook make(List<LedgerTx> txs, List<LedgerCheckpoint> cps) =>
        LedgerBook(
          accounts: const [bank, cash],
          txs: txs,
          checkpoints: cps,
          budgets: const [],
        );
    final a = spend('a', DateTime(2026, 11, 1, 12), 100, 'bank');
    final b = spend('b', DateTime(2026, 11, 3, 12), 100, 'bank');
    // 缺 500：同帳戶有一筆 500 但時間在 11/5（餘額之後）→ 時間可能記錯。
    var bk = make(
      [a, b, spend('late', DateTime(2026, 11, 5), 500, 'bank')],
      [cp('a', 1, 1000), cp('b', 3, 400)],
    );
    expect(
      bk.gapHints(bk.checkpointOfTx('b')!).single.kind,
      GapHintKind.wrongTime,
    );
    // 缺 500：中間有一筆 500 記在現金 → 記錯帳戶。
    bk = make(
      [a, b, spend('cash', DateTime(2026, 11, 2), 500, 'cash')],
      [cp('a', 1, 1000), cp('b', 3, 400)],
    );
    expect(
      bk.gapHints(bk.checkpointOfTx('b')!).single.kind,
      GapHintKind.wrongAccount,
    );
    // 多出 300：同帳戶有一筆 300 還沒退款 → 退款沒記。
    bk = make(
      [a, b, spend('x', DateTime(2026, 10, 1), 300, 'bank')],
      [cp('a', 1, 1000), cp('b', 3, 900 + 300)],
    );
    expect(
      bk.gapHints(bk.checkpointOfTx('b')!).single.kind,
      GapHintKind.refund,
    );
  });

  test('貼上匯入第 9 欄：這筆之後的餘額；跟誰留空也行', () {
    final lines = book([]).parseImport('''
中信銀行｜2026/11/04 12:00｜餐飲｜麥當勞｜189｜｜｜｜86000
現金｜2026/11/04 13:00｜餐飲｜便當｜120｜｜｜｜1880
中信銀行｜2026/11/04 14:00｜餐飲｜咖啡｜100
''');
    expect(lines[0].error, isNull);
    expect(lines[0].tx!.paidFor, isNull);
    expect(lines[0].after, 86000);
    expect(lines[1].after, 1880);
    expect(lines[2].after, isNull);
    // 第 10 欄備註、新分類「寵物」。
    final noted = book([]).parseImport('現金｜2026/11/05 15:00｜寵物｜飼料｜650｜｜｜｜｜補貨');
    expect(noted.single.error, isNull);
    expect(noted.single.tx!.category, '寵物');
    expect(noted.single.tx!.note, '補貨');
    // 備註最多 100 字，超過那一行擋下來。
    final ok100 = book(
      [],
    ).parseImport('現金｜2026/11/05 15:00｜寵物｜飼料｜650｜｜｜｜｜${'字' * 100}');
    expect(ok100.single.error, isNull);
    final long = book(
      [],
    ).parseImport('現金｜2026/11/05 15:00｜寵物｜飼料｜650｜｜｜｜｜${'字' * 101}');
    expect(long.single.error, contains('100'));
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

  test('拆分：1000 元家樂福拆成生活用品 500＋餐飲 500，就不算 1000 購物；退款、幫別人付照比例', () {
    final t = LedgerTx(
      id: 'carrefour',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 5, 12),
      amount: 1000,
      accountId: 'card',
      category: '生活', // 代表（金額最大的那份）
      merchant: '家樂福',
      splits: const [
        LedgerSplit(category: '生活', amount: 500),
        LedgerSplit(category: '餐飲', amount: 500),
      ],
    );
    var b = book([t]);
    var st = b.monthStats(2026, 11);
    expect(st.spend, 1000);
    expect(st.byCategory, {'生活': 500, '餐飲': 500});
    expect(st.byCategory.containsKey('購物'), isFalse);
    // 帳戶照整筆算。
    expect(b.stateOf(card)!.now, 12400 + 1000);
    // 分類篩選、搜尋兩個分類都找得到。
    expect(b.categoriesOf(t), ['生活', '餐飲']);
    expect(b.matches(t, '餐飲'), isTrue);
    // 退款 200：照拆分比例從兩個分類扣回（各 100）。
    final refund = LedgerTx(
      id: 'r',
      type: LedgerTxType.refund,
      occurredAt: DateTime(2026, 11, 6),
      amount: 200,
      accountId: 'card',
      linkedId: 'carrefour',
    );
    b = book([t, refund]);
    st = b.monthStats(2026, 11);
    expect(st.byCategory, {'生活': 400, '餐飲': 400});
    expect(st.spend, 800);
    // 幫別人付 400：自己那份 600，照比例（各 300）。
    b = book([
      t.copyWith(paidFor: () => const PaidFor(amount: 400, people: '小美')),
    ]);
    st = b.monthStats(2026, 11);
    expect(st.byCategory, {'生活': 300, '餐飲': 300});
    expect(st.spend, 600);
    // 加起來永遠剛好等於該付的（除不盡的差額補在最後一份）。
    final odd = LedgerTx(
      id: 'odd',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 7),
      amount: 100,
      accountId: 'card',
      category: '購物',
      splits: const [
        LedgerSplit(category: '購物', amount: 33),
        LedgerSplit(category: '生活', amount: 33),
        LedgerSplit(category: '餐飲', amount: 34),
      ],
    );
    final shares = book([]).categoryShares(odd, 77);
    expect(shares.values.fold(0, (a, c) => a + c), 77);
    // JSON 來回保留拆分；沒拆的不寫 splits。
    final back = LedgerTx.fromJson(t.toJson());
    expect(back.isSplit, isTrue);
    expect(back.splits.map((s) => s.amount), [500, 500]);
    expect(
      (t.copyWith(splits: const []).toJson()).containsKey('splits'),
      isFalse,
    );
  });

  test('當天相同金額只提醒不擋下：不看帳戶；同帳戶同分鐘同金額才擋', () {
    final cardSwipe = LedgerTx(
      id: 'a',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 5, 12, 0),
      amount: 300,
      accountId: 'card',
      category: '餐飲',
      merchant: '便當',
    );
    final b = book([cardSwipe]);
    // 另一個帳戶（現金）、同一天、不同時間、同金額：提醒，但不擋。
    final cash = DateTime(2026, 11, 5, 18, 30);
    expect(b.sameDayAmount(cash, 300).map((t) => t.id), ['a']);
    expect(b.sameMinute('cash', cash, 300), isNull, reason: '不擋下');
    // 不同天、不同金額、0 元都不提醒。
    expect(b.sameDayAmount(DateTime(2026, 11, 6), 300), isEmpty);
    expect(b.sameDayAmount(cash, 301), isEmpty);
    expect(b.sameDayAmount(cash, 0), isEmpty);
    // 同帳戶同一分鐘同金額＝原本的擋下規則照舊。
    expect(
      b.sameMinute('card', DateTime(2026, 11, 5, 12, 0, 40), 300),
      isNotNull,
    );
    // 匯入：現金那行不重複（照匯入），但標出當天有相同金額。
    final lines = b.parseImport('''
現金｜2026/11/05 18:30｜餐飲｜小吃｜300
現金｜2026/11/05 19:30｜餐飲｜飲料｜300
中信銀行｜2026/11/05 12:00｜餐飲｜便當｜300
''');
    expect(lines[0].duplicate, isFalse);
    expect(lines[0].sameDayOf, contains('便當'));
    expect(lines[1].duplicate, isFalse);
    expect(lines[1].sameDayOf, isNotNull);
    expect(lines[2].duplicate, isTrue, reason: '同帳戶同分鐘同金額擋下');
  });

  test('搜尋：每個欄位都搜、空白隔開多個詞都要符合、金額有沒有逗號都行', () {
    final t = LedgerTx(
      id: 's',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 5, 15, 30),
      amount: 1650,
      accountId: 'cash',
      category: '寵物',
      merchant: '寵物店',
      note: '貓罐頭 補貨',
      paidFor: const PaidFor(amount: 800, people: '小美'),
      flagged: true,
    );
    final b = book([t]);
    for (final q in [
      '寵物店', // 商家
      '貓罐頭', // 備註
      '寵物', // 分類
      '現金', // 帳戶
      '小美', // 跟誰
      '1650', '1,650', // 金額
      '11/5', '2026/11/05', '11月', // 日期
      '15:30', // 時間
      '支出', // 類型
      '要注意', // 旗
      '寵物 小美 15:30', // 多個詞都要找得到
      '',
    ]) {
      expect(b.matches(t, q), isTrue, reason: q);
    }
    for (final q in ['麥當勞', '寵物 麥當勞', '9999', '12/5']) {
      expect(b.matches(t, q), isFalse, reason: q);
    }
  });

  test('分類有寵物、菸酒；備註在 100 字內', () {
    expect(ledgerExpenseCats.keys, containsAll(['寵物', '菸酒', '創業魔物童話']));
    expect(ledgerNoteMax, 100);
  });

  test('匯入金額可以是 0（折扣、折抵）；空的或看不懂的才報錯', () {
    final lines = book([]).parseImport('''
中信銀行｜2026/11/05 15:00｜餐飲｜折抵後免費｜0｜｜｜｜｜折價券
中信銀行｜2026/11/05 16:00｜餐飲｜便當｜NT\$0
中信銀行｜2026/11/05 17:00｜餐飲｜便當｜
中信銀行｜2026/11/05 18:00｜餐飲｜便當｜abc
''');
    expect(lines[0].error, isNull);
    expect(lines[0].tx!.amount, 0);
    expect(lines[0].tx!.note, '折價券');
    expect(lines[1].tx!.amount, 0);
    expect(lines[2].error, isNotNull);
    expect(lines[3].error, isNotNull);
    final b = book([lines[0].tx!]);
    expect(b.monthStats(2026, 11).spend, 0);
  });

  test('匯入：商家名稱（第 4 欄）必填', () {
    final lines = book([]).parseImport('''
中信銀行｜2026/11/05 15:00｜餐飲｜｜100
中信銀行｜2026/11/05 16:00｜餐飲｜便當｜100
''');
    expect(lines[0].error, contains('商家'));
    expect(lines[1].error, isNull);
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

  test('總支出＝消費＋幫別人付（對方那份）＋還款＋轉給他人；消費只算自己', () {
    final at = DateTime(2026, 11, 5, 12);
    LedgerTx tx(
      LedgerTxType type,
      int amount, {
      String? cat,
      PaidFor? pf,
      bool toOther = false,
    }) => LedgerTx(
      id: ledgerId(),
      type: type,
      occurredAt: at,
      amount: amount,
      accountId: 'a',
      category: cat,
      paidFor: pf,
      toOther: toOther,
      toName: toOther ? '阿明' : '',
    );
    final book = LedgerBook(
      accounts: [
        const LedgerAccount(
          id: 'a',
          name: '中信帳戶',
          type: LedgerAccountType.bank,
          order: 1,
        ),
      ],
      txs: [
        tx(
          LedgerTxType.expense,
          1000,
          cat: '餐飲',
          pf: const PaidFor(amount: 400, people: 'Cen'),
        ),
        tx(LedgerTxType.expense, 8000, cat: '還款'),
        tx(LedgerTxType.transfer, 1200, toOther: true),
        tx(LedgerTxType.income, 50000, cat: '薪資'),
      ],
      checkpoints: const [],
      budgets: const [],
    );
    final st = book.statsWhere((_) => true);
    expect(st.spend, 600, reason: '消費只算自己那份，不含還款、轉給他人');
    expect(st.byCategory.containsKey('還款'), isFalse);
    expect(st.extra[ledgerPaidForOut], 400);
    expect(st.extra['還款'], 8000);
    expect(st.extra[ledgerToOtherCat], 1200);
    expect(st.out, 600 + 400 + 8000 + 1200);
    expect(st.income, 50000);
  });
}
