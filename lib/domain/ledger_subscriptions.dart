import 'models/ledger.dart';

/// 每月扣款的算法（2026-11-05 使用者：單純紀錄，記每月幾號扣多少錢；2026-11-06 加上
/// 借款的期數跟貸款總額）。跟實際記帳完全沒有關連，只是釐清每月該繳多少。

/// 某年某月的最後一天是幾號。
int lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// [day] 號在某年某月實際扣款的日期：沒有那天（31 號碰到 2 月）就是月底。
DateTime subChargeDate(int year, int month, int day) {
  final last = lastDayOfMonth(year, month);
  return DateTime(year, month, day > last ? last : day);
}

/// 下一次扣款日：今天（含）之後最近的那一天。
DateTime nextSubCharge(LedgerSubscription s, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisMonth = subChargeDate(now.year, now.month, s.day);
  if (!thisMonth.isBefore(today)) return thisMonth;
  return subChargeDate(now.year, now.month + 1, s.day);
}

/// 距離下次扣款還有幾天（今天扣＝0）。
int daysUntilSubCharge(LedgerSubscription s, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return nextSubCharge(s, now).difference(today).inDays;
}

/// `yyyy-MM` 的格式（第一期扣款月份存檔用）。
String monthKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// 借款已經扣了幾期：從第一期那個月起，每個月的扣款日只要到了（含今天）就算一期，
/// 最多到總期數。沒填第一期月份或總期數就算不出來（null）；信用卡沒有第一期，一律 null。
int? paidPeriods(LedgerSubscription s, DateTime now) {
  final periods = s.periods;
  final start = s.startMonth;
  if (s.kind != LedgerChargeKind.debt ||
      s.debtType == LedgerDebtType.creditCard ||
      periods == null ||
      start == null) {
    return null;
  }
  final parts = start.split('-');
  if (parts.length != 2) return null;
  final sy = int.tryParse(parts[0]), sm = int.tryParse(parts[1]);
  if (sy == null || sm == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final k = (now.year - sy) * 12 + (now.month - sm);
  if (k < 0) return 0;
  final thisMonthPaid = !subChargeDate(
    now.year,
    now.month,
    s.day,
  ).isAfter(today);
  final paid = k + (thisMonthPaid ? 1 : 0);
  return paid > periods ? periods : paid;
}

/// 還剩幾期（算不出來是 null）。
int? remainingPeriods(LedgerSubscription s, DateTime now) {
  final paid = paidPeriods(s, now);
  return paid == null ? null : s.periods! - paid;
}

/// 還剩多少沒繳（還剩幾期 × 每月扣款，算不出來是 null）。
int? remainingAmount(LedgerSubscription s, DateTime now) {
  final left = remainingPeriods(s, now);
  return left == null ? null : left * s.amount;
}

/// 實際本利總額：總共要繳多少（總期數 × 每月扣款；沒填期數是 null）。
int? totalPayable(LedgerSubscription s) =>
    s.kind == LedgerChargeKind.debt && s.periods != null
    ? s.periods! * s.amount
    : null;

/// 純利息：本利總額 − 貸款總額（含手續費之類）。沒填貸款總額或期數、或本利總額比貸款總額
/// 還少（數字填錯）是 null。
int? pureInterest(LedgerSubscription s) {
  final total = totalPayable(s), loan = s.loanTotal;
  if (total == null || loan == null || loan <= 0) return null;
  return total >= loan ? total - loan : null;
}

/// 實際年利率（%）：用本息平均攤還反推，跟銀行信貸講的年利率同一種算法（月利率 × 12），
/// 可以直接拿來比。借 [principal]、每月繳 [payment]、繳 [periods] 期。
/// 繳的總額比借的還少（數字不合理）是 null；剛好一樣是 0。
double? loanAnnualRate(int principal, int payment, int periods) {
  if (principal <= 0 || payment <= 0 || periods <= 0) return null;
  final total = payment * periods;
  if (total < principal) return null;
  if (total == principal) return 0;
  // 這個月利率下，每月繳 payment 相當於借多少（現值）；月利率越高現值越小，用二分法找。
  double present(double r) {
    var factor = 1.0, sum = 0.0;
    for (var i = 0; i < periods; i++) {
      factor /= 1 + r;
      sum += factor;
    }
    return payment * sum;
  }

  var low = 0.0, high = 1.0;
  for (var i = 0; i < 80; i++) {
    final mid = (low + high) / 2;
    if (present(mid) > principal) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2 * 12 * 100;
}

/// 這筆借款的實際年利率（沒填貸款總額或期數是 null）。
double? annualRateOf(LedgerSubscription s) {
  final loan = s.loanTotal, n = s.periods;
  if (s.kind != LedgerChargeKind.debt || loan == null || n == null) {
    return null;
  }
  return loanAnnualRate(loan, s.amount, n);
}

/// 借款的期數都扣完了（已繳清）。
bool isFinished(LedgerSubscription s, DateTime now) {
  final left = remainingPeriods(s, now);
  return left != null && left <= 0;
}

/// 現在還在扣款：開關開著、沒刪掉、借款的期數也還沒扣完。
bool isCharging(LedgerSubscription s, DateTime now) =>
    s.active && s.deletedAt == null && !isFinished(s, now);

/// 仍在扣款中的每月合計；給 [kind] 就只算那一種（訂閱或借款）。
/// 借款期數都扣完（已繳清）的不算。
int subsMonthlyTotal(
  Iterable<LedgerSubscription> list, {
  LedgerChargeKind? kind,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return list
      .where((s) => isCharging(s, at) && (kind == null || s.kind == kind))
      .fold(0, (sum, s) => sum + s.amount);
}

/// 排序：扣款中的在前（照每月幾號、再照名稱），已停用或已繳清的在後。
List<LedgerSubscription> sortSubs(
  Iterable<LedgerSubscription> list, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return list.where((s) => s.deletedAt == null).toList()..sort((a, b) {
    final ca = isCharging(a, at), cb = isCharging(b, at);
    if (ca != cb) return ca ? -1 : 1;
    final d = a.day.compareTo(b.day);
    return d != 0 ? d : a.name.compareTo(b.name);
  });
}
