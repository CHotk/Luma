import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/trade_entry.dart';
import 'package:lume/domain/trade_stats.dart';

var _seq = 0;

TradeEntry t({
  required double pnl,
  double lev = 10,
  double margin = 100,
  bool long = true,
  String sym = 'BTC',
  required DateTime closed,
  DateTime? opened,
}) => TradeEntry(
  id: '${_seq++}',
  symbol: sym,
  isLong: long,
  leverage: lev,
  margin: margin,
  openedAt: opened ?? closed.subtract(const Duration(hours: 3)),
  closedAt: closed,
  pnl: pnl,
);

void main() {
  final sep = DateTime(2026, 9);
  final trades = [
    t(pnl: -40, lev: 20, closed: DateTime(2026, 9, 2, 15)),
    t(pnl: -120, lev: 25, long: false, closed: DateTime(2026, 9, 5, 18)),
    t(pnl: 55, lev: 5, sym: 'SOL', closed: DateTime(2026, 9, 9, 20)),
    t(pnl: 246, lev: 10, margin: 500, closed: DateTime(2026, 9, 18, 21)),
    t(pnl: 30, lev: 5, closed: DateTime(2026, 9, 18, 9)),
    t(pnl: 99, closed: DateTime(2026, 10, 1, 9)), // 下個月，不算
    TradeEntry(
      id: 'open',
      symbol: 'ETH',
      isLong: true,
      leverage: 10,
      margin: 300,
      openedAt: DateTime(2026, 9, 20),
    ), // 持倉中，不算損益
  ];

  test('損益算在平倉那天，持倉中跟別的月份不算', () {
    final m = summarizeMonth(trades, sep, capital: 2000);
    expect(m.closed.length, 5);
    expect(m.total, 171);
    expect(m.returnPercent, closeTo(8.55, 1e-9));
    expect(m.dayPnl[DateTime(2026, 9, 18)], 276);
    expect(m.winDays, 2);
    expect(m.lossDays, 2);
  });

  test('勝率、盈虧比、最大單日', () {
    final m = summarizeMonth(trades, sep);
    expect(m.winRate, 60);
    expect(m.avgWin, closeTo(331 / 3, 1e-9));
    expect(m.avgLoss, 80);
    expect(m.profitRatio, closeTo(331 / 3 / 80, 1e-9));
    expect(m.bestDay!.key, DateTime(2026, 9, 18));
    expect(m.worstDay!.value, -120);
    expect(m.returnPercent, isNull);
  });

  test('本金報酬率＝損益 ÷ 本金', () {
    expect(trades[3].pnlPercent, closeTo(49.2, 1e-9));
    expect(trades.last.pnlPercent, isNull);
    expect(trades.last.positionSize, 3000);
  });

  test('依槓桿／方向／幣種分組', () {
    final closed = closedInMonth(trades, sep);
    final lev = byLeverage(closed);
    expect(lev.map((g) => g.count), [2, 1, 2]);
    expect(lev[2].total, -160);
    final lh = lowVsHighLeverage(closed);
    expect(lh.low.total, 331);
    expect(lh.high.wins, 0);
    expect(byDirection(closed)[1].total, -120);
    expect(bySymbol(closed).first.label, 'BTC');
  });

  test('看盤少 vs 多：只算有平倉的日子', () {
    final split = splitByWatch(pnlByDay(closedInMonth(trades, sep)), {
      DateTime(2026, 9, 2): 11,
      DateTime(2026, 9, 5): 14,
      DateTime(2026, 9, 9): 3,
      DateTime(2026, 9, 12): 20, // 沒有交易，不算
    });
    expect(split.heavyDays, 2);
    expect(split.heavyAvg, -80);
    expect(split.calmDays, 2);
    expect(split.calmAvg, closeTo((55 + 276) / 2, 1e-9));
  });

  test('最長連續虧損依平倉時間排', () {
    final s = longestLosingStreak(closedInMonth(trades, sep));
    expect(s!.count, 2);
    expect(s.total, -160);
    expect(longestLosingStreak([trades[2]]), isNull);
  });

  test('開倉次數含持倉中', () {
    expect(openedInMonth(trades, sep), 6);
  });

  test('JSON 來回不掉資料', () {
    final back = TradeEntry.fromJson(trades[1].toJson());
    expect(back.toJson(), trades[1].toJson());
    final open = TradeEntry.fromJson(trades.last.toJson());
    expect(open.isOpen, isTrue);
    final cap = TradeMonthCapital.fromJson(
      const TradeMonthCapital(id: '2026-09', amount: 2000).toJson(),
    );
    expect(cap.amount, 2000);
    expect(TradeMonthCapital.idOf(DateTime(2026, 9)), '2026-09');
  });
}
