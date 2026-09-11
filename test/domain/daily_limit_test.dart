import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/daily_limit.dart';
import 'package:lume/domain/rules_config.dart';

/// 每日上限是這支 App 的核心規則：做滿就擋住，不是只跳提示。
void main() {
  final today = DateTime(2026, 9, 11, 20);
  const rules = RulesConfig(roundsPerDay: 5, minutesPerDay: 15);

  group('DailyLimit', () {
    test('沒做滿就還能做', () {
      final usage = DailyUsage(date: today, roundsDone: 4);
      expect(DailyLimit.reached(usage, rules), isFalse);
      expect(DailyLimit.roundsLeft(usage, rules), 1);
    });

    test('輪數到了就擋住', () {
      final usage = DailyUsage(date: today, roundsDone: 5);
      expect(DailyLimit.reached(usage, rules), isTrue);
      expect(DailyLimit.roundsLeft(usage, rules), 0);
    });

    test('時間先到也擋住', () {
      final usage = DailyUsage(
        date: today,
        roundsDone: 1,
        practiceSeconds: 15 * 60,
      );
      expect(DailyLimit.reached(usage, rules), isTrue);
    });

    test('跨日自動歸零', () {
      final yesterday = DailyUsage(
        date: DateTime(2026, 9, 10, 23),
        roundsDone: 5,
        practiceSeconds: 900,
      );
      final rolled = DailyLimit.rollOver(yesterday, today);
      expect(rolled.roundsDone, 0);
      expect(rolled.practiceSeconds, 0);
    });

    test('同一天不歸零', () {
      final earlier = DailyUsage(date: DateTime(2026, 9, 11, 9), roundsDone: 3);
      expect(DailyLimit.rollOver(earlier, today).roundsDone, 3);
    });
  });
}
