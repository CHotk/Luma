import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/crypto_watch_stats.dart';
import 'package:lume/domain/models/crypto_watch_entry.dart';

CryptoWatchEntry e(DateTime at, {String? reason}) =>
    CryptoWatchEntry(id: at.toIso8601String(), at: at, reason: reason);

void main() {
  final now = DateTime(2026, 9, 24, 15, 0);

  test('countsByDay 依日期算次數', () {
    final counts = countsByDay([
      e(DateTime(2026, 9, 24, 9)),
      e(DateTime(2026, 9, 24, 12)),
      e(DateTime(2026, 9, 23, 22)),
    ]);
    expect(counts[DateTime(2026, 9, 24)], 2);
    expect(counts[DateTime(2026, 9, 23)], 1);
  });

  test('lastDays 補齊沒有紀錄的日子並由舊到新', () {
    final days = lastDays([e(DateTime(2026, 9, 24, 9))], now, 3);
    expect(days.map((d) => d.count), [0, 0, 1]);
    expect(days.first.day, DateTime(2026, 9, 22));
  });

  test('averageInterval：不到兩筆是 null，否則是平均間隔', () {
    final since = DateTime(2026, 9, 1);
    expect(averageInterval([e(DateTime(2026, 9, 24, 9))], since), isNull);
    final avg = averageInterval([
      e(DateTime(2026, 9, 24, 9)),
      e(DateTime(2026, 9, 24, 11)),
      e(DateTime(2026, 9, 24, 15)),
    ], since);
    expect(avg, const Duration(hours: 3));
  });

  test('longestGapOnDay：今天要把最後一次到現在也算進去', () {
    final gap = longestGapOnDay(
      [e(DateTime(2026, 9, 24, 9)), e(DateTime(2026, 9, 24, 10))],
      now,
      now,
    );
    expect(gap, const Duration(hours: 5));
  });

  test('時段桶與原因統計', () {
    expect(timeBucket(DateTime(2026, 1, 1, 23)), '深夜 22–06');
    expect(timeBucket(DateTime(2026, 1, 1, 3)), '深夜 22–06');
    expect(timeBucket(DateTime(2026, 1, 1, 8)), '早上 06–12');
    final r = countsByReason([
      e(DateTime(2026, 9, 24, 9), reason: '焦慮'),
      e(DateTime(2026, 9, 24, 10)),
    ]);
    expect(r['焦慮'], 1);
    expect(r['未填'], 1);
  });
}
