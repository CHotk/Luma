import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/daily_limit.dart';
import '../../domain/models/history.dart';
import '../../domain/rules_config.dart';
import '../../domain/scoring.dart';

/// 月曆卡片點某一天要顯示的內容（2026-09-29 使用者要求：英文首頁也要
/// 跟日文首頁一樣的打卡熱度月曆卡片——跟 `jp_home_controller.dart` 的
/// [JpDaySummary] 是同樣概念但各自獨立一份，不共用，英文軌道跟日文
/// 軌道本來就是分開的兩套資料）。
class EnHomeDaySummary {
  const EnHomeDaySummary({
    required this.count,
    required this.minutes,
    required this.words,
  });

  /// 那天答了幾題。
  final int count;

  /// 那天花費的分鐘數，從每題的 [HistoryEntry.seconds] 加總算出來。
  final int minutes;

  /// 那天練過的單字，依作答次數由多到少排序，同一個字答幾次就算幾次。
  final List<({String word, int count})> words;
}

/// 首頁要顯示的東西，一次算好，畫面只負責排版。
class HomeState {
  const HomeState({
    required this.rules,
    required this.usage,
    required this.total,
    required this.confirmed,
    required this.pending,
    required this.practicedDaysThisMonth,
    required this.streakDays,
    required this.firstPracticedAt,
    required this.daysSinceStart,
    required this.allPracticedDates,
    required this.daySummaries,
  });

  final RulesConfig rules;
  final DailyUsage usage;
  final int total;
  final int confirmed;
  final int pending;

  bool get limitReached => DailyLimit.reached(usage, rules);
  int get roundsLeft => DailyLimit.roundsLeft(usage, rules);

  /// 這個月（含今天）練過的「日」，1~31，給月曆看板卡片塗色用
  /// （2026-09-29 使用者要求：跟日文首頁一樣的打卡熱度月曆）。
  final Set<int> practicedDaysThisMonth;

  /// 從今天往回算，連續練習了幾天，算法跟日文首頁那張卡片一致。
  final int streakDays;

  /// 最早一筆作答紀錄是哪一天，從沒練過就是 null。
  final DateTime? firstPracticedAt;

  /// 從第一次練習那天算到今天，含頭尾兩端各算一天。沒練過就是 0。
  final int daysSinceStart;

  /// 全部有練習過的日期（不限這個月），給月曆卡片切換月份用。
  final Set<DateTime> allPracticedDates;

  /// 每一天的練習摘要，key 是那天零點的日期。
  final Map<DateTime, EnHomeDaySummary> daySummaries;
}

/// autoDispose：離開首頁就丟掉，回來時重新算，
/// 這樣做完一輪回來數字一定是新的，不用手動通知。
final homeStateProvider = FutureProvider.autoDispose<HomeState>((ref) async {
  // 有寫入就重算，不然回到首頁看到的還是上一輪之前的數字。
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final settings = ref.watch(settingsRepositoryProvider);
  final words = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await settings.loadRules();
  final usage = await settings.loadUsage(now);
  final summary = Scoring.summarize(words, rules);

  final entries = await ref.watch(historyRepositoryProvider).entries();
  final practicedDates = {
    for (final e in entries) DateTime(e.at.year, e.at.month, e.at.day),
  };
  final practicedDaysThisMonth = {
    for (final d in practicedDates)
      if (d.year == now.year && d.month == now.month) d.day,
  };
  var streakDays = 0;
  var cursor = DateTime(now.year, now.month, now.day);
  while (practicedDates.contains(cursor)) {
    streakDays++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  DateTime? firstPracticedAt;
  for (final d in practicedDates) {
    if (firstPracticedAt == null || d.isBefore(firstPracticedAt)) {
      firstPracticedAt = d;
    }
  }
  final daysSinceStart = firstPracticedAt == null
      ? 0
      : DateTime(
              now.year,
              now.month,
              now.day,
            ).difference(firstPracticedAt).inDays +
            1;

  final entriesByDay = <DateTime, List<HistoryEntry>>{};
  for (final e in entries) {
    final d = DateTime(e.at.year, e.at.month, e.at.day);
    entriesByDay.putIfAbsent(d, () => []).add(e);
  }
  final daySummaries = {
    for (final entry in entriesByDay.entries)
      entry.key: _buildEnDaySummary(entry.value),
  };

  return HomeState(
    rules: rules,
    usage: usage,
    total: summary.total,
    confirmed: summary.confirmed,
    pending: summary.pending,
    practicedDaysThisMonth: practicedDaysThisMonth,
    streakDays: streakDays,
    firstPracticedAt: firstPracticedAt,
    daysSinceStart: daysSinceStart,
    allPracticedDates: practicedDates,
    daySummaries: daySummaries,
  );
});

EnHomeDaySummary _buildEnDaySummary(List<HistoryEntry> dayEntries) {
  var totalSeconds = 0;
  final wordCounts = <String, int>{};
  for (final e in dayEntries) {
    totalSeconds += e.seconds;
    wordCounts[e.word] = (wordCounts[e.word] ?? 0) + 1;
  }
  final sortedWords = wordCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return EnHomeDaySummary(
    count: dayEntries.length,
    minutes: totalSeconds ~/ 60,
    words: [for (final e in sortedWords) (word: e.key, count: e.value)],
  );
}
