/// 一題的作答紀錄。
///
/// 這份紀錄是**只增不改**的，跟專案裡 history.txt 的規矩一樣。
/// 單字上的累計對錯次數必須等於這裡的加總，兩邊對不起來就是有 bug。
class HistoryEntry {
  const HistoryEntry({
    required this.round,
    required this.word,
    required this.correct,
    required this.at,
  });

  /// 輪次編號，從 1 開始連號。
  final int round;
  final String word;
  final bool correct;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'round': round,
    'word': word,
    'correct': correct,
    'at': at.toIso8601String(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    round: json['round'] as int,
    word: json['word'] as String,
    correct: json['correct'] as bool,
    at: DateTime.parse(json['at'] as String),
  );
}

/// 一輪的摘要。作答紀錄存不下的東西放這裡，例如花了多久。
class RoundLog {
  const RoundLog({
    required this.round,
    required this.at,
    required this.seconds,
    required this.total,
    required this.right,
    required this.stealth,
  });

  final int round;
  final DateTime at;
  final int seconds;
  final int total;
  final int right;

  /// 是不是在偽裝模式做的。之後想看「上班偷學了多少」就靠這個欄位。
  final bool stealth;

  Map<String, dynamic> toJson() => {
    'round': round,
    'at': at.toIso8601String(),
    'seconds': seconds,
    'total': total,
    'right': right,
    'stealth': stealth,
  };

  factory RoundLog.fromJson(Map<String, dynamic> json) => RoundLog(
    round: json['round'] as int,
    at: DateTime.parse(json['at'] as String),
    seconds: json['seconds'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    right: json['right'] as int? ?? 0,
    stealth: json['stealth'] as bool? ?? false,
  );
}

/// 從第一天到現在的總計。全部由紀錄算出來，不另外存一份，
/// 這樣就不會有「總計跟明細對不起來」的問題。
class LifetimeStats {
  const LifetimeStats({
    required this.rounds,
    required this.questions,
    required this.right,
    required this.wrong,
    required this.seconds,
    required this.activeDays,
    required this.stealthRounds,
    this.since,
  });

  final int rounds;
  final int questions;
  final int right;
  final int wrong;
  final int seconds;

  /// 有做題的天數。不是從第一天算到今天，是真的有開來用的天數。
  final int activeDays;
  final int stealthRounds;
  final DateTime? since;

  static const empty = LifetimeStats(
    rounds: 0,
    questions: 0,
    right: 0,
    wrong: 0,
    seconds: 0,
    activeDays: 0,
    stealthRounds: 0,
  );

  /// 正確率。沒答過題時回 0，不要讓畫面去處理除以零。
  double get accuracy => questions == 0 ? 0 : right / questions;
}
