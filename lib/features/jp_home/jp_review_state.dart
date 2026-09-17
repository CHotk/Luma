import '../../domain/jp_review_config.dart';
import '../../domain/models/kana_practice.dart';
import '../kana_practice/gojuon_data.dart';

/// 一個清音目前的複習狀態，只有這三種，沒有中間類別
/// （跟英文軌道 [RulesConfig] 的待複習／新字／已掌握是同一個精神）。
enum KanaBucket { fresh, due, mastered }

/// 五十音清音表裡一個字的練習狀況，從 [KanaPracticeEntry] 紀錄算出來。
class KanaProgress {
  const KanaProgress({
    required this.kana,
    required this.romaji,
    required this.practiceCount,
    required this.pureCount,
    required this.lastPracticedAt,
  });

  final String kana;
  final String romaji;

  /// 這個字被存過幾筆練習紀錄，不管輔助描摹還是純手寫。
  final int practiceCount;

  /// 這個字用「純手寫」模式練過幾次——只有純手寫才算真的會寫，
  /// 輔助描摹背景印著參考線，練再多次也不能算掌握。
  final int pureCount;

  final DateTime? lastPracticedAt;

  KanaBucket bucket(JpReviewConfig config, DateTime now) {
    if (practiceCount == 0) return KanaBucket.fresh;
    if (pureCount < config.masteryPracticeCount) return KanaBucket.due;

    final last = lastPracticedAt;
    if (last == null) return KanaBucket.due;
    final stale = now.difference(last).inDays >= config.reviewStaleDays;
    return stale ? KanaBucket.due : KanaBucket.mastered;
  }
}

/// 把目前所有練習紀錄套到五十音清音表上，算出每個字的練習狀況。
///
/// 看平假名＋片假名兩張表共 92 個字（[gojuonRows]／[gojuonRowsKatakana]）
/// ——2026-09-17 之前這裡只算 46 個平假名，因為手寫練習頁那時候只能
/// 選平假名；使用者要求兩邊都能練之後，片假名就跟平假名一樣正式排進
/// 複習排程，不再是例外。
List<KanaProgress> buildKanaProgress(List<KanaPracticeEntry> entries) {
  final byKana = <String, List<KanaPracticeEntry>>{};
  for (final e in entries) {
    byKana.putIfAbsent(e.kana, () => []).add(e);
  }

  return [
    for (final table in [gojuonRows, gojuonRowsKatakana])
      for (final row in table.values)
        for (final (kana, romaji) in row)
          KanaProgress(
            kana: kana,
            romaji: romaji,
            practiceCount: (byKana[kana] ?? const []).length,
            pureCount: (byKana[kana] ?? const [])
                .where((e) => !e.assisted)
                .length,
            lastPracticedAt: (byKana[kana] ?? const []).fold<DateTime?>(
              null,
              (latest, e) =>
                  latest == null || e.savedAt.isAfter(latest)
                      ? e.savedAt
                      : latest,
            ),
          ),
  ];
}

/// 46 個清音裡各狀態的數量，日文首頁「下一輪」清單直接顯示這個。
class KanaReviewSummary {
  const KanaReviewSummary({
    required this.fresh,
    required this.due,
    required this.mastered,
  });

  final int fresh;
  final int due;
  final int mastered;
}

KanaReviewSummary summarizeKanaReview(
  List<KanaProgress> progress,
  JpReviewConfig config, {
  required DateTime now,
}) {
  var fresh = 0, due = 0, mastered = 0;
  for (final p in progress) {
    switch (p.bucket(config, now)) {
      case KanaBucket.fresh:
        fresh++;
      case KanaBucket.due:
        due++;
      case KanaBucket.mastered:
        mastered++;
    }
  }
  return KanaReviewSummary(fresh: fresh, due: due, mastered: mastered);
}
