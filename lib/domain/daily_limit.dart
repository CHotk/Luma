import 'rules_config.dart';

/// 今天的用量。
///
/// 這是整支 App 最重要的一條規則：做滿就擋住，不是提醒而已。
/// 使用者要的是「限制我，避免我做太多然後過早放棄」。
/// 之後如果有人想把這段拿掉，請先回去看使用者 2026-09-11 說過的話。
class DailyUsage {
  const DailyUsage({
    required this.date,
    this.roundsDone = 0,
    this.practiceSeconds = 0,
  });

  /// 這筆用量屬於哪一天。跨日就整組歸零。
  final DateTime date;
  final int roundsDone;

  /// 純作答秒數。不含在單字庫閒逛的時間。
  final int practiceSeconds;

  DailyUsage copyWith({int? roundsDone, int? practiceSeconds}) => DailyUsage(
    date: date,
    roundsDone: roundsDone ?? this.roundsDone,
    practiceSeconds: practiceSeconds ?? this.practiceSeconds,
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'roundsDone': roundsDone,
    'practiceSeconds': practiceSeconds,
  };

  factory DailyUsage.fromJson(Map<String, dynamic> json) => DailyUsage(
    date: DateTime.parse(json['date'] as String),
    roundsDone: json['roundsDone'] as int? ?? 0,
    practiceSeconds: json['practiceSeconds'] as int? ?? 0,
  );
}

/// 判斷今天還能不能再做一輪。
abstract final class DailyLimit {
  /// 輪數或時間，哪個先到算哪個。
  static bool reached(DailyUsage usage, RulesConfig rules) {
    return usage.roundsDone >= rules.roundsPerDay ||
        usage.practiceSeconds >= rules.minutesPerDay * 60;
  }

  static int roundsLeft(DailyUsage usage, RulesConfig rules) {
    final left = rules.roundsPerDay - usage.roundsDone;
    return left < 0 ? 0 : left;
  }

  /// 跨日就把用量歸零。判斷只看年月日，不看時分秒。
  static DailyUsage rollOver(DailyUsage usage, DateTime now) {
    final sameDay =
        usage.date.year == now.year &&
        usage.date.month == now.month &&
        usage.date.day == now.day;
    return sameDay ? usage : DailyUsage(date: now);
  }
}
