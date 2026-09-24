import 'models/habit_entry.dart';

/// 看盤紀錄的統計（純函式，給統計頁跟測試用）。

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// 每天看幾次。
Map<DateTime, int> countsByDay(List<HabitEntry> entries) {
  final map = <DateTime, int>{};
  for (final e in entries) {
    final d = dayOf(e.at);
    map[d] = (map[d] ?? 0) + 1;
  }
  return map;
}

/// 最近 [days] 天（含今天）每天次數，由舊到新。
List<({DateTime day, int count})> lastDays(
  List<HabitEntry> entries,
  DateTime now,
  int days,
) {
  final counts = countsByDay(entries);
  final today = dayOf(now);
  return [
    for (var i = days - 1; i >= 0; i--)
      (
        day: today.subtract(Duration(days: i)),
        count: counts[today.subtract(Duration(days: i))] ?? 0,
      ),
  ];
}

/// 相鄰兩次之間的平均間隔（只看 [since] 之後的紀錄），不到兩筆回傳 null。
Duration? averageInterval(List<HabitEntry> entries, DateTime since) {
  final times =
      entries.where((e) => !e.at.isBefore(since)).map((e) => e.at).toList()
        ..sort();
  if (times.length < 2) return null;
  final total = times.last.difference(times.first);
  return Duration(microseconds: total.inMicroseconds ~/ (times.length - 1));
}

/// 某一天內，相鄰兩次之間（含「當天第一次距離 0 點」不算）最長的間隔；
/// 如果是今天，最後一次到現在也算一段。不到一筆回傳 null。
Duration? longestGapOnDay(
  List<HabitEntry> entries,
  DateTime day,
  DateTime now,
) {
  final d = dayOf(day);
  final times = entries.where((e) => dayOf(e.at) == d).map((e) => e.at).toList()
    ..sort();
  if (times.isEmpty) return null;
  Duration best = Duration.zero;
  for (var i = 1; i < times.length; i++) {
    final gap = times[i].difference(times[i - 1]);
    if (gap > best) best = gap;
  }
  if (d == dayOf(now)) {
    final tail = now.difference(times.last);
    if (tail > best) best = tail;
  }
  return best;
}

/// 一天中的時段桶：深夜 22–6、早上 6–12、下午 12–18、晚上 18–22。
String timeBucket(DateTime t) {
  final h = t.hour;
  if (h >= 22 || h < 6) return '深夜 22–06';
  if (h < 12) return '早上 06–12';
  if (h < 18) return '下午 12–18';
  return '晚上 18–22';
}

const timeBuckets = ['早上 06–12', '下午 12–18', '晚上 18–22', '深夜 22–06'];

Map<String, int> countsByBucket(List<HabitEntry> entries) {
  final map = {for (final b in timeBuckets) b: 0};
  for (final e in entries) {
    final b = timeBucket(e.at);
    map[b] = map[b]! + 1;
  }
  return map;
}

/// 觸發原因次數（沒填的歸「未填」）。
Map<String, int> countsByReason(List<HabitEntry> entries) {
  final map = <String, int>{};
  for (final e in entries) {
    final r = e.reason ?? '未填';
    map[r] = (map[r] ?? 0) + 1;
  }
  return map;
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h 小時 $m 分';
  return '$m 分';
}
