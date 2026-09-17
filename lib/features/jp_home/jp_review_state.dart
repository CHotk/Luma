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
/// 只看清音表裡的 46 個字（[gojuonRows]）——手寫練習頁本來就只能從
/// 這張表選字，「匯入既有圖片」進來的片假名紀錄不在這個排程範圍內，
/// 這是刻意簡化，不是漏算。
List<KanaProgress> buildKanaProgress(List<KanaPracticeEntry> entries) {
  final byKana = <String, List<KanaPracticeEntry>>{};
  for (final e in entries) {
    byKana.putIfAbsent(e.kana, () => []).add(e);
  }

  return [
    for (final row in gojuonRows.values)
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
