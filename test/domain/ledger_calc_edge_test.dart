import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/ledger_log.dart';
import 'package:lume/domain/models/ledger.dart';

/// 記帳算法的邊界（2026-11-12 使用者：涵蓋率補到 95%、更多邊界）：同時間排序、
/// 沒記在 App 裡的戶頭（LineBank／虛擬貨幣）推算、匯率字串、對帳點選取、
/// 補記時間太擠、退款找不到原本那筆、匯入各種擋下來的情況。
void main() {
  final start = DateTime(2026, 10, 1);
  const bank = LedgerAccount(
    id: 'bank',
    name: '中信活存',
    type: LedgerAccountType.bank,
    order: 1,
  );
  const cash = LedgerAccount(
    id: 'cash',
    name: '現金',
    type: LedgerAccountType.cash,
    order: 2,
  );
  const card = LedgerAccount(
    id: 'card',
    name: '中信卡',
    type: LedgerAccountType.creditCard,
    creditLimit: 50000,
    order: 3,
  );
  final noon = DateTime(2026, 10, 5, 12);

  LedgerBook book(
    List<LedgerTx> txs, {
    List<LedgerAccount> accounts = const [bank, cash, card],
    List<LedgerCheckpoint>? cps,
  }) => LedgerBook(
    accounts: accounts,
    txs: txs,
    checkpoints:
        cps ??
        [
          LedgerCheckpoint(
            id: 'o1',
            accountId: 'bank',
            at: start,
            balance: 10000,
          ),
          LedgerCheckpoint(
            id: 'o2',
            accountId: 'cash',
            at: start,
            balance: 1000,
          ),
        ],
    budgets: const [],
  );

  LedgerTx tr(
    String id, {
    int amount = 3260,
    DateTime? at,
    DateTime? created,
    String account = 'bank',
    String toName = '',
    String fromName = '',
    double? toAfter,
    double? fromAfter,
    double? usdt,
    List<LedgerSplit> splits = const [],
    bool toOther = false,
  }) => LedgerTx(
    id: id,
    type: LedgerTxType.transfer,
    occurredAt: at ?? noon,
    createdAt: created,
    amount: amount,
    accountId: account,
    toName: toName,
    fromName: fromName,
    toAfter: toAfter,
    fromAfter: fromAfter,
    extAmount: usdt,
    splits: splits,
    toOther: toOther,
  );

  group('排序：同一時間', () {
    test('同時間：後建立的排前面；建立時間也一樣就看 id', () {
      final b = book([
        LedgerTx(
          id: 'a',
          type: LedgerTxType.expense,
          occurredAt: noon,
          createdAt: noon,
          amount: 10,
          accountId: 'cash',
          category: '餐飲',
        ),
        LedgerTx(
          id: 'b',
          type: LedgerTxType.expense,
          occurredAt: noon,
          createdAt: noon,
          amount: 20,
          accountId: 'cash',
          category: '餐飲',
        ),
        LedgerTx(
          id: 'c',
          type: LedgerTxType.expense,
          occurredAt: noon,
          createdAt: noon.add(const Duration(seconds: 5)),
          amount: 30,
          accountId: 'cash',
          category: '餐飲',
        ),
      ]);
      expect(b.txs.map((t) => t.id), ['c', 'b', 'a']);
    });
  });

  group('沒記在 App 裡的戶頭', () {
    test('同時間兩筆轉 LineBank：照建立先後算，第二筆有填餘額就從那裡重新算', () {
      final b = book([
        tr(
          'x2',
          amount: 500,
          toName: 'LineBank',
          created: noon.add(const Duration(seconds: 1)),
          toAfter: 9000,
        ),
        tr('x1', amount: 300, toName: 'LineBank', created: noon),
      ]);
      expect(b.extBalance('LineBank'), 9000);
      // 拿掉有填餘額的那筆（編輯它時）：只剩 300。
      expect(b.extBalance('LineBank', skipId: 'x2'), 300);
    });

    test('收入「平轉」從 LineBank 轉回來：LineBank 那邊減掉', () {
      final b = book([
        tr('in', amount: 1000, toName: 'LineBank', toAfter: 1000),
        LedgerTx(
          id: 'back',
          type: LedgerTxType.income,
          occurredAt: noon.add(const Duration(hours: 1)),
          amount: 400,
          accountId: 'bank',
          category: ledgerFlatTransfer,
          toName: 'LineBank',
        ),
      ]);
      expect(b.extBalance('LineBank'), 600);
    });

    test('轉進去其中一部分花掉了：只算轉進去的那部分；金額 0 不會除以 0（邊界）', () {
      final b = book([
        tr(
          'sp',
          amount: 1000,
          toName: 'LineBank',
          splits: const [LedgerSplit(category: '餐飲', amount: 250)],
        ),
        tr(
          'zero',
          amount: 0,
          toName: 'LineBank',
          at: noon.add(const Duration(hours: 1)),
        ),
      ]);
      expect(b.extBalance('LineBank'), 750);
    });

    test('有沒有填過餘額：從那邊轉出有填「這筆之後」也算；stopAt 之前沒有就是沒有', () {
      final b = book([
        tr('a', fromName: 'LineBank', fromAfter: 5000, account: '', at: noon),
        tr('b', toName: 'LineBank', at: noon.subtract(const Duration(days: 1))),
        LedgerTx(
          id: 'inc',
          type: LedgerTxType.income,
          occurredAt: noon.subtract(const Duration(days: 2)),
          amount: 100,
          accountId: 'bank',
          category: '薪資',
        ),
      ]);
      expect(b.extHasBalance('LineBank'), isTrue);
      expect(b.extHasBalance('LineBank', stopAt: 'a'), isFalse);
      expect(b.extHasBalance('LineBank', skipId: 'a'), isFalse);
      expect(b.extHasBalance('富邦'), isFalse);
    });

    test('虛擬貨幣差額：不是轉帳、沒填餘額、第一次填＝不比（null）；有基準才比', () {
      final first = tr('c1', toName: ledgerCryptoExt, usdt: 100, toAfter: 100);
      final second = tr(
        'c2',
        toName: ledgerCryptoExt,
        usdt: 100,
        toAfter: 205,
        at: noon.add(const Duration(days: 1)),
      );
      final out = tr(
        'c3',
        amount: 3260,
        fromName: ledgerCryptoExt,
        account: '',
        usdt: 100,
        fromAfter: 105,
        at: noon.add(const Duration(days: 2)),
      );
      final b = book([first, second, out]);
      expect(b.usdtDiffOf(first), isNull);
      expect(b.usdtDiffOf(second), closeTo(5, 0.001));
      // 轉出：205 − 100 = 105，剛好對上（差不到 0.005 當沒差）。
      expect(b.usdtDiffOf(out), isNull);
      expect(
        b.usdtDiffOf(
          LedgerTx(
            id: 'e',
            type: LedgerTxType.expense,
            occurredAt: noon,
            amount: 1,
            accountId: 'cash',
          ),
        ),
        isNull,
      );
      expect(b.usdtDiffOf(tr('no', toName: ledgerCryptoExt, usdt: 1)), isNull);
    });

    test('多少換多少：USDT 小數一位、兩位、整數；0 或沒填＝不顯示（邊界）', () {
      final b = book(const []);
      expect(
        b.fxLine(tr('a', amount: 3260, toName: ledgerCryptoExt, usdt: 100)),
        '\$3,260 → 100 USDT・1 USDT ≈ \$32.60',
      );
      expect(
        b.fxLine(tr('b', amount: 408, toName: ledgerCryptoExt, usdt: 12.5)),
        startsWith('\$408 → 12.5 USDT'),
      );
      expect(
        b.fxLine(tr('c', amount: 400, fromName: ledgerCryptoExt, usdt: 12.34)),
        startsWith('12.34 USDT → \$400'),
      );
      expect(b.fxLine(tr('d', toName: ledgerCryptoExt, usdt: 0)), isNull);
      expect(b.fxLine(tr('e', toName: ledgerCryptoExt)), isNull);
      // 有 USDT 但不是虛擬貨幣（例如 LineBank）＝不顯示。
      expect(b.fxLine(tr('f', toName: 'LineBank', usdt: 5)), isNull);
    });
  });

  group('對帳點', () {
    test('某時間點的值：被跳過的對帳點、在那之後的對帳點都不算；之前沒有對帳點＝null', () {
      final cps = [
        LedgerCheckpoint(
          id: 'o1',
          accountId: 'bank',
          at: start,
          balance: 10000,
        ),
        LedgerCheckpoint(
          id: 'late',
          accountId: 'bank',
          at: DateTime(2026, 10, 20),
          balance: 1,
        ),
        LedgerCheckpoint(
          id: 'mid',
          accountId: 'bank',
          at: DateTime(2026, 10, 3),
          balance: 8000,
        ),
      ];
      final b = book(const [], cps: cps);
      expect(b.valueAt(bank, DateTime(2026, 10, 10)), 8000);
      expect(b.valueAt(bank, DateTime(2026, 10, 10), skipCp: 'mid'), 10000);
      expect(b.valueAt(bank, DateTime(2026, 9, 1)), isNull);
    });

    test('一筆轉帳兩邊都附餘額：可以指定拿哪個帳戶的', () {
      final cps = [
        LedgerCheckpoint(
          id: 'o1',
          accountId: 'bank',
          at: start,
          balance: 10000,
        ),
        LedgerCheckpoint(id: 'o2', accountId: 'cash', at: start, balance: 1000),
        LedgerCheckpoint(
          id: 'p1',
          accountId: 'bank',
          at: noon,
          balance: 9000,
          txId: 't',
        ),
        LedgerCheckpoint(
          id: 'p2',
          accountId: 'cash',
          at: noon,
          balance: 2000,
          txId: 't',
        ),
      ];
      final b = book(const [], cps: cps);
      expect(b.checkpointOfTx('t', accountId: 'cash')!.id, 'p2');
      expect(b.checkpointOfTx('t')!.id, isNotNull);
      expect(b.checkpointOfTx('t', accountId: 'card'), isNull);
    });

    test('補記時間：前一個餘額只差不到一分鐘時，放兩個中間', () {
      final t0 = DateTime(2026, 10, 5, 12, 0, 0);
      final cps = [
        LedgerCheckpoint(id: 'a', accountId: 'bank', at: t0, balance: 1),
        LedgerCheckpoint(
          id: 'b',
          accountId: 'bank',
          at: t0.add(const Duration(seconds: 30)),
          balance: 2,
        ),
      ];
      final b = book(const [], cps: cps);
      expect(b.fixTimeFor(cps[1]), t0.add(const Duration(seconds: 15)));
      // 第一個餘額前面沒東西：前一分鐘。
      expect(b.fixTimeFor(cps[0]), t0.subtract(const Duration(minutes: 1)));
    });

    test('帳戶狀態：只有起點＝還沒對過帳', () {
      final b = book(const []);
      final s = b.stateOf(bank)!;
      expect(s.checked, isFalse);
      expect(s.isCard, isFalse);
      expect(s.limit, 0);
    });
  });

  group('統計', () {
    test('退款找不到原本那筆：扣在未分類；調整（減少）算未分類消費', () {
      final b = book([
        LedgerTx(
          id: 'r',
          type: LedgerTxType.refund,
          occurredAt: noon,
          amount: 200,
          accountId: 'bank',
          linkedId: '不存在',
        ),
        LedgerTx(
          id: 'adj',
          type: LedgerTxType.adjustment,
          occurredAt: noon,
          amount: 500,
          accountId: 'bank',
        ),
      ]);
      final s = b.statsWhere((_) => true);
      expect(s.byCategory[ledgerUncategorized], 300);
      expect(b.txs.firstWhere((t) => t.id == 'adj').ownSpend, 500);
      expect(b.categoriesOf(b.txs.firstWhere((t) => t.id == 'r')), isEmpty);
    });

    test('轉給他人有拆分：每份照分類算消費，不算「轉給他人」', () {
      final b = book([
        tr(
          'o',
          amount: 1000,
          toOther: true,
          toName: '小美',
          splits: const [
            LedgerSplit(category: '餐飲', amount: 600),
            LedgerSplit(category: '娛樂', amount: 400),
          ],
        ),
      ]);
      final s = b.statsWhere((_) => true);
      expect(s.byCategory['餐飲'], 600);
      expect(s.byCategory['娛樂'], 400);
      expect(s.extra[ledgerToOtherCat], isNull);
    });

    test('搜尋：平轉／轉給他人都搜得到', () {
      final flat = tr('f', toName: 'LineBank');
      final other = tr('o', toOther: true, toName: '小美');
      final b = book([flat, other]);
      expect(b.matches(flat, '平轉'), isTrue);
      expect(b.matches(other, '轉給他人'), isTrue);
      expect(b.matches(other, '平轉'), isFalse);
    });
  });

  group('匯入擋下來', () {
    test('日期時間看不懂', () {
      final l = book(const []).parseImport('中信｜明天中午｜餐飲｜麥當勞｜100');
      expect(l.single.error, '看不懂日期時間');
    });

    test('轉帳備註太長', () {
      final l = book(const []).parseImport(
        '中信活存｜2026/10/05 12:00｜轉帳｜小美｜100｜｜｜｜｜${'字' * (ledgerNoteMax + 1)}',
      );
      expect(l.single.error, contains('備註太長'));
    });

    test('沒有銀行帳戶：轉帳、收入都找不到帳戶', () {
      final b = book(
        const [],
        accounts: const [card],
        cps: [
          LedgerCheckpoint(
            id: 'c',
            accountId: 'card',
            at: start,
            creditLimit: 50000,
            available: 50000,
          ),
        ],
      );
      final l = b.parseImport('''
不存在｜2026/10/05 12:00｜轉帳｜小美｜100
不存在｜2026/10/05 12:00｜薪資｜公司｜100
''');
      expect(l[0].error, contains('找不到轉出的帳戶'));
      expect(l[1].error, contains('也沒有銀行帳戶'));
    });

    test('提款要先有銀行跟現金帳戶', () {
      final b = book(
        const [],
        accounts: const [bank],
        cps: [
          LedgerCheckpoint(id: 'o1', accountId: 'bank', at: start, balance: 1),
        ],
      );
      final l = b.parseImport('中信活存｜2026/10/05 12:00｜提款｜ATM｜1000');
      expect(l.single.error, '要先有銀行跟現金帳戶');
    });
  });

  group('紀錄差異', () {
    test('從哪個戶頭改了：寫從哪裡改成哪裡；空的寫「無」', () {
      final a = tr('x', toName: 'LineBank');
      final b = a.copyWith(fromName: '富邦');
      final d = logDiffTx(a, b, (id) => id ?? '');
      expect(d.any((s) => s.contains('從（沒記帳的戶頭）：無 → 富邦')), isTrue);
    });

    test('對帳點同步時間：沒改過＝當時的時間', () {
      final c = LedgerCheckpoint(
        id: 'c',
        accountId: 'bank',
        at: start,
        balance: 1,
      );
      expect(c.syncedAt, start);
    });
  });
}
