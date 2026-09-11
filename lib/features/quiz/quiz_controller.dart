import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/history.dart';
import '../../domain/models/quiz.dart';
import '../../domain/question_picker.dart';
import '../../domain/rules_config.dart';
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
/// 紀錄是**每答一題就寫一次**，不是整輪結束才寫。
/// 中途關掉瀏覽器或被系統收掉都不會掉資料，半輪也留得下來。
/// 只有今日用量是整輪做完才計，因為那是「做完一輪」的概念。
class QuizController extends AutoDisposeAsyncNotifier<QuizState> {
  /// 整輪的碼錶。
  final _stopwatch = Stopwatch();

  /// 這一題是什麼時候出現的。用來算每題想了幾秒。
  DateTime? _questionShownAt;

  /// 這一輪的編號，開始時就決定好，之後每題都寫同一個。
  int _round = 0;

  @override
  Future<QuizState> build() async {
    final words = await ref.read(wordRepositoryProvider).loadAll();
    final rules = await ref.read(settingsRepositoryProvider).loadRules();
    final now = ref.read(clockProvider)();

    // 偽裝模式一律點選題：跳出中文輸入法在辦公室很顯眼。
    final effective = ref.read(stealthModeProvider)
        ? rules.copyWith(quizStyle: QuizStyle.tapOnly)
        : rules;

    final questions = QuestionPicker(rules: effective).pick(words, now: now);
    _round = await ref.read(historyRepositoryProvider).nextRoundNumber();
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

  /// 打字題按「不會」。
  ///
  /// 直接判錯並把答案揭開，不要逼人硬打一個錯的上去。
  /// 打不出來跟打錯是同一件事，都算 wrong。
  void giveUp() {
    final s = state.valueOrNull;
    if (s == null || s.judged != null) return;
    state = AsyncData(s.copyWith(judged: false));
  }

  /// 記下這題的結果並前進。最後一題會回傳 true，讓畫面知道該跳結果頁。
  Future<bool> answer(bool correct) async {
    final s = state.valueOrNull;
    if (s == null) return false;

    final now = ref.read(clockProvider)();
    final shown = _questionShownAt ?? now;

    final answered = QuizAnswer(
      question: s.current,
      correct: correct,
      answeredAt: now,
      seconds: now.difference(shown).inSeconds,
      input: s.current.mode == QuizMode.type ? s.input.trim() : '',
    );
    final answers = [...s.answers, answered];

    // 這一題馬上寫進紀錄。中途離開也不會掉。
    final stealth = ref.read(stealthModeProvider);
    await ref
        .read(historyRepositoryProvider)
        .appendAnswer(
          HistoryEntry(
            round: _round,
            word: answered.question.word.word,
            correct: answered.correct,
            at: answered.answeredAt,
            seconds: answered.seconds,
            typed: answered.question.mode == QuizMode.type,
            input: answered.input,
            isReview: answered.question.isReview,
          ),
          stealth: stealth,
        );
    // 對錯次數是從紀錄加總出來的，寫完就要讓單字庫重算。
    ref.read(wordRepositoryProvider).invalidate();

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

    // 每一題在作答當下就寫過了，這裡只補上整輪實際花的時間。
    await ref
        .read(historyRepositoryProvider)
        .finishRound(_round, _stopwatch.elapsed);

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
