import 'dart:math' as math;

import 'models/debt.dart';

/// 負債每月還款表的計算（純函式，畫面跟測試共用）。
///
/// 固定期數用「本息平均攤還」：月付 M＝P·r ÷ (1 − (1+r)^−n)，r＝年利率 ÷ 12，
/// 四捨五入到元；每期利息＝剩餘本金 × r（四捨五入），本金＝M − 利息，最後
/// 一期把剩下的本金一次補齊。0 利率（信用卡分期）就是本金平分、無條件
/// 進位。

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// 第 [k] 期（從 1 起）的扣款日；那個月沒有扣款日那天（例如 31 號）就用月底。
DateTime dueDateOf(Debt d, int k) {
  final t = d.firstYear * 12 + (d.firstMonth - 1) + k - 1;
  final y = t ~/ 12, m = t % 12 + 1;
  final dim = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(d.dueDay, dim));
}

/// 每月要繳多少（自由還款是預計每月還的；信用卡是本期帳單大概金額）。
double monthlyPayment(Debt d) {
  if (d.flexible || d.isBill) return d.flexPay;
  if (d.term <= 0) return 0;
  final r = d.rate / 1200;
  if (r == 0) return (d.principal / d.term).ceilToDouble();
  return (d.principal * r / (1 - math.pow(1 + r, -d.term))).roundToDouble();
}

/// 攤還表的一期。
class DebtRow {
  const DebtRow({
    required this.k,
    required this.date,
    required this.pay,
    required this.principal,
    required this.interest,
    required this.balance,
    this.payment,
  });

  final int k;

  /// 應繳日（已繳的自由還款是實際繳款日）。
  final DateTime date;
  final double pay;
  final double principal;
  final double interest;

  /// 繳完這期剩下的本金。
  final double balance;

  /// 這期的繳款紀錄，沒繳是 null。
  final DebtPayment? payment;

  bool get isPaid => payment != null;
}

/// 這筆債的攤還表。[payments] 是這筆債的繳款（不用排序）。提前清償過的
/// 只留已繳的那幾期。
List<DebtRow> scheduleOf(
  Debt d,
  Iterable<DebtPayment> payments, {
  DateTime? today,
}) {
  final m = monthlyPayment(d);
  final rows = <DebtRow>[];
  if (d.isBill) return _billRows(d, payments, today ?? DateTime.now());
  var b = d.principal;
  if (d.flexible) {
    final pays = [...payments]..sort((a, b) => a.date.compareTo(b.date));
    var k = 0;
    for (final p in pays) {
      k++;
      b -= p.amount;
      rows.add(
        DebtRow(
          k: k,
          date: p.date,
          pay: p.amount,
          principal: p.amount,
          interest: 0,
          balance: math.max(0, b),
          payment: p,
        ),
      );
    }
    if (d.payoffAt != null || m <= 0) return rows;
    final last = k;
    while (b > 0.5 && k < last + 600) {
      k++;
      final p = math.min(m, b);
      b -= p;
      rows.add(
        DebtRow(
          k: k,
          date: dueDateOf(d, k),
          pay: p,
          principal: p,
          interest: 0,
          balance: b,
        ),
      );
    }
    return rows;
  }
  final byK = {
    for (final p in payments)
      if (p.period != null) p.period!: p,
  };
  final r = d.rate / 1200;
  for (var k = 1; k <= d.term; k++) {
    final i = (b * r).roundToDouble();
    var p = m - i;
    if (k == d.term || p > b) p = b;
    b -= p;
    rows.add(
      DebtRow(
        k: k,
        date: dueDateOf(d, k),
        pay: p + i,
        principal: p,
        interest: i,
        balance: math.max(0, b),
        payment: byK[k],
      ),
    );
  }
  return d.payoffAt != null ? rows.where((r) => r.isPaid).toList() : rows;
}

/// 信用卡帳單：從第一期每月一期，排到這個月再多一期（下個月），已繳的
/// 照實繳金額，沒繳的照本期帳單大概金額。沒有本金、利息、剩餘。
List<DebtRow> _billRows(
  Debt d,
  Iterable<DebtPayment> payments,
  DateTime today,
) {
  final byK = {
    for (final p in payments)
      if (p.period != null) p.period!: p,
  };
  final first = d.firstYear * 12 + d.firstMonth - 1;
  final nowIdx = today.year * 12 + today.month - 1;
  var last = math.max(1, nowIdx - first + 2);
  if (byK.isNotEmpty) last = math.max(last, byK.keys.reduce(math.max) + 1);
  return [
    for (var k = 1; k <= last; k++)
      DebtRow(
        k: k,
        date: dueDateOf(d, k),
        pay: byK[k]?.amount ?? d.flexPay,
        principal: 0,
        interest: 0,
        balance: 0,
        payment: byK[k],
      ),
  ];
}

/// 一筆債的狀況。
class DebtStats {
  DebtStats._(this.debt, this.rows, this.today);

  factory DebtStats.of(
    Debt d,
    Iterable<DebtPayment> payments, {
    DateTime? today,
  }) => DebtStats._(
    d,
    scheduleOf(d, payments, today: today),
    today ?? DateTime.now(),
  );

  final Debt debt;
  final List<DebtRow> rows;
  final DateTime today;

  late final List<DebtRow> paid = rows.where((r) => r.isPaid).toList();

  /// 下一期要繳的，還清了是 null。
  late final DebtRow? next = closed
      ? null
      : rows.where((r) => !r.isPaid).firstOrNull;

  double get monthly => monthlyPayment(debt);

  late final double remaining = debt.payoffAt != null || debt.isBill
      ? 0
      : paid.isEmpty
      ? debt.principal
      : paid.last.balance;

  /// 還清了：提前清償過、固定期數繳滿、或自由還款還完。
  bool get closed =>
      debt.payoffAt != null ||
      (!debt.isBill &&
          !debt.flexible &&
          rows.isNotEmpty &&
          rows.every((r) => r.isPaid)) ||
      (debt.flexible &&
          rows.isNotEmpty &&
          rows.last.isPaid &&
          rows.last.balance <= 0.5);

  int get paidCount => paid.length;
  int get totalCount => rows.length;

  double get interestPaid => paid.fold(0.0, (s, r) => s + r.interest);
  double get interestLeft => closed
      ? 0
      : rows.where((r) => !r.isPaid).fold(0.0, (s, r) => s + r.interest);
  double get interestTotal => interestPaid + interestLeft;

  /// 預計（或實際）還清的日子。
  DateTime? get payoffDate => debt.isBill
      ? null
      : debt.payoffAt ?? (rows.isEmpty ? null : rows.last.date);

  /// 已還本金比例（0–100）。信用卡帳單沒有本金，固定 0。
  double get percent => debt.isBill
      ? 0
      : debt.principal <= 0
      ? 100
      : ((debt.principal - remaining) / debt.principal * 100).clamp(0, 100);

  /// 下一期過了扣款日還沒繳，逾期幾天；沒逾期是 0。
  int get overdueDays {
    final n = next;
    if (n == null) return 0;
    final d = _day(today).difference(_day(n.date)).inDays;
    return d > 0 ? d : 0;
  }
}

/// 某個月要繳的一期（已繳或未繳）。
class DueItem {
  const DueItem(this.stats, this.row, {this.isPayoff = false});

  final DebtStats stats;
  final DebtRow row;

  /// 這是那個月的提前清償，不是一般的一期。
  final bool isPayoff;

  Debt get debt => stats.debt;
  bool get isPaid => isPayoff || row.isPaid;

  /// 實繳（已繳）或應繳金額。
  double get amount => row.payment?.amount ?? row.pay;

  bool isOverdue(DateTime today) =>
      !isPaid && _day(row.date).isBefore(_day(today));
}

/// [month] 那個月每筆債落在那個月的那一期，依日期排。
List<DueItem> duesOfMonth(Iterable<DebtStats> all, DateTime month) {
  final out = <DueItem>[];
  for (final s in all) {
    for (final r in s.rows) {
      if (r.date.year == month.year && r.date.month == month.month) {
        out.add(DueItem(s, r));
      }
    }
    final po = s.debt.payoffAt;
    if (po != null && po.year == month.year && po.month == month.month) {
      out.add(
        DueItem(
          s,
          DebtRow(
            k: 0,
            date: po,
            pay: s.debt.payoffAmount ?? 0,
            principal: s.debt.payoffAmount ?? 0,
            interest: 0,
            balance: 0,
          ),
          isPayoff: true,
        ),
      );
    }
  }
  return out..sort((a, b) => a.row.date.compareTo(b.row.date));
}

/// 提前還款試算的結果。
class PrepayResult {
  const PrepayResult({
    required this.months,
    required this.interest,
    required this.savedInterest,
    required this.savedMonths,
    required this.payoff,
  });

  final int months;
  final double interest;
  final double savedInterest;
  final int savedMonths;
  final DateTime payoff;
}

/// 每月多還 [extra]、現在一次多還 [lump]，多久還清、利息多少、省多少。
/// 多還的錢付不了利息（月付＋多還 ≤ 利息）時回傳 null。
PrepayResult? simulatePrepay(DebtStats s, {double extra = 0, double lump = 0}) {
  if (s.closed) return null;
  final r = s.debt.rate / 1200;
  var b = s.remaining - lump;
  final first = s.next?.date ?? s.today;
  final baseMonths = s.totalCount - s.paidCount;
  if (b <= 0) {
    return PrepayResult(
      months: 0,
      interest: 0,
      savedInterest: s.interestLeft,
      savedMonths: baseMonths,
      payoff: s.today,
    );
  }
  var n = 0;
  var interest = 0.0;
  while (b > 0.5 && n < 1200) {
    final i = (b * r).roundToDouble();
    final p = s.monthly + extra - i;
    if (p <= 0) return null;
    interest += i;
    b -= math.min(p, b);
    n++;
  }
  return PrepayResult(
    months: n,
    interest: interest,
    savedInterest: math.max(0, s.interestLeft - interest),
    savedMonths: math.max(0, baseMonths - n),
    payoff: DateTime(first.year, first.month + n - 1, first.day),
  );
}

/// 全部負債加起來的狀況。
class DebtTotals {
  DebtTotals(this.all, {required this.income, DateTime? today})
    : today = today ?? DateTime.now();

  final List<DebtStats> all;
  final double? income;
  final DateTime today;

  late final List<DebtStats> active = all.where((s) => !s.closed).toList();

  /// 還在攤還的（不含信用卡帳單），算剩餘、還清日、先還哪一筆用。
  late final List<DebtStats> loans = active
      .where((s) => !s.debt.isBill)
      .toList();

  double get remaining => active.fold(0.0, (s, x) => s + x.remaining);
  double get principal => all
      .where((x) => !x.debt.isBill)
      .fold(0.0, (s, x) => s + x.debt.principal);
  double get paidPercent =>
      principal <= 0 ? 100 : (principal - remaining) / principal * 100;

  /// 每月固定要繳（還沒還清的）。
  double get monthly => active.fold(0.0, (s, x) => s + x.monthly);
  double get interestLeft => active.fold(0.0, (s, x) => s + x.interestLeft);
  double get interestPaid => all.fold(0.0, (s, x) => s + x.interestPaid);

  /// 全部還清的日子。
  DateTime? get freeDate => active.fold<DateTime?>(
    null,
    (a, x) =>
        a == null || (x.payoffDate?.isAfter(a) ?? false) ? x.payoffDate : a,
  );

  int get monthsLeft {
    final f = freeDate;
    if (f == null) return 0;
    return math.max(0, (f.year - today.year) * 12 + f.month - today.month);
  }

  int get overdueCount => active.where((s) => s.overdueDays > 0).length;

  /// 每月還款佔收入（%），沒填收入是 null。
  double? get incomeRatio =>
      income == null || income! <= 0 ? null : monthly / income! * 100;

  late final List<DueItem> thisMonth = duesOfMonth(all, today);
  double get dueThisMonth =>
      thisMonth.where((x) => !x.isPayoff).fold(0.0, (s, x) => s + x.amount);
  double get paidThisMonth => thisMonth
      .where((x) => x.isPaid && !x.isPayoff)
      .fold(0.0, (s, x) => s + x.amount);
}

/// 「多的錢先還哪一筆」的兩種順序：雪崩法（利率高先還，最省利息）、
/// 雪球法（剩最少的先還，最快少一筆帳）。0 利率的排在雪崩法最後。
List<DebtStats> avalancheOrder(Iterable<DebtStats> active) =>
    [...active]..sort((a, b) {
      final c = b.debt.rate.compareTo(a.debt.rate);
      return c != 0 ? c : a.remaining.compareTo(b.remaining);
    });

List<DebtStats> snowballOrder(Iterable<DebtStats> active) =>
    [...active]..sort((a, b) => a.remaining.compareTo(b.remaining));
