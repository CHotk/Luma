/// 一題的作答紀錄。
///
/// 這份紀錄是**只增不改**的，跟專案裡 history.txt 的規矩一樣。
/// 單字上的累計對錯次數必須等於這裡的加總，兩邊對不起來就是有 bug。
///
/// 沒有輪次編號欄位（2026-09-17 決定拿掉）：同一輪的所有題目共用同一個
/// [at] 時間戳（對話端整批寫入時只蓋一次系統時間，App 端也改成一輪
/// 開始時只取一次 `DateTime.now()`，見 `quiz_controller.dart`），兩個
/// 獨立來源產生的真實時刻幾乎不可能重複，靠 [at] 識別／分組一輪，
/// 不需要再靠額外配發的編號、也不需要維持任何人工的編號分帶規則。
class HistoryEntry {
  const HistoryEntry({
    required this.word,
    required this.correct,
    required this.at,
    this.seconds = 0,
    this.typed = false,
    this.input = '',
    this.isReview = false,
  });

  final String word;
  final bool correct;

  /// 按下答案的那一刻，精確到秒。
  final DateTime at;

  /// 這題想了幾秒。
  /// 從 history.txt 匯進來的舊紀錄沒有這個資料，一律是 0。
  final int seconds;

  /// 這題是不是打字題。點選題只按會或不會，打字題才有輸入內容。
  final bool typed;

  /// 打字題實際打了什麼。
  ///
  /// 留著是為了以後翻得出「當初是拼錯哪個字母」，
  /// 光知道答錯沒有用，要知道錯在哪裡才學得到東西。
  final String input;

  /// 這題是不是回考的舊字。
  final bool isReview;

  Map<String, dynamic> toJson() => {
    'word': word,
    'correct': correct,
    'at': at.toIso8601String(),
    'seconds': seconds,
    'typed': typed,
    'input': input,
    'isReview': isReview,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    word: json['word'] as String,
    correct: json['correct'] as bool,
    at: DateTime.parse(json['at'] as String),
    seconds: json['seconds'] as int? ?? 0,
    typed: json['typed'] as bool? ?? false,
    input: json['input'] as String? ?? '',
    isReview: json['isReview'] as bool? ?? false,
  );
}

/// 一輪的摘要。作答紀錄存不下的東西放這裡，例如花了多久。
///
/// 沒有輪次編號欄位：[at] 本身就是這一輪的識別碼——同一輪的所有
/// [HistoryEntry] 共用同一個 [at]，這裡的 [at] 就是那個共用值。
class RoundLog {
  const RoundLog({
    required this.at,
    required this.seconds,
    required this.total,
    required this.right,
    required this.stealth,
  });

  final DateTime at;
  final int seconds;
  final int total;
  final int right;

  /// 是不是在偽裝模式做的。之後想看「上班偷學了多少」就靠這個欄位。
  final bool stealth;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'seconds': seconds,
    'total': total,
    'right': right,
    'stealth': stealth,
  };

  factory RoundLog.fromJson(Map<String, dynamic> json) => RoundLog(
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
