import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/domain/models/kana_practice.dart';
import 'package:lume/features/jp_light/jp_light_data.dart';

/// 點亮（2026-10-15）：點亮模式考某一行、整輪全對才開花。
void main() {
  KanaExamEntry e(
    String round,
    String kana,
    bool ok,
    DateTime at, {
    String? row,
  }) => KanaExamEntry(
    id: '$round-$kana',
    roundId: round,
    kana: kana,
    romaji: '',
    isCorrect: ok,
    examType: 'kana',
    savedAt: at,
    strokes: const [],
    lightRow: row,
  );

  test('あ行：第一輪錯一個、第二輪全對 → 第二輪那天開花；最好 100%', () {
    final d1 = DateTime(2026, 10, 10), d2 = DateTime(2026, 10, 12);
    final exams = [
      for (final (k, ok) in [
        ('あ', true),
        ('イ', true),
        ('う', false),
        ('え', true),
        ('オ', true),
      ])
        e('r1', k, ok, d1, row: 'あ'),
      for (final k in ['ア', 'い', 'ウ', 'エ', 'お']) e('r2', k, true, d2, row: 'あ'),
      // 一般考試全對不算
      for (final k in ['か', 'き', 'く', 'け', 'こ']) e('r3', k, true, d2),
    ];
    final practice = [
      KanaPracticeEntry(
        id: 'p1',
        kana: 'あ',
        romaji: 'a',
        assisted: false,
        savedAt: DateTime(2026, 10, 1),
        strokes: const [
          [(0.0, 0.0, 0.0), (1.0, 1.0, 3000.0)],
        ],
      ),
    ];
    final l = computeJpLight(exams, practice);
    final a = l.firstWhere((x) => x.row == 'あ');
    expect(a.lit, isTrue);
    expect(a.litAt, d2);
    expect(a.exams, 2);
    expect(a.best, 100);
    expect(a.lastWrong, isEmpty);
    expect(a.practiceCount, 1);
    expect(a.practiceTime, const Duration(seconds: 3));
    expect(a.daysToLight, 11);
    final ka = l.firstWhere((x) => x.row == 'か');
    expect(ka.lit, isFalse);
    expect(ka.exams, 0);
  });

  test('沒寫完整輪不算', () {
    final exams = [
      for (final k in ['か', 'き'])
        e('r', k, true, DateTime(2026, 10, 1), row: 'か'),
    ];
    final ka = computeJpLight(exams, const []).firstWhere((x) => x.row == 'か');
    expect(ka.exams, 0);
    expect(ka.lit, isFalse);
  });
}
