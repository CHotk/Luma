import 'models/word.dart';

/// 單字狀態的統計。
///
/// 對錯次數的累加不在這裡：那是從作答紀錄加總出來的，
/// 由 HistoryRepository 負責，這樣兩邊出的題才能合併而不互相覆蓋。
abstract final class Scoring {
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
