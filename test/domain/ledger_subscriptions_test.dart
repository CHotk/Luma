import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/ledger_subscriptions.dart';
import 'package:lume/domain/models/ledger.dart';

LedgerSubscription sub(
  String name,
  int amount,
  int day, {
  bool active = true,
  DateTime? deletedAt,
}) => LedgerSubscription(
  id: name,
  name: name,
  amount: amount,
  day: day,
  active: active,
  deletedAt: deletedAt,
);

/// 每月訂閱（單純紀錄用）：扣款日遇到沒有那天的月份算月底、下一次扣款日、每月合計。
void main() {
  debtTests();
  test('31 號碰到短月份算那個月最後一天（含閏年）', () {
    expect(subChargeDate(2026, 2, 31), DateTime(2026, 2, 28));
    expect(subChargeDate(2028, 2, 31), DateTime(2028, 2, 29));
    expect(subChargeDate(2026, 4, 31), DateTime(2026, 4, 30));
    expect(subChargeDate(2026, 5, 31), DateTime(2026, 5, 31));
    expect(subChargeDate(2026, 11, 12), DateTime(2026, 11, 12));
  });

  test('下一次扣款日：今天還沒過就是今天，過了就是下個月，跨年也對', () {
    final s = sub('Netflix', 390, 12);
    expect(nextSubCharge(s, DateTime(2026, 11, 5, 23)), DateTime(2026, 11, 12));
    expect(daysUntilSubCharge(s, DateTime(2026, 11, 5, 23)), 7);
    // 當天扣＝今天。
    expect(nextSubCharge(s, DateTime(2026, 11, 12, 8)), DateTime(2026, 11, 12));
    expect(daysUntilSubCharge(s, DateTime(2026, 11, 12, 8)), 0);
    // 過了就是下個月。
    expect(nextSubCharge(s, DateTime(2026, 11, 13)), DateTime(2026, 12, 12));
    // 12 月過了 → 隔年 1 月。
    expect(nextSubCharge(s, DateTime(2026, 12, 20)), DateTime(2027, 1, 12));
    // 31 號：1/31 之後下一次是 2/28。
    final e = sub('iCloud', 30, 31);
    expect(nextSubCharge(e, DateTime(2027, 1, 31)), DateTime(2027, 1, 31));
    expect(nextSubCharge(e, DateTime(2027, 2, 1)), DateTime(2027, 2, 28));
  });

  test('每月合計只算訂閱中、沒刪掉的', () {
    final list = [
      sub('A', 390, 12),
      sub('B', 100, 1),
      sub('C', 500, 5, active: false),
      sub('D', 70, 9, deletedAt: DateTime(2026, 11, 1)),
    ];
    expect(subsMonthlyTotal(list), 490);
    expect(subsMonthlyTotal(const []), 0);
  });

  test('排序：訂閱中的在前、照扣款日；已停用的在後；刪掉的不出現', () {
    final list = sortSubs([
      sub('C', 500, 5, active: false),
      sub('A', 390, 12),
      sub('D', 70, 9, deletedAt: DateTime(2026, 11, 1)),
      sub('B', 100, 1),
    ]);
    expect(list.map((s) => s.name), ['B', 'A', 'C']);
  });

  test('存取格式往返不變；舊資料缺欄位也讀得進來', () {
    final s = LedgerSubscription(
      id: 'x',
      name: 'Spotify',
      amount: 149,
      day: 3,
      note: '家庭方案',
      active: false,
      createdAt: DateTime(2026, 11, 5, 9),
      updatedAt: DateTime(2026, 11, 5, 10),
    );
    final back = LedgerSubscription.fromJson(s.toJson());
    expect(back.name, 'Spotify');
    expect(back.amount, 149);
    expect(back.day, 3);
    expect(back.note, '家庭方案');
    expect(back.active, isFalse);
    final minimal = LedgerSubscription.fromJson({'id': 'y', 'day': 99});
    expect(minimal.day, 31);
    expect(minimal.active, isTrue);
    expect(minimal.amount, 0);
  });
}

/// 借款的期數、貸款總額（2026-11-06 使用者）。
void debtTests() {
  LedgerSubscription debt({
    int amount = 1000,
    int day = 10,
    int? periods = 12,
    int? loan = 11000,
    String? start = '2026-09',
    bool active = true,
  }) => LedgerSubscription(
    id: 'd',
    name: '手機分期',
    amount: amount,
    day: day,
    kind: LedgerChargeKind.debt,
    periods: periods,
    loanTotal: loan,
    startMonth: start,
    active: active,
  );

  group('借款期數', () {
    test('已繳幾期：第一期那個月起，每個月扣款日到了就算一期', () {
      final d = debt(); // 2026-09 起，每月 10 號，共 12 期
      expect(paidPeriods(d, DateTime(2026, 8, 20)), 0); // 還沒開始
      expect(paidPeriods(d, DateTime(2026, 9, 9)), 0); // 9/10 還沒到
      expect(paidPeriods(d, DateTime(2026, 9, 10)), 1); // 當天算
      expect(paidPeriods(d, DateTime(2026, 11, 5)), 2); // 9、10 月已扣，11/10 還沒
      expect(paidPeriods(d, DateTime(2026, 11, 10)), 3);
      expect(remainingPeriods(d, DateTime(2026, 11, 5)), 10);
      expect(remainingAmount(d, DateTime(2026, 11, 5)), 10000);
    });

    test('沒填第一期或總期數就算不出來；訂閱沒有期數', () {
      expect(paidPeriods(debt(start: null), DateTime(2026, 11, 5)), isNull);
      expect(paidPeriods(debt(periods: null), DateTime(2026, 11, 5)), isNull);
      expect(remainingAmount(debt(start: null), DateTime(2026, 11, 5)), isNull);
      final sub = LedgerSubscription(
        id: 's',
        name: 'Netflix',
        amount: 390,
        day: 1,
        periods: 12,
        startMonth: '2026-01',
      );
      expect(paidPeriods(sub, DateTime(2026, 11, 5)), isNull);
    });

    test('期數扣完＝已繳清：不再算進每月合計，也不再是扣款中', () {
      final d = debt(periods: 3); // 9、10、11 月
      expect(isFinished(d, DateTime(2026, 11, 9)), isFalse);
      expect(isCharging(d, DateTime(2026, 11, 9)), isTrue);
      expect(subsMonthlyTotal([d], now: DateTime(2026, 11, 9)), 1000);
      expect(paidPeriods(d, DateTime(2027, 5, 1)), 3); // 不會超過總期數
      expect(isFinished(d, DateTime(2026, 11, 10)), isTrue);
      expect(isCharging(d, DateTime(2026, 11, 10)), isFalse);
      expect(subsMonthlyTotal([d], now: DateTime(2026, 11, 10)), 0);
      // 排序：已繳清的排到後面。
      final other = LedgerSubscription(
        id: 'o',
        name: 'iCloud',
        amount: 30,
        day: 28,
      );
      expect(
        sortSubs([d, other], now: DateTime(2026, 11, 12)).map((s) => s.id),
        ['o', 'd'],
      );
    });

    test('本利總額 = 期數 × 每月；比貸款總額多的是純利息', () {
      expect(totalPayable(debt()), 12000);
      expect(pureInterest(debt()), 1000); // 12000 − 11000
      expect(pureInterest(debt(loan: 12000)), 0); // 一樣多＝零利率
      expect(pureInterest(debt(loan: null)), isNull);
      expect(pureInterest(debt(loan: 13000)), isNull); // 繳的比借的少＝數字有誤
      expect(totalPayable(debt(periods: null)), isNull);
    });

    test('實際年利率：本息平均攤還反推，跟銀行算法一樣', () {
      // 借 10 萬、年利率 8%、12 期：銀行算每月 8,699。
      expect(loanAnnualRate(100000, 8699, 12), closeTo(8.0, 0.05));
      // 借 100 萬、年利率 3%、84 期：每月約 13,213。
      expect(loanAnnualRate(1000000, 13213, 84), closeTo(3.0, 0.02));
      expect(loanAnnualRate(12000, 1000, 12), 0); // 沒利息
      expect(loanAnnualRate(13000, 1000, 12), isNull); // 繳的比借的少
      expect(loanAnnualRate(0, 1000, 12), isNull);
      expect(annualRateOf(debt(loan: null)), isNull);
      expect(annualRateOf(debt(periods: null)), isNull);
    });

    test('信用卡沒有第一期：算不出已繳幾期、不會變已繳清；信貸跟小額借款一樣算', () {
      final at = DateTime(2027, 12, 1);
      final card = debt(
        periods: 3,
      ).copyWith(debtType: LedgerDebtType.creditCard);
      expect(paidPeriods(card, at), isNull);
      expect(isFinished(card, at), isFalse);
      final loan = debt().copyWith(debtType: LedgerDebtType.personalLoan);
      expect(paidPeriods(loan, DateTime(2026, 11, 5)), 2);
    });

    test('合計可以分訂閱／借款算', () {
      final list = [
        debt(),
        LedgerSubscription(id: 's', name: 'Netflix', amount: 390, day: 12),
      ];
      final at = DateTime(2026, 11, 5);
      expect(subsMonthlyTotal(list, now: at), 1390);
      expect(
        subsMonthlyTotal(list, kind: LedgerChargeKind.debt, now: at),
        1000,
      );
      expect(
        subsMonthlyTotal(list, kind: LedgerChargeKind.subscription, now: at),
        390,
      );
    });

    test('存取往返不變；訂閱不帶這些欄位', () {
      final back = LedgerSubscription.fromJson(debt().toJson());
      expect(back.kind, LedgerChargeKind.debt);
      expect(back.debtType, LedgerDebtType.smallLoan);
      // 舊資料沒有 debtType：算小額借款；三種都存得回來。
      expect(LedgerDebtType.parse(null), LedgerDebtType.smallLoan);
      for (final t in LedgerDebtType.values) {
        final x = debt().copyWith(debtType: t);
        expect(LedgerSubscription.fromJson(x.toJson()).debtType, t);
      }
      expect(back.periods, 12);
      expect(back.loanTotal, 11000);
      expect(back.startMonth, '2026-09');
      final json = LedgerSubscription(
        id: 's',
        name: 'x',
        amount: 1,
        day: 1,
      ).toJson();
      expect(json.containsKey('periods'), isFalse);
      expect(json.containsKey('loanTotal'), isFalse);
    });
  });
}
