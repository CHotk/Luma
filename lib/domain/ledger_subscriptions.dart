import 'models/ledger.dart';

/// 每月訂閱的算法（2026-11-05 使用者：單純紀錄，記每月幾號扣多少錢）。

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

/// 仍在訂閱中的每月合計。
int subsMonthlyTotal(Iterable<LedgerSubscription> list) => list
    .where((s) => s.active && s.deletedAt == null)
    .fold(0, (sum, s) => sum + s.amount);

/// 排序：訂閱中的在前（照每月幾號、再照名稱），已停用的在後。
List<LedgerSubscription> sortSubs(Iterable<LedgerSubscription> list) =>
    list.where((s) => s.deletedAt == null).toList()..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.name.compareTo(b.name);
    });
