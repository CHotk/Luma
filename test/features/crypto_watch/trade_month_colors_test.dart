import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/trade_entry.dart';
import 'package:lume/features/crypto_watch/trade_ui.dart';

/// 交易月曆每單顏色（2026-10-15 使用者要求）：每月打亂一次、用完照同順序
/// 輪、跨月單保留原色、剩下的打亂接在後面。
void main() {
  final now = DateTime(2026, 12, 31);
  TradeEntry t(String id, DateTime open, [DateTime? close]) => TradeEntry(
    id: id,
    symbol: 'BTC',
    isLong: true,
    leverage: 10,
    margin: 100,
    openedAt: open,
    closedAt: close,
  );

  test('一個月內前五單五種顏色都不重複，第六單起照同一個順序再輪', () {
    final trades = [
      for (var i = 0; i < 12; i++)
        t('a$i', DateTime(2026, 10, i + 1), DateTime(2026, 10, i + 1, 12)),
    ];
    final c = tradeMonthColors(trades, 2026, 10, now: now);
    final first = [for (var i = 0; i < 5; i++) c['a$i']!];
    expect(first.toSet(), tradeOverlapColors.toSet());
    for (var i = 5; i < 12; i++) {
      expect(c['a$i'], first[i % 5]);
    }
  });

  test('同一個月每次算都一樣；不同月份順序不全相同', () {
    List<Color> orderOf(int m) {
      final trades = [
        for (var i = 0; i < 5; i++)
          t('$m-$i', DateTime(2026, m, i + 1), DateTime(2026, m, i + 1, 12)),
      ];
      final c = tradeMonthColors(trades, 2026, m, now: now);
      return [for (var i = 0; i < 5; i++) c['$m-$i']!];
    }

    expect(orderOf(10), orderOf(10));
    final all = {for (var m = 1; m <= 12; m++) orderOf(m).join()};
    expect(all.length, greaterThan(1));
  });

  test('跨月單保留上個月的顏色，這個月新單用剩下四種，用完才輪回它的顏色', () {
    final carry = t('carry', DateTime(2026, 9, 28)); // 抱著沒平
    final trades = [
      t('s1', DateTime(2026, 9, 1), DateTime(2026, 9, 2)),
      t('s2', DateTime(2026, 9, 3), DateTime(2026, 9, 4)),
      carry,
      for (var i = 0; i < 5; i++)
        t('n$i', DateTime(2026, 10, i + 2), DateTime(2026, 10, i + 2, 12)),
    ];
    final sep = tradeMonthColors(trades, 2026, 9, now: now);
    final oct = tradeMonthColors(trades, 2026, 10, now: now);
    expect(oct['carry'], sep['carry']);
    final news = [for (var i = 0; i < 4; i++) oct['n$i']!];
    expect(news.toSet().length, 4);
    expect(news, isNot(contains(sep['carry'])));
    expect(oct['n4'], sep['carry']);
  });
}
