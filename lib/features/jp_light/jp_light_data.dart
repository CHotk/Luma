import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/kana_exam.dart';
import '../../domain/models/kana_practice.dart';
import '../kana_practice/gojuon_data.dart';

/// 日文「點亮」（2026-10-15 使用者選設計稿
/// `design-history/已選擇完成/2026-10-15_日文點亮進度五種設計.html` 第 4 版
/// 「櫻花樹開花」）：一行（あ～わ）一朵花，考試選「點亮」模式、一次只考
/// 那一行、全部答對就開花。考試本來就每題隨機平假／片假，所以不分兩種
/// 字，一共 10 朵。
class JpRowLight {
  const JpRowLight({
    required this.row,
    required this.litAt,
    required this.firstAt,
    required this.practiceCount,
    required this.practiceTime,
    required this.exams,
    required this.best,
    required this.lastWrong,
  });

  /// 行的 key（あ、か…），見 [gojuonRows]。
  final String row;

  /// 第一次全對（開花）的時間；還沒開是 null。
  final DateTime? litAt;

  /// 第一次碰這一行（手寫練習或點亮考試）的時間；還沒碰過是 null。
  final DateTime? firstAt;

  /// 這一行的字手寫練了幾次、寫了多久（筆畫時間加總）。
  final int practiceCount;
  final Duration practiceTime;

  /// 點亮考試考過幾次（寫完整輪才算）、最好幾 %。
  final int exams;
  final int best;

  /// 最近一次點亮考試寫錯的字（全對就是空的）。
  final List<String> lastWrong;

  bool get lit => litAt != null;

  /// 從第一次碰到開花花了幾天（至少 1 天）。
  int? get daysToLight => litAt == null || firstAt == null
      ? null
      : (litAt!.difference(firstAt!).inHours / 24).ceil().clamp(1, 99999);
}

/// 這一行包含的字（平假、片假都算）。
Set<String> jpRowKana(String row) => {
  for (final k in gojuonRows[row] ?? const <(String, String)>[]) k.$1,
  for (final k in gojuonRowsKatakana[row] ?? const <(String, String)>[]) k.$1,
};

List<JpRowLight> computeJpLight(
  List<KanaExamEntry> exams,
  List<KanaPracticeEntry> practice,
) {
  final out = <JpRowLight>[];
  for (final row in gojuonRows.keys) {
    final kana = jpRowKana(row);
    final size = gojuonRows[row]!.length;
    // 點亮考試：照輪次分組，寫完整輪（題數＝這一行的字數）才算。
    final rounds = <String, List<KanaExamEntry>>{};
    for (final e in exams) {
      if (e.deletedAt != null || e.lightRow != row) continue;
      (rounds[e.roundId] ??= []).add(e);
    }
    final done = [
      for (final r in rounds.values)
        if (r.length >= size) r..sort((a, b) => a.savedAt.compareTo(b.savedAt)),
    ]..sort((a, b) => a.last.savedAt.compareTo(b.last.savedAt));
    DateTime? litAt;
    var best = 0;
    for (final r in done) {
      final right = r.where((e) => e.isCorrect).length;
      final pct = (right * 100 / r.length).round();
      if (pct > best) best = pct;
      if (right == r.length) litAt ??= r.last.savedAt;
    }
    final mine = [
      for (final p in practice)
        if (p.deletedAt == null && kana.contains(p.kana)) p,
    ];
    var ms = 0.0;
    for (final p in mine) {
      final last = p.strokes.isEmpty || p.strokes.last.isEmpty
          ? 0.0
          : p.strokes.last.last.$3;
      ms += last;
    }
    final starts = [
      for (final p in mine) p.savedAt,
      for (final r in rounds.values)
        for (final e in r) e.savedAt,
    ]..sort();
    out.add(
      JpRowLight(
        row: row,
        litAt: litAt,
        firstAt: starts.isEmpty ? null : starts.first,
        practiceCount: mine.length,
        practiceTime: Duration(milliseconds: ms.round()),
        exams: done.length,
        best: best,
        lastWrong: done.isEmpty
            ? const []
            : [
                for (final e in done.last)
                  if (!e.isCorrect) e.kana,
              ],
      ),
    );
  }
  return out;
}

/// 櫻花樹頁、日文首頁的小卡都看這個；考完、練完（[dataRevisionProvider]
/// 變了）自己重算。
final jpLightProvider = FutureProvider.autoDispose<List<JpRowLight>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final exams = await ref.read(kanaExamRepositoryProvider).loadAll();
  final practice = await ref.read(kanaPracticeRepositoryProvider).loadAll();
  return computeJpLight(exams, practice);
});

String fmtPracticeTime(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return '${d.inSeconds} 秒';
  if (m < 60) return '$m 分';
  return '${m ~/ 60} 小時 ${m % 60} 分';
}
