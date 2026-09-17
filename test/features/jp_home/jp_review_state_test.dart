import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/jp_review_config.dart';
import 'package:lume/domain/models/kana_practice.dart';
import 'package:lume/features/jp_home/jp_review_state.dart';

void main() {
  const config = JpReviewConfig(
    dailyKanaTarget: 5,
    dailyMinutesTarget: 10,
    masteryPracticeCount: 3,
    reviewStaleDays: 7,
  );

  KanaPracticeEntry entry(
    String kana,
    String romaji, {
    required bool assisted,
    required DateTime savedAt,
  }) => KanaPracticeEntry(
    id: '$kana-${savedAt.microsecondsSinceEpoch}',
    kana: kana,
    romaji: romaji,
    assisted: assisted,
    savedAt: savedAt,
    strokes: const [],
  );

  test('沒練過的字算新字', () {
    final progress = buildKanaProgress(const []);
    final summary = summarizeKanaReview(progress, config, now: DateTime(2026, 9, 17));

    expect(summary.fresh, 46, reason: '五十音清音表總共 46 個字，一筆紀錄都沒有就全部是新字');
    expect(summary.due, 0);
    expect(summary.mastered, 0);
  });

  test('輔助描摹練再多次都不算掌握，算待複習', () {
    final entries = [
      for (var i = 0; i < 5; i++)
        entry('あ', 'a', assisted: true, savedAt: DateTime(2026, 9, 10 + i)),
    ];
    final progress = buildKanaProgress(entries);
    final summary = summarizeKanaReview(progress, config, now: DateTime(2026, 9, 17));

    expect(summary.due, 1);
    expect(summary.mastered, 0);
    expect(summary.fresh, 45);
  });

  test('純手寫練到門檻次數就算掌握', () {
    final entries = [
      for (var i = 0; i < 3; i++)
        entry('あ', 'a', assisted: false, savedAt: DateTime(2026, 9, 14 + i)),
    ];
    final progress = buildKanaProgress(entries);
    final summary = summarizeKanaReview(progress, config, now: DateTime(2026, 9, 17));

    expect(summary.mastered, 1);
    expect(summary.due, 0);
  });

  test('已掌握但太久沒碰，退回待複習', () {
    final entries = [
      for (var i = 0; i < 3; i++)
        entry('あ', 'a', assisted: false, savedAt: DateTime(2026, 9, 1 + i)),
    ];
    final progress = buildKanaProgress(entries);
    // 最後一次練習是 9/3，現在是 9/17，隔了 14 天，超過 reviewStaleDays（7）。
    final summary = summarizeKanaReview(progress, config, now: DateTime(2026, 9, 17));

    expect(summary.due, 1, reason: '太久沒複習，就算次數夠也要退回待複習');
    expect(summary.mastered, 0);
  });

  test('片假名或其他不在清音表裡的紀錄不會被算進任何一類', () {
    final entries = [entry('ア', 'a', assisted: false, savedAt: DateTime(2026, 9, 17))];
    final progress = buildKanaProgress(entries);
    final summary = summarizeKanaReview(progress, config, now: DateTime(2026, 9, 17));

    expect(summary.fresh + summary.due + summary.mastered, 46, reason: '片假名不在表裡，總數還是 46');
  });
}
