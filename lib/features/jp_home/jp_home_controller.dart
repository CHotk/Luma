import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../domain/jp_review_config.dart';
import '../../domain/models/kana_practice.dart';
import 'jp_review_state.dart';

/// 月曆卡片點某一天要顯示的內容（2026-09-29 使用者要求：點某一天要能
/// 看到一些資訊，不是只有塗色）。
class JpDaySummary {
  const JpDaySummary({
    required this.count,
    required this.minutes,
    required this.kana,
    this.examCount = 0,
    this.examCorrect = 0,
  });

  /// 那天存了幾筆練習紀錄。
  final int count;

  /// 那天練習花的分鐘數，算法跟 [JpHomeState.todayMinutes] 同一套。
  final int minutes;

  /// 那天練過的假名，依練習次數由多到少排序，同一個假名出現幾次
  /// 就算幾次（不去重成只顯示一次）。
  final List<({String kana, String romaji, int count})> kana;

  /// 那天考試答了幾題、答對幾題（2026-10-05 使用者回報：只有考試的日子，
  /// 月曆沒塗色、點進來也說沒紀錄）。
  final int examCount;
  final int examCorrect;
}

/// 日文首頁要顯示的東西，一次算好，畫面只負責排版
/// （跟英文軌道的 [HomeState] 同一個做法）。
class JpHomeState {
  const JpHomeState({
    required this.config,
    required this.todayCount,
    required this.todayMinutes,
    required this.review,
    required this.practicedDaysThisMonth,
    required this.streakDays,
    required this.firstPracticedAt,
    required this.daysSinceStart,
    required this.allPracticedDates,
    required this.daySummaries,
  });

  final JpReviewConfig config;

  /// 今天存了幾筆練習紀錄，首頁進度環的「done」看這個。
  final int todayCount;

  /// 今天練習花的分鐘數，從每筆紀錄的筆畫時間戳加總算出來，不是編的。
  final int todayMinutes;

  final KanaReviewSummary review;

  /// 這個月（含今天）練過的「日」，1~31，給月曆看板卡片塗色用
  /// （2026-09-29 使用者要求：日文首頁加打卡熱度月曆，在原有版面上加，
  /// 不是取代——見 `design-history/日文月曆看板設計/01`）。
  final Set<int> practicedDaysThisMonth;

  /// 從今天往回算，連續練習了幾天（今天還沒練也算，只要昨天有練就
  /// 從昨天開始算，不會因為「今天還沒點開 App」就把昨天累積的連續
  /// 天數歸零——這是使用者查看首頁那一刻的即時狀態，不是硬性規則）。
  final int streakDays;

  /// 最早一筆練習紀錄是哪一天（2026-09-29 使用者要求：統計要能看到
  /// 「幾號開始學習」）。從沒練過就是 null。
  final DateTime? firstPracticedAt;

  /// 從第一次練習那天算到今天，含頭尾兩端各算一天（今天開始學就是
  /// 「已經 1 天」，不是 0）。沒練過就是 0。
  final int daysSinceStart;

  /// 全部有練習過的日期（不限這個月），給月曆卡片切換月份用
  /// （2026-09-29 使用者要求：點月份標題要能選其他月，不是只能看當月）。
  final Set<DateTime> allPracticedDates;

  /// 每一天的練習摘要，key 是那天零點的日期（2026-09-29 使用者要求：
  /// 月曆卡片點某一天要能看到資訊）。沒練過的日子不會有 entry。
  final Map<DateTime, JpDaySummary> daySummaries;
}

/// autoDispose：離開日文首頁就丟掉，回來時重新算，practice 頁自動存檔
/// 之後靠 [dataRevisionProvider] 通知這裡要重算。
final jpHomeStateProvider = FutureProvider.autoDispose<JpHomeState>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final config = await loadJpReviewConfig();
  final entries = await ref.watch(kanaPracticeRepositoryProvider).loadAll();
  // 考試紀錄跟練習紀錄分開存（考試要能單獨看正確率），但「那天有沒有
  // 練日文」兩種都算：只考了試的日子，月曆也要塗色、連續天數也要接上
  // （2026-10-05 使用者回報考完回首頁今天沒亮）。
  final exams = await ref.watch(kanaExamRepositoryProvider).loadAll();
  final now = DateTime.now();

  final today = entries.where(
    (e) =>
        e.savedAt.year == now.year &&
        e.savedAt.month == now.month &&
        e.savedAt.day == now.day,
  );

  // 每筆紀錄自己的練習時間＝那筆筆畫時間軸最後一個時間戳（見
  // KanaPracticeEntry.strokes 的說明：時間軸從那一筆的第一次落筆算起，
  // 換字／存檔就會歸零重算），今天花的總分鐘數是今天所有紀錄加總，
  // 不是找最大值。匯入的舊圖片沒有筆畫資料，貢獻 0，不會假裝有練習
  // 時間。
  var todayMs = 0.0;
  for (final e in today) {
    var entryMs = 0.0;
    for (final stroke in e.strokes) {
      if (stroke.isEmpty) continue;
      final last = stroke.last.$3;
      if (last > entryMs) entryMs = last;
    }
    todayMs += entryMs;
  }

  final progress = buildKanaProgress(entries);
  final review = summarizeKanaReview(progress, config, now: now);

  // 已刪除（墓碑）的紀錄不算「有練習」，跟畫面其他地方看 loadAll() 的
  // 邏輯一致（loadAll 本身已經濾掉 deletedAt != null，這裡沿用同一份
  // entries 就好，不用另外再濾一次）。
  final practicedDates = {
    for (final e in entries)
      DateTime(e.savedAt.year, e.savedAt.month, e.savedAt.day),
    for (final e in exams)
      DateTime(e.savedAt.year, e.savedAt.month, e.savedAt.day),
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

  final entriesByDay = <DateTime, List<KanaPracticeEntry>>{};
  for (final e in entries) {
    final d = DateTime(e.savedAt.year, e.savedAt.month, e.savedAt.day);
    entriesByDay.putIfAbsent(d, () => []).add(e);
  }
  final examsByDay = <DateTime, ({int count, int correct})>{};
  for (final e in exams) {
    final d = DateTime(e.savedAt.year, e.savedAt.month, e.savedAt.day);
    final prev = examsByDay[d] ?? (count: 0, correct: 0);
    examsByDay[d] = (
      count: prev.count + 1,
      correct: prev.correct + (e.isCorrect ? 1 : 0),
    );
  }
  final daySummaries = {
    for (final d in {...entriesByDay.keys, ...examsByDay.keys})
      d: _buildDaySummary(entriesByDay[d] ?? const [], exam: examsByDay[d]),
  };

  return JpHomeState(
    config: config,
    todayCount: today.length,
    todayMinutes: todayMs ~/ 60000,
    review: review,
    practicedDaysThisMonth: practicedDaysThisMonth,
    streakDays: streakDays,
    firstPracticedAt: firstPracticedAt,
    daysSinceStart: daysSinceStart,
    allPracticedDates: practicedDates,
    daySummaries: daySummaries,
  );
});

/// 算某一天的練習摘要，邏輯跟算「今天」那段（[todayMs]）同一套，只是
/// 換成任一天的紀錄清單。
JpDaySummary _buildDaySummary(
  List<KanaPracticeEntry> dayEntries, {
  ({int count, int correct})? exam,
}) {
  var ms = 0.0;
  final kanaCounts = <String, int>{};
  final romajiByKana = <String, String>{};
  for (final e in dayEntries) {
    var entryMs = 0.0;
    for (final stroke in e.strokes) {
      if (stroke.isEmpty) continue;
      final last = stroke.last.$3;
      if (last > entryMs) entryMs = last;
    }
    ms += entryMs;
    kanaCounts[e.kana] = (kanaCounts[e.kana] ?? 0) + 1;
    romajiByKana[e.kana] = e.romaji;
  }
  final sortedKana = kanaCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return JpDaySummary(
    count: dayEntries.length,
    minutes: ms ~/ 60000,
    examCount: exam?.count ?? 0,
    examCorrect: exam?.correct ?? 0,
    kana: [
      for (final e in sortedKana)
        (kana: e.key, romaji: romajiByKana[e.key]!, count: e.value),
    ],
  );
}
