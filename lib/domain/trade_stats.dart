import 'crypto_watch_stats.dart' show dayOf;
import 'models/trade_entry.dart';

/// 交易&自律的統計（純函式，給主畫面月曆、日誌、月報跟測試用）。
///
/// 損益一律算在**平倉那天**；持倉中的單不算進任何損益數字。

/// 一天看盤超過這個次數就算「看太多」：月曆的 👁 變黃、月報分成
/// 「看盤少的日子 vs 看盤多的日子」比較（2026-10-08 設計稿用的門檻）。
const heavyWatchThreshold = 8;

/// 平倉時間落在 [month] 那個月的單（已平倉才算）。
List<TradeEntry> closedInMonth(Iterable<TradeEntry> trades, DateTime month) => [
  for (final t in trades)
    if (t.closedAt != null &&
        t.closedAt!.year == month.year &&
        t.closedAt!.month == month.month)
      t,
];

/// 開倉時間落在 [month] 那個月的單（含還持倉中的），月報「開倉次數」用。
int openedInMonth(Iterable<TradeEntry> trades, DateTime month) => trades
    .where(
      (t) => t.openedAt.year == month.year && t.openedAt.month == month.month,
    )
    .length;

/// 每天（平倉日）的損益合計。
Map<DateTime, double> pnlByDay(Iterable<TradeEntry> trades) {
  final map = <DateTime, double>{};
  for (final t in trades) {
    if (t.closedAt == null || t.pnl == null) continue;
    final d = dayOf(t.closedAt!);
    map[d] = (map[d] ?? 0) + t.pnl!;
  }
  return map;
}

/// 一組單的成績：幾單、贏幾單、合計賺賠。月報各種「依 xx 分組」共用。
class TradeGroup {
  const TradeGroup(this.label, this.count, this.wins, this.total);

  final String label;
  final int count;
  final int wins;
  final double total;
}

TradeGroup _group(String label, Iterable<TradeEntry> list) => TradeGroup(
  label,
  list.length,
  list.where((t) => (t.pnl ?? 0) > 0).length,
  list.fold(0.0, (s, t) => s + (t.pnl ?? 0)),
);

/// 依槓桿分三組：≤ 5x、6–10x、> 10x（沒有單的組也留著，畫面比較好對照）。
List<TradeGroup> byLeverage(List<TradeEntry> closed) => [
  _group('≤ 5x', closed.where((t) => t.leverage <= 5)),
  _group('6–10x', closed.where((t) => t.leverage > 5 && t.leverage <= 10)),
  _group('> 10x', closed.where((t) => t.leverage > 10)),
];

/// 自律成績單用的兩組：≤ 10x vs > 10x。
({TradeGroup low, TradeGroup high}) lowVsHighLeverage(
  List<TradeEntry> closed,
) => (
  low: _group('≤ 10x', closed.where((t) => t.leverage <= 10)),
  high: _group('> 10x', closed.where((t) => t.leverage > 10)),
);

List<TradeGroup> byDirection(List<TradeEntry> closed) => [
  _group('多單', closed.where((t) => t.isLong)),
  _group('空單', closed.where((t) => !t.isLong)),
];

/// 依幣種，單數多的在前。
List<TradeGroup> bySymbol(List<TradeEntry> closed) {
  final symbols = {for (final t in closed) t.symbol};
  return [
    for (final s in symbols) _group(s, closed.where((t) => t.symbol == s)),
  ]..sort((a, b) => b.count.compareTo(a.count));
}

/// 「看盤少的日子 vs 看盤多的日子」：只看有平倉的日子，依當天看盤次數
/// 分兩組，算每組幾天、平均每天賺賠。這是看盤跟交易整合起來才有的數字。
class WatchSplit {
  const WatchSplit({
    required this.calmDays,
    required this.calmAvg,
    required this.heavyDays,
    required this.heavyAvg,
  });

  final int calmDays;
  final double? calmAvg;
  final int heavyDays;
  final double? heavyAvg;
}

WatchSplit splitByWatch(
  Map<DateTime, double> dayPnl,
  Map<DateTime, int> watchCounts, {
  int threshold = heavyWatchThreshold,
}) {
  final calm = <double>[];
  final heavy = <double>[];
  dayPnl.forEach((day, pnl) {
    ((watchCounts[day] ?? 0) > threshold ? heavy : calm).add(pnl);
  });
  double? avg(List<double> l) =>
      l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  return WatchSplit(
    calmDays: calm.length,
    calmAvg: avg(calm),
    heavyDays: heavy.length,
    heavyAvg: avg(heavy),
  );
}

/// 最長連續虧損（依平倉時間排）：連賠幾單、合計賠多少。沒有虧損回傳 null。
({int count, double total})? longestLosingStreak(List<TradeEntry> closed) {
  final sorted = [...closed]
    ..sort((a, b) => a.closedAt!.compareTo(b.closedAt!));
  var best = (count: 0, total: 0.0);
  var run = (count: 0, total: 0.0);
  for (final t in sorted) {
    if ((t.pnl ?? 0) < 0) {
      run = (count: run.count + 1, total: run.total + t.pnl!);
      if (run.count > best.count ||
          (run.count == best.count && run.total < best.total)) {
        best = run;
      }
    } else {
      run = (count: 0, total: 0.0);
    }
  }
  return best.count == 0 ? null : best;
}

/// 一個月的總結，主畫面、日誌、月報共用。
class MonthTradeSummary {
  const MonthTradeSummary({
    required this.closed,
    required this.dayPnl,
    required this.total,
    required this.capital,
  });

  final List<TradeEntry> closed;
  final Map<DateTime, double> dayPnl;
  final double total;

  /// 月初資金，沒填是 null。
  final double? capital;

  /// 月報酬 %＝本月損益 ÷ 月初資金。
  double? get returnPercent =>
      capital == null || capital == 0 ? null : total / capital! * 100;

  int get wins => closed.where((t) => (t.pnl ?? 0) > 0).length;
  int get winDays => dayPnl.values.where((v) => v > 0).length;
  int get lossDays => dayPnl.values.where((v) => v < 0).length;

  /// 勝率（%），沒有單是 null。
  double? get winRate => closed.isEmpty ? null : wins / closed.length * 100;

  double? get avgWin {
    final w = closed.where((t) => (t.pnl ?? 0) > 0).toList();
    return w.isEmpty ? null : w.fold(0.0, (s, t) => s + t.pnl!) / w.length;
  }

  /// 平均每次賠多少（正數）。
  double? get avgLoss {
    final l = closed.where((t) => (t.pnl ?? 0) < 0).toList();
    return l.isEmpty ? null : -l.fold(0.0, (s, t) => s + t.pnl!) / l.length;
  }

  /// 盈虧比＝平均賺 ÷ 平均賠，任一邊沒有就是 null。
  double? get profitRatio {
    final w = avgWin, l = avgLoss;
    return w == null || l == null || l == 0 ? null : w / l;
  }

  double? get avgLeverage => closed.isEmpty
      ? null
      : closed.fold(0.0, (s, t) => s + t.leverage) / closed.length;

  MapEntry<DateTime, double>? get bestDay {
    final best = dayPnl.entries.where((e) => e.value > 0);
    return best.isEmpty
        ? null
        : best.reduce((a, b) => b.value > a.value ? b : a);
  }

  MapEntry<DateTime, double>? get worstDay {
    final worst = dayPnl.entries.where((e) => e.value < 0);
    return worst.isEmpty
        ? null
        : worst.reduce((a, b) => b.value < a.value ? b : a);
  }
}

MonthTradeSummary summarizeMonth(
  Iterable<TradeEntry> trades,
  DateTime month, {
  double? capital,
}) {
  final closed = closedInMonth(trades, month);
  return MonthTradeSummary(
    closed: closed,
    dayPnl: pnlByDay(closed),
    total: closed.fold(0.0, (s, t) => s + (t.pnl ?? 0)),
    capital: capital,
  );
}
