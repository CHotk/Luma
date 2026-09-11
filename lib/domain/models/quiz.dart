import 'word.dart';

/// 題型。
enum QuizMode {
  /// 英翻中，看英文想中文，點卡片翻面後自己按會或不會。
  tap,

  /// 中翻英，看中文把英文打出來。這是唯一測得到拼寫的題型。
  type,
}

/// 一題。單字加上這題要用哪種題型。
class QuizQuestion {
  const QuizQuestion({
    required this.word,
    required this.mode,
    required this.isReview,
  });

  final Word word;
  final QuizMode mode;

  /// 是不是回考的舊字。結果頁要把新字和回考分開算。
  final bool isReview;
}

/// 一題的作答結果。
///
/// 時間記到每一題，不只記每一輪。
/// 想很久才答對，跟一秒就答對，熟練度是兩回事，
/// 這個差別要留下來，之後才分析得出哪些字其實還不熟。
class QuizAnswer {
  const QuizAnswer({
    required this.question,
    required this.correct,
    required this.answeredAt,
    required this.seconds,
  });

  final QuizQuestion question;
  final bool correct;

  /// 按下去的那一刻。
  final DateTime answeredAt;

  /// 這題想了幾秒，從題目出現算到按下去。
  final int seconds;
}

/// 一輪的成績。只存結果，不存過程。
class RoundResult {
  const RoundResult({
    required this.answers,
    required this.elapsed,
    required this.finishedAt,
  });

  final List<QuizAnswer> answers;
  final Duration elapsed;
  final DateTime finishedAt;

  int get total => answers.length;
  int get rightCount => answers.where((a) => a.correct).length;

  /// 答錯和沒答出來的字。
  ///
  /// 結果頁一定要把這些全部列出來並附中文，一個都不能漏，
  /// 這是使用者明確要求過的，不要為了畫面好看而截斷。
  List<QuizAnswer> get missed => answers.where((a) => !a.correct).toList();

  int countOf({required bool review, required bool correctOnly}) => answers
      .where((a) => a.question.isReview == review && (!correctOnly || a.correct))
      .length;
}
