import 'models/quiz.dart';
import 'models/word.dart';

/// 把一輪的作答結果換算成新的單字成績。
///
/// 這裡只負責算，不負責存。存是 repository 的事，分開才好測。
abstract final class Scoring {
  /// 套用單一題的結果，回傳更新後的字。
  ///
  /// 答對就 right 加一，答錯就 wrong 加一，兩者都會更新最後受測日期。
  /// 注意：答錯不會把 right 歸零。使用者要看得到「會過但又錯了」這種狀態。
  static Word apply(Word word, {required bool correct, required DateTime at}) {
    return word.copyWith(
      right: correct ? word.right + 1 : word.right,
      wrong: correct ? word.wrong : word.wrong + 1,
      lastTest: at,
    );
  }

  /// 套用一整輪。回傳「單字 id 對應到更新後的字」。
  static Map<int, Word> applyRound(RoundResult result) {
    final updated = <int, Word>{};
    for (final answer in result.answers) {
      final base = updated[answer.question.word.id] ?? answer.question.word;
      updated[base.id] = apply(
        base,
        correct: answer.correct,
        at: result.finishedAt,
      );
    }
    return updated;
  }

  /// 統計三種狀態各有幾個字。首頁和統計頁的數字都從這裡來，不要各算各的。
  static ({int total, int confirmed, int learning, int pending}) summarize(
    Iterable<Word> words,
    int confirmRight,
  ) {
    var confirmed = 0, learning = 0, pending = 0;
    for (final w in words) {
      switch (w.statusWith(confirmRight)) {
        case WordStatus.confirmed:
          confirmed++;
        case WordStatus.learning:
          learning++;
        case WordStatus.pending:
          pending++;
      }
    }
    return (
      total: confirmed + learning + pending,
      confirmed: confirmed,
      learning: learning,
      pending: pending,
    );
  }
}
