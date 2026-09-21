import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_exam.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/speaker_button.dart';
import '../kana_practice/kana_paper.dart';
import 'exam_question_data.dart';
import 'exam_result_dialog.dart';

enum ExamMode { kana, vocab }

/// 50 音和詞彙考試頁面。
///
/// 從考試模式選擇頁（`kana_exam_mode_select_page.dart`）選好模式後才會
/// 進來，[mode] 進來之後不會再變——考卷中途換模式沒有意義，要換模式
/// 就是返回重選（2026-09-21 使用者要求：50 音跟詞彙先各自獨立開發）。
class KanaExamPage extends ConsumerStatefulWidget {
  const KanaExamPage({super.key, required this.mode});

  final ExamMode mode;

  @override
  ConsumerState<KanaExamPage> createState() => _KanaExamPageState();
}

class _KanaExamPageState extends ConsumerState<KanaExamPage> {
  late final ExamMode _mode = widget.mode;
  int _currentQuestionIndex = 0;
  int _correctCount = 0;

  // 繪圖相關
  final _strokes = <List<Offset>>[];
  final _strokeTimes = <List<double>>[];
  DateTime? _sessionStart;
  int? _activePointer;

  // 題目列表
  late final List<(String, String)> _kanaQuestions =
      ExamQuestionData.getShuffledKanaQuestions();
  late final List<(String, String)> _vocabQuestions =
      ExamQuestionData.getShuffledVocabQuestions();

  List<(String, String)> get _currentQuestions =>
      _mode == ExamMode.kana ? _kanaQuestions : _vocabQuestions;

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

  Future<void> _submitAnswer() async {
    if (_isCompleted) return;

    // 沒寫任何一筆就送出，不能算「答對」——沒人批閱不代表可以什麼都
    // 不寫就過關，至少要落過筆（2026-09-21 使用者要求考試要真的記錄
    // 練習成果，空白紙不算一次練習）。
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先寫再提交')));
      return;
    }

    final question = _currentQuestions[_currentQuestionIndex];
    final correctAnswer = question.$2;
    // TODO: 根據筆畫相似度判斷是否答對，現在只要有落筆就算通過——
    // 沒有批閱者，考試的重點是逼自己回想寫出來，不是自動判對錯
    // （2026-09-21 使用者：反正也沒人批閱）。
    final isCorrect = true;

    if (isCorrect) {
      setState(() {
        _correctCount++;
      });
    }

    // 建立 KanaExamEntry 並存檔
    final now = DateTime.now();
    final entry = KanaExamEntry(
      id: now.microsecondsSinceEpoch.toString(),
      kana: correctAnswer,
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

    // 儲存到 repository
    final repo = ref.read(kanaExamRepositoryProvider);
    await repo.add(entry);

    if (!mounted) return;

    // 顯示結果彈窗，直接重播使用者剛寫的筆畫給他自己核對，還沒有手寫
    // 辨識、不能假裝認得出寫的是什麼字（TODO：接上筆畫比對後這裡
    // 才顯示真正辨識出的字，而不是原始筆畫）。
    showExamResultDialog(
      context: context,
      isCorrect: isCorrect,
      userStrokes: List.of(_strokes),
      correctAnswer: correctAnswer,
      onNext: _nextQuestion,
    );
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
          child: CustomPaint(painter: InkPainter(strokes: _strokes)),
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
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      _mode == ExamMode.kana ? '📝 50 音考試' : '📝 詞彙考試',
                      style: AppText.title,
                    ),
                    const Spacer(),
                    Container(
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
                  ],
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
                      Text(
                        _mode == ExamMode.kana ? '聽發音，寫出平假名' : '看漢字，寫出平假名讀音',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink3,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: Gap.md),
                      if (_mode == ExamMode.kana)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: AppColors.jpAccent,
                                shape: BoxShape.circle,
                              ),
                              child: SpeakerButton(
                                text: question.$2,
                                size: 26,
                                color: AppColors.jpAccentInk,
                              ),
                            ),
                            const SizedBox(width: Gap.lg),
                            Text(
                              question.$1,
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
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
                            ElevatedButton(
                              onPressed: _submitAnswer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.jpAccent,
                                foregroundColor: AppColors.jpAccentInk,
                              ),
                              child: const Text('提交答案'),
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
      _clearInk();
      if (_mode == ExamMode.kana) {
        _kanaQuestions
          ..clear()
          ..addAll(ExamQuestionData.getShuffledKanaQuestions());
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _mode == ExamMode.kana ? '🌸 50 音考試完成！' : '🌸 詞彙考試完成！',
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gap.xl),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : _correctCount / total,
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
                          '$accuracy%',
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
                          style: TextStyle(fontSize: 13, color: AppColors.ink3),
                        ),
                      ],
                    ),
                  ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
