import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/debt_schedule.dart';
import 'package:lume/domain/models/debt.dart';

Debt debt({
  double principal = 100000,
  double rate = 5,
  int term = 24,
  bool flex = false,
  double flexPay = 0,
  int y = 2026,
  int m = 1,
  int due = 10,
  DateTime? payoffAt,
}) => Debt(
  id: 'd',
  name: '測試',
  lender: '銀行',
  type: DebtType.loan,
  principal: principal,
  rate: rate,
  term: term,
  firstYear: y,
  firstMonth: m,
  dueDay: due,
  flexible: flex,
  flexPay: flexPay,
  payoffAt: payoffAt,
  payoffAmount: payoffAt == null ? null : 1,
);

DebtPayment pay(int k, DateTime date, double amount) =>
    DebtPayment(id: '$k', debtId: 'd', period: k, date: date, amount: amount);

void main() {
  test('本息平均攤還：10 萬、5%、24 期月付 4,387，總利息 5,290', () {
    final d = debt();
    expect(monthlyPayment(d), 4387);
    final s = DebtStats.of(d, const [], today: DateTime(2026, 1, 1));
    expect(s.totalCount, 24);
    expect(s.interestTotal, closeTo(5290, 3));
    expect(s.rows.last.balance, 0);
    final principalSum = s.rows.fold(0.0, (a, r) => a + r.principal);
    expect(principalSum, closeTo(100000, 0.01));
  });

  test('0 利率分期：本金平分、無條件進位', () {
    final d = debt(principal: 36000, rate: 0, term: 12);
    expect(monthlyPayment(d), 3000);
    expect(DebtStats.of(d, const [], today: DateTime(2026)).interestTotal, 0);
  });

  test('扣款日在月底沒有那天就用月底', () {
    final d = debt(due: 31, m: 2);
    expect(dueDateOf(d, 1), DateTime(2026, 2, 28));
    expect(dueDateOf(d, 2), DateTime(2026, 3, 31));
    expect(dueDateOf(d, 12), DateTime(2027, 1, 31));
  });

  test('繳了幾期之後的剩餘本金、下一期、逾期天數', () {
    final d = debt();
    final rows = DebtStats.of(d, const []).rows;
    final s = DebtStats.of(d, [
      pay(1, DateTime(2026, 1, 10), rows[0].pay),
      pay(2, DateTime(2026, 2, 10), rows[1].pay),
    ], today: DateTime(2026, 3, 13));
    expect(s.paidCount, 2);
    expect(s.remaining, rows[1].balance);
    expect(s.next!.k, 3);
    expect(s.overdueDays, 3);
    expect(s.closed, isFalse);
  });

  test('繳滿就是還清；提前清償也是還清、剩 0', () {
    final d = debt(principal: 3000, rate: 0, term: 3);
    final rows = DebtStats.of(d, const []).rows;
    final all = [for (final r in rows) pay(r.k, r.date, r.pay)];
    expect(DebtStats.of(d, all).closed, isTrue);
    final po = DebtStats.of(debt(payoffAt: DateTime(2026, 5)), const []);
    expect(po.closed, isTrue);
    expect(po.remaining, 0);
    expect(po.next, isNull);
  });

  test('自由還款：有還就扣，剩下照每月推算', () {
    final d = debt(
      principal: 50000,
      rate: 0,
      term: 0,
      flex: true,
      flexPay: 5000,
    );
    final s = DebtStats.of(d, [
      DebtPayment(
        id: 'a',
        debtId: 'd',
        date: DateTime(2026, 1, 28),
        amount: 5000,
      ),
      DebtPayment(
        id: 'b',
        debtId: 'd',
        date: DateTime(2026, 2, 27),
        amount: 8000,
      ),
    ]);
    expect(s.remaining, 37000);
    expect(s.paidCount, 2);
    expect(s.totalCount, 2 + 8); // 37000 ÷ 5000 → 8 期
    expect(s.rows.last.pay, 2000);
  });

  test('提前還款試算：每月多還會早還清、省利息；0 利率省不到', () {
    final s = DebtStats.of(
      debt(principal: 300000, rate: 6.5, term: 60),
      const [],
    );
    final r = simulatePrepay(s, extra: 3000)!;
    expect(r.savedMonths, greaterThan(0));
    expect(r.savedInterest, greaterThan(0));
    final lump = simulatePrepay(s, lump: 300000)!;
    expect(lump.months, 0);
    final zero = DebtStats.of(
      debt(rate: 0, principal: 12000, term: 12),
      const [],
    );
    expect(simulatePrepay(zero, extra: 1000)!.savedInterest, 0);
  });

  test('某月應繳、全部加總、雪崩／雪球順序', () {
    final a = DebtStats.of(debt(), const [], today: DateTime(2026, 3, 1));
    final b = DebtStats.of(
      Debt.fromJson({
        ...debt(principal: 20000, rate: 0, term: 10, due: 20).toJson(),
        'id': 'e',
      }),
      const [],
      today: DateTime(2026, 3, 1),
    );
    final dues = duesOfMonth([a, b], DateTime(2026, 3));
    expect(dues.map((x) => x.row.date.day), [10, 20]);
    final t = DebtTotals([a, b], income: 10000, today: DateTime(2026, 3, 1));
    expect(t.monthly, 4387 + 2000);
    expect(t.incomeRatio, closeTo(63.87, 0.01));
    expect(avalancheOrder([a, b]).first, a);
    expect(snowballOrder([a, b]).first, b);
  });

  test('JSON 來回不掉資料', () {
    final d = debt(payoffAt: DateTime(2026, 5, 1));
    expect(Debt.fromJson(d.toJson()).toJson(), d.toJson());
    final p = pay(3, DateTime(2026, 3, 10), 4387);
    expect(DebtPayment.fromJson(p.toJson()).toJson(), p.toJson());
  });

  test('信用卡帳單：每月一期照帳單金額、沒有本金利息剩餘、不會還清', () {
    final card = Debt(
      id: 'c',
      name: '中信卡',
      lender: '中信',
      type: DebtType.card,
      principal: 0,
      rate: 0,
      term: 0,
      firstYear: 2026,
      firstMonth: 8,
      dueDay: 15,
      flexible: false,
      flexPay: 8000,
    );
    expect(card.isBill, isTrue);
    final today = DateTime(2026, 10, 20);
    final s = DebtStats.of(card, [
      DebtPayment(
        id: 'p',
        debtId: 'c',
        period: 1,
        date: DateTime(2026, 8, 15),
        amount: 7321,
      ),
    ], today: today);
    // 8、9、10 月，再多排到 11 月
    expect(s.rows.map((r) => r.date.month), [8, 9, 10, 11]);
    expect(s.rows.first.pay, 7321);
    expect(s.rows[1].pay, 8000);
    expect(s.remaining, 0);
    expect(s.closed, isFalse);
    expect(s.payoffDate, isNull);
    expect(s.interestTotal, 0);
    expect(s.next!.date, DateTime(2026, 9, 15));
    expect(s.overdueDays, 35);
    final t = DebtTotals([s], income: null, today: today);
    expect(t.monthly, 8000);
    expect(t.loans, isEmpty);
    expect(t.remaining, 0);
    expect(duesOfMonth([s], DateTime(2026, 10)).single.amount, 8000);
  });

  test('拿掉的舊種類讀進來變「其他」', () {
    final j = debt().toJson()..['type'] = 'family';
    expect(Debt.fromJson(j).type, DebtType.other);
  });

  test('開辦費算進總成本、不影響月付', () {
    final d = Debt.fromJson({...debt().toJson(), 'fee': 3000});
    final s = DebtStats.of(d, const []);
    expect(s.monthly, 4387);
    expect(s.totalCost, closeTo(s.interestTotal + 3000, 0.01));
    expect(Debt.fromJson(debt().toJson()).fee, 0);
  });
}
