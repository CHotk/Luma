import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/quiz.dart';
import '../../domain/question_picker.dart';
import '../../domain/spell_judge.dart';

/// 測驗進行中的狀態。
class QuizState {
  const QuizState({
    required this.questions,
    required this.index,
    required this.answers,
    this.revealed = false,
    this.input = '',
    this.judged,
  });

  final List<QuizQuestion> questions;
  final int index;
  final List<QuizAnswer> answers;

  /// 點選題翻面了沒。沒翻面不准按會或不會，避免手滑亂按。
  final bool revealed;

  /// 打字題目前輸入的內容。
  final String input;

  /// 打字題送出後的判定結果。null 代表還沒送出。
  final bool? judged;

  QuizQuestion get current => questions[index];
  bool get isLast => index >= questions.length - 1;
  double get progress => (index + 1) / questions.length;

  QuizState copyWith({
    int? index,
    List<QuizAnswer>? answers,
    bool? revealed,
    String? input,
    bool? judged,
    bool clearJudged = false,
  }) {
    return QuizState(
      questions: questions,
      index: index ?? this.index,
      answers: answers ?? this.answers,
      revealed: revealed ?? this.revealed,
      input: input ?? this.input,
      judged: clearJudged ? null : (judged ?? this.judged),
    );
  }
}

final quizControllerProvider =
    AutoDisposeAsyncNotifierProvider<QuizController, QuizState>(
      QuizController.new,
    );

/// 一輪測驗的流程。
///
/// 只管「這一輪」的事。成績寫回單字庫和今日用量是在 [finish] 一次做完，
/// 中途離開就不算，這是刻意的：半途而廢不該留下紀錄。
class QuizController extends AutoDisposeAsyncNotifier<QuizState> {
  /// 整輪的碼錶。
  final _stopwatch = Stopwatch();

  /// 這一題是什麼時候出現的。用來算每題想了幾秒。
  DateTime? _questionShownAt;

  @override
  Future<QuizState> build() async {
    final words = await ref.read(wordRepositoryProvider).loadAll();
    final rules = await ref.read(settingsRepositoryProvider).loadRules();
    final now = ref.read(clockProvider)();

    // 偽裝模式全部用點選題，不出打字題。
    final effective = ref.read(stealthModeProvider)
        ? rules.copyWith(typeQuestions: 0)
        : rules;

    final questions = QuestionPicker(rules: effective).pick(words, now: now);
    _stopwatch
      ..reset()
      ..start();
    _questionShownAt = now;

    // 離開測驗頁時把碼錶停掉，不然背景會一直跑。
    ref.onDispose(_stopwatch.stop);

    return QuizState(questions: questions, index: 0, answers: const []);
  }

  /// 點選題翻面。可以來回翻，看了中文想再確認一次英文很正常。
  void toggleReveal() {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(revealed: !s.revealed));
  }

  void updateInput(String value) {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(input: value));
  }

  /// 打字題送出。判定規則在 [SpellJudge]，這裡不自己比字串。
  void submitTyped() {
    final s = state.valueOrNull;
    if (s == null || s.judged != null) return;
    final correct = SpellJudge.isCorrect(
      input: s.input,
      answer: s.current.word.word,
    );
    state = AsyncData(s.copyWith(judged: correct));
  }

  /// 記下這題的結果並前進。最後一題會回傳 true，讓畫面知道該跳結果頁。
  Future<bool> answer(bool correct) async {
    final s = state.valueOrNull;
    if (s == null) return false;

    final now = ref.read(clockProvider)();
    final shown = _questionShownAt ?? now;

    final answers = [
      ...s.answers,
      QuizAnswer(
        question: s.current,
        correct: correct,
        answeredAt: now,
        seconds: now.difference(shown).inSeconds,
      ),
    ];

    if (s.isLast) {
      await _finish(answers);
      return true;
    }

    // 下一題的計時從這一刻重新起算。
    _questionShownAt = now;
    state = AsyncData(
      s.copyWith(
        index: s.index + 1,
        answers: answers,
        revealed: false,
        input: '',
        clearJudged: true,
      ),
    );
    return false;
  }

  /// 一輪結束：寫回成績、累加今日用量、把結果交給結果頁。
  Future<void> _finish(List<QuizAnswer> answers) async {
    _stopwatch.stop();
    final now = ref.read(clockProvider)();
    final result = RoundResult(
      answers: answers,
      elapsed: _stopwatch.elapsed,
      finishedAt: now,
    );

    final stealth = ref.read(stealthModeProvider);

    // 先寫紀錄，再讓單字庫重新加總。順序不能反，
    // 因為對錯次數是從紀錄算出來的，不是自己累加的。
    await ref
        .read(historyRepositoryProvider)
        .appendRound(result, stealth: stealth);
    ref.read(wordRepositoryProvider).invalidate();

    // 偽裝模式不計入今日用量，也就不受每日上限管（使用者 2026-09-11 決定）。
    // 理由是上班很無聊，那段時間本來就想一直背。
    // 代價是首頁那個環只反映一般模式的份量，總量要看總紀錄頁。
    if (stealth) return;

    final settings = ref.read(settingsRepositoryProvider);
    final usage = await settings.loadUsage(now);
    await settings.saveUsage(
      usage.copyWith(
        roundsDone: usage.roundsDone + 1,
        practiceSeconds: usage.practiceSeconds + _stopwatch.elapsed.inSeconds,
      ),
    );

    ref.read(lastRoundProvider.notifier).state = result;
  }
}
