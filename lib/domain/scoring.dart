import 'models/word.dart';
import 'rules_config.dart';

/// 單字狀態的統計。
///
/// 對錯次數的累加不在這裡：那是從作答紀錄加總出來的，
/// 由 HistoryRepository 負責，這樣兩邊出的題才能合併而不互相覆蓋。
abstract final class Scoring {
  /// 每種狀態各有幾個字。沒有的狀態也會是 0，畫面不用自己補。
  static Map<WordStatus, int> countByStatus(
    Iterable<Word> words,
    RulesConfig rules,
  ) {
    final counts = {for (final s in WordStatus.values) s: 0};
    for (final w in words) {
      final status = w.statusWith(rules);
      counts[status] = counts[status]! + 1;
    }
    return counts;
  }

  /// 首頁要的三個數字。其餘地方請直接用 [countByStatus]。
  static ({int total, int confirmed, int pending}) summarize(
    Iterable<Word> words,
    RulesConfig rules,
  ) {
    final counts = countByStatus(words, rules);
    return (
      total: counts.values.fold(0, (sum, n) => sum + n),
      confirmed: counts[WordStatus.confirmed] ?? 0,
      pending: counts[WordStatus.pending] ?? 0,
    );
  }
}
