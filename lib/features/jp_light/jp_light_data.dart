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
/// 開花那一刻的紀錄（2026-10-16 使用者要求）：到開花為止**全部累加**的
/// 手寫練習幾次、普通考試幾輪、點亮通關幾次，從第一天練到開花多久，跟
/// 開花的時間。不另外存檔——練習／考試紀錄一筆都不刪（刪除只是標記
/// `deletedAt`），所以用「那一刻還在的紀錄」重算，結果永遠跟當下一樣。
class JpBloomRecord {
  const JpBloomRecord({
    required this.at,
    required this.since,
    required this.practiceCount,
    required this.examRounds,
    required this.lightPasses,
  });

  /// 開花的時間（那一輪最後一題存檔的時間）。
  final DateTime at;

  /// 第一天練習（第一筆手寫或考試）的時間；從這裡算到 [at] 練了多久。
  final DateTime since;

  /// 到開花為止：手寫練習總次數（所有字）。
  final int practiceCount;

  /// 到開花為止：普通考試（不是點亮）考了幾輪。
  final int examRounds;

  /// 到開花為止：點亮考試全對通關幾次（含這一次）。
  final int lightPasses;

  Duration get span => at.difference(since);
}

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
    this.record,
  });

  /// 開花那一刻的累加紀錄；還沒開是 null。
  final JpBloomRecord? record;

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

/// 點亮某一行要考哪幾行：從あ一路考到這一行（2026-10-16 使用者要求：
/// 每開一朵花，前面開過的也要再考一遍；只能照五十音順序一行一行點亮）。
List<String> jpLightExamRows(String row) {
  final keys = gojuonRows.keys.toList();
  return keys.sublist(0, keys.indexOf(row) + 1);
}

/// 點亮某一行要寫幾題：考的每一行、每個字平假片假各考一次（2026-10-16
/// 使用者要求：每一行都要包含平假跟片假）。
int jpLightExamSize(String row) => [
  for (final r in jpLightExamRows(row)) gojuonRows[r]!.length * 2,
].fold(0, (a, b) => a + b);

/// 下一個能點亮的行（照順序第一個還沒開的）；全開了是 null。
String? jpNextLightRow(List<JpRowLight> lights) {
  for (final l in lights) {
    if (!l.lit) return l.row;
  }
  return null;
}

/// 這一行現在能不能考點亮：開過的可以再考，沒開的只有輪到的那一行可以。
bool jpCanLight(List<JpRowLight> lights, String row) =>
    lights.any((l) => l.row == row && l.lit) || jpNextLightRow(lights) == row;

List<JpRowLight> computeJpLight(
  List<KanaExamEntry> exams,
  List<KanaPracticeEntry> practice,
) {
  // 那一刻還在（存了、還沒被刪）的紀錄。
  bool alive(DateTime saved, DateTime? deleted, DateTime t) =>
      !saved.isAfter(t) && (deleted == null || deleted.isAfter(t));
  // 所有點亮考試輪次：寫完整輪又全對的，記下通關時間。
  final lightRounds = <String, List<KanaExamEntry>>{};
  for (final e in exams) {
    if (e.lightRow != null) (lightRounds[e.roundId] ??= []).add(e);
  }
  JpBloomRecord recordAt(DateTime t) {
    final practiceAlive = [
      for (final p in practice)
        if (alive(p.savedAt, p.deletedAt, t)) p.savedAt,
    ];
    final examAlive = [
      for (final e in exams)
        if (alive(e.savedAt, e.deletedAt, t)) e,
    ];
    var passes = 0;
    for (final r in lightRounds.values) {
      final live = [
        for (final e in r)
          if (alive(e.savedAt, e.deletedAt, t)) e,
      ];
      if (live.isNotEmpty &&
          live.length >= jpLightExamSize(r.first.lightRow!) &&
          live.every((e) => e.isCorrect)) {
        passes++;
      }
    }
    final starts = [...practiceAlive, for (final e in examAlive) e.savedAt]
      ..sort();
    return JpBloomRecord(
      at: t,
      since: starts.isEmpty ? t : starts.first,
      practiceCount: practiceAlive.length,
      examRounds: {
        for (final e in examAlive)
          if (e.lightRow == null) e.roundId,
      }.length,
      lightPasses: passes,
    );
  }

  final out = <JpRowLight>[];
  for (final row in gojuonRows.keys) {
    final kana = jpRowKana(row);
    final size = jpLightExamSize(row);
    // 前一行還沒開，這一行就算全對也不開（只能照順序點亮）。
    final prevLit = out.isEmpty || out.last.lit;
    // 點亮考試：照輪次分組，寫完整輪（あ到這一行、平假片假都考）才算。
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
      if (right == r.length && prevLit) litAt ??= r.last.savedAt;
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
        record: litAt == null ? null : recordAt(litAt),
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
