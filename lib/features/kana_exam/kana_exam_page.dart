import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_exam.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/speaker_button.dart';
import '../kana_practice/gojuon_data.dart';
import '../kana_practice/kana_paper.dart';
import 'exam_question_data.dart';
import 'exam_result_dialog.dart';
import 'kana_exam_header_bar.dart';

enum ExamMode { kana, vocab }

/// 50 音和詞彙考試頁面。
///
/// 從考試模式選擇頁（`kana_exam_mode_select_page.dart`）選好模式後才會
/// 進來，[mode] 進來之後不會再變——考卷中途換模式沒有意義，要換模式
/// 就是返回重選（2026-09-21 使用者要求：50 音跟詞彙先各自獨立開發）。
class KanaExamPage extends ConsumerStatefulWidget {
  const KanaExamPage({super.key, required this.mode, this.selectedRows});

  final ExamMode mode;

  /// 50 音考試選題範圍頁（`kana_exam_row_select_page.dart`）帶進來的
  /// 勾選行，只有 [mode] 是 [ExamMode.kana] 時才有意義。null 表示沒有
  /// 經過選題範圍頁（例如直接打網址進來），退回舊的固定題庫。
  final Set<String>? selectedRows;

  @override
  ConsumerState<KanaExamPage> createState() => _KanaExamPageState();
}

class _KanaExamPageState extends ConsumerState<KanaExamPage> {
  late final ExamMode _mode = widget.mode;

  /// 這次考試（進這頁到寫完最後一題）的所有題目共用同一個 id，考試
  /// 紀錄頁靠這個把題目分組成一輪一輪（2026-09-21 使用者要求：要有
  /// 輪次）。「再考一次」（[_restart]）算新的一輪，要重新產生一個。
  String _roundId = DateTime.now().microsecondsSinceEpoch.toString();
  int _currentQuestionIndex = 0;
  int _correctCount = 0;

  // 繪圖相關
  final _strokes = <List<Offset>>[];
  final _strokeTimes = <List<double>>[];
  DateTime? _sessionStart;
  int? _activePointer;

  // 題目列表
  late final List<ExamQuestion> _kanaQuestions = widget.selectedRows != null
      ? _questionsFromRows(widget.selectedRows!)
      : ExamQuestionData.getShuffledKanaQuestions();
  late final List<ExamQuestion> _vocabQuestions =
      ExamQuestionData.getShuffledVocabQuestions();

  List<ExamQuestion> get _currentQuestions =>
      _mode == ExamMode.kana ? _kanaQuestions : _vocabQuestions;

  /// 把選中的行（あ／か／さ……）展開成題目清單。每個字各自擲一次銅板
  /// 決定用平假名還是片假名——兩份表行跟羅馬字一一對應，混著考才是
  /// 真的考熟不熟，不是考認不認得某一種字體（2026-09-21 使用者要求：
  /// 平假還是片假就無所謂）。範圍是選中的行全部都考一輪，不是選了
  /// 範圍還要再抽一次子集。
  static List<ExamQuestion> _questionsFromRows(Set<String> rows) {
    final random = math.Random();
    final result = <ExamQuestion>[];
    for (final row in rows) {
      final hiragana = gojuonRows[row] ?? const [];
      final katakana = gojuonRowsKatakana[row] ?? const [];
      for (var i = 0; i < hiragana.length; i++) {
        final useKatakana = random.nextBool();
        final pick = useKatakana ? katakana[i] : hiragana[i];
        result.add((pick.$2, pick.$1, useKatakana));
      }
    }
    result.shuffle();
    return result;
  }

  bool get _isCompleted => _currentQuestionIndex >= _currentQuestions.length;

  void _clearInk() {
    _strokes.clear();
    _strokeTimes.clear();
    _sessionStart = null;
  }

  double _elapsedMs() =>
      DateTime.now().difference(_sessionStart!).inMicroseconds / 1000;

  void _nextQuestion() {
    setState(() {
      _currentQuestionIndex++;
      _clearInk();
    });
  }

  /// 「提交」——至少要落過筆才能按（按鈕本身在 [_strokes] 是空的時候
  /// 就 disable 掉，見 build 方法，不是按了才跳提示）。還沒有手寫
  /// 辨識，系統不能自動判對錯，彈窗跳出來後要使用者自己核對「你寫的」
  /// 跟「正確答案」，按 ✓／✗ 才真正記錄（2026-09-21 使用者要求：不是
  /// 按提交就等於答對）。
  void _submitAnswer() {
    if (_isCompleted || _strokes.isEmpty) return;
    final question = _currentQuestions[_currentQuestionIndex];
    showExamResultDialog(
      context: context,
      userStrokes: List.of(_strokes),
      correctAnswer: question.$2,
      knownIncorrect: false,
      isKatakana: question.$3,
      onFinish: (isCorrect) => _saveAndAdvance(question, isCorrect: isCorrect),
    );
  }

  /// 「不會，看答案」——寫不出來時不用硬湊，直接跳過本題、公布正確
  /// 答案，記錄成不會（2026-09-21 使用者要求：要有看答案的選項，
  /// 按下去等同按不會）。沒寫任何一筆也能按，跟「提交」不一樣，而且
  /// 結果已經確定，不用再讓使用者自評一次。
  void _markAsUnknown() {
    if (_isCompleted) return;
    final question = _currentQuestions[_currentQuestionIndex];
    showExamResultDialog(
      context: context,
      userStrokes: List.of(_strokes),
      correctAnswer: question.$2,
      knownIncorrect: true,
      isKatakana: question.$3,
      onFinish: (isCorrect) => _saveAndAdvance(question, isCorrect: isCorrect),
    );
  }

  /// 使用者在結果彈窗裡確認完（自評或看完不會的答案）才真的存檔、
  /// 進下一題——「提交」按下去那一刻還不知道對錯，不能提前存。
  Future<void> _saveAndAdvance(
    ExamQuestion question, {
    required bool isCorrect,
  }) async {
    if (isCorrect) {
      setState(() {
        _correctCount++;
      });
    }

    final now = DateTime.now();
    final entry = KanaExamEntry(
      id: now.microsecondsSinceEpoch.toString(),
      roundId: _roundId,
      kana: question.$2,
      romaji: question.$1,
      isCorrect: isCorrect,
      examType: _mode == ExamMode.kana ? 'kana' : 'vocab',
      savedAt: now,
      strokes: [
        for (var i = 0; i < _strokes.length; i++)
          [
            for (var j = 0; j < _strokes[i].length; j++)
              (_strokes[i][j].dx, _strokes[i][j].dy, _strokeTimes[i][j]),
          ],
      ],
    );

    final repo = ref.read(kanaExamRepositoryProvider);
    await repo.add(entry);

    if (!mounted) return;
    _nextQuestion();
  }

  Widget _buildPaper(BoxConstraints constraints) {
    final box = constraints.biggest;
    Offset normalize(Offset local) =>
        Offset(local.dx / box.width, local.dy / box.height);

    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: PaperGridPainter()),
        Listener(
          onPointerDown: (e) {
            if (_activePointer != null) return;
            _activePointer = e.pointer;
            setState(() {
              _sessionStart ??= DateTime.now();
              _strokes.add([normalize(e.localPosition)]);
              _strokeTimes.add([_elapsedMs()]);
            });
          },
          onPointerMove: (e) {
            if (e.pointer != _activePointer) return;
            setState(() {
              _strokes.last.add(normalize(e.localPosition));
              _strokeTimes.last.add(_elapsedMs());
            });
          },
          onPointerUp: (e) {
            if (e.pointer != _activePointer) return;
            _activePointer = null;
          },
          onPointerCancel: (e) {
            if (e.pointer != _activePointer) return;
            _activePointer = null;
          },
          // 筆畫粗細照畫布邊長抓比例算，跟 kana_practice_page.dart
          // 手寫畫布同一套公式（2026-09-21 使用者回饋：預覽比較粗、
          // 比較好看，手寫時也想要那麼粗，而且要按畫布比例算）。
          child: CustomPaint(
            painter: InkPainter(
              strokes: _strokes,
              strokeWidth: inkStrokeWidth(box.shortestSide),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleted) {
      return _buildCompletedPage();
    }

    final question = _currentQuestions[_currentQuestionIndex];

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                KanaExamHeaderBar(
                  title: _mode == ExamMode.kana ? '📝 50 音考試' : '📝 詞彙考試',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.jpAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Text(
                      '${_currentQuestionIndex + 1} / ${_currentQuestions.length}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.jpAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  child: LinearProgressIndicator(
                    value: _currentQuestionIndex / _currentQuestions.length,
                    minHeight: 5,
                    backgroundColor: AppColors.glassFill,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.jpAccent,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_mode == ExamMode.kana) ...[
                        // 題目只有羅馬字，光看羅馬字分不出這題要寫平假名
                        // 還是片假名（兩種字體的羅馬拼法一模一樣），所以
                        // 一定要有這個標籤，還要跟平假名用不同顏色，
                        // 不然容易看錯題目、寫錯字體（2026-09-21 使用者
                        // 要求）。
                        Center(child: _ScriptBadge(isKatakana: question.$3)),
                      ],
                      const SizedBox(height: Gap.md),
                      if (_mode == ExamMode.kana)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: question.$3
                                    ? AppColors.accent
                                    : AppColors.jpAccent,
                                shape: BoxShape.circle,
                              ),
                              child: SpeakerButton(
                                text: question.$2,
                                size: 26,
                                color: question.$3
                                    ? AppColors.bgDeep
                                    : AppColors.jpAccentInk,
                              ),
                            ),
                            const SizedBox(width: Gap.lg),
                            Text(
                              question.$1,
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                color: question.$3
                                    ? AppColors.accent
                                    : AppColors.ink,
                                height: 1,
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.jpAccent.withValues(
                                  alpha: 0.12,
                                ),
                                border: Border.all(
                                  color: AppColors.jpAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(Radii.card),
                              ),
                              child: Text(
                                question.$1,
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: Gap.md),
                            SpeakerButton(
                              text: question.$2,
                              size: 24,
                              color: AppColors.jpAccent,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: paperColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      _buildPaper(constraints),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.md),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _clearInk,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('清除'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: _markAsUnknown,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                                side: BorderSide(color: AppColors.glassEdge),
                              ),
                              child: const Text('不會，看答案'),
                            ),
                            const SizedBox(width: Gap.sm),
                            ElevatedButton(
                              // 沒下筆不能按——不是按了才彈提示，直接
                              // disable 才不會讓人以為按了有反應
                              // （2026-09-21 使用者要求：0 筆畫不可以
                              // 點提交）。
                              onPressed: _strokes.isEmpty
                                  ? null
                                  : _submitAnswer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.jpAccent,
                                foregroundColor: AppColors.jpAccentInk,
                                disabledBackgroundColor: AppColors.glassFill,
                                disabledForegroundColor: AppColors.ink3,
                              ),
                              child: const Text('提交'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _restart() {
    setState(() {
      _currentQuestionIndex = 0;
      _correctCount = 0;
      _roundId = DateTime.now().microsecondsSinceEpoch.toString();
      _clearInk();
      if (_mode == ExamMode.kana) {
        _kanaQuestions
          ..clear()
          ..addAll(
            widget.selectedRows != null
                ? _questionsFromRows(widget.selectedRows!)
                : ExamQuestionData.getShuffledKanaQuestions(),
          );
      } else {
        _vocabQuestions
          ..clear()
          ..addAll(ExamQuestionData.getShuffledVocabQuestions());
      }
    });
  }

  Widget _buildCompletedPage() {
    final total = _currentQuestions.length;
    final accuracy = total == 0 ? 0 : (_correctCount / total * 100).round();

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: _mode == ExamMode.kana ? '50 音考試結果' : '詞彙考試結果',
                ),
                const Spacer(),
                Text(
                  _mode == ExamMode.kana ? '🌸 50 音考試完成！' : '🌸 詞彙考試完成！',
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gap.xl),
                // 結算圈圈跟百分比數字一起從 0 動態跑到最終正確率（例如
                // 40% 就從 0 跑到 40），不是一開場就直接靜態顯示結果
                // （2026-09-22 使用者要求）。TweenAnimationBuilder 一進
                // 這個畫面就自動跑一次，不用自己管 AnimationController
                // 的生命週期。
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: total == 0 ? 0 : _correctCount / total),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    final animatedAccuracy = (value * 100).round();
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 148,
                          height: 148,
                          child: CircularProgressIndicator(
                            value: value,
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                            backgroundColor: AppColors.glassFill,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.jpAccent,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$animatedAccuracy%',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: AppColors.jpAccent,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_correctCount / $total 題',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.ink3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  accuracy >= 80 ? '寫得很扎實，繼續保持' : '多練幾次，肌肉記憶會自己長出來',
                  style: TextStyle(fontSize: 14, color: AppColors.ink2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gap.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _restart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.jpAccent,
                      foregroundColor: AppColors.jpAccentInk,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.button),
                      ),
                    ),
                    child: const Text(
                      '再考一次',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ink2,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('返回模式選擇'),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 標出這題要寫平假名還是片假名的小標籤。顏色故意跟平假名（樱色
/// [AppColors.jpAccent]）用不一樣的顏色（[AppColors.accent] 藍色系），
/// 兩色反差夠大，一眼就能分出這題是哪一種，不用細看文字
/// （2026-09-21 使用者要求：平跟片不同顏色，不然容易看錯題目）。
class _ScriptBadge extends StatelessWidget {
  const _ScriptBadge({required this.isKatakana});

  final bool isKatakana;

  @override
  Widget build(BuildContext context) {
    final color = isKatakana ? AppColors.accent : AppColors.jpAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isKatakana ? '片假名' : '平假名',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
