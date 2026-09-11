/// 學習規則的參數集中在這裡。
///
/// 使用者隨時可能想調每輪幾題、上限幾輪、門檻幾次，
/// 所以這些數字絕對不准散落在畫面或邏輯裡。
/// 設定頁改的是覆寫後的 [RulesConfig] 實例，不是改這個檔的預設值。
class RulesConfig {
  const RulesConfig({
    this.newPerRound = 10,
    this.reviewPerRound = 1,
    this.typeQuestions = 3,
    this.roundsPerDay = 5,
    this.minutesPerDay = 15,
    this.confirmRight = 2,
  });

  /// 每輪的新字數量。
  final int newPerRound;

  /// 每輪回考幾個已經答對過的舊字。
  /// 用來驗證是真的會還是猜中的，連續答對兩次才算真的會。
  final int reviewPerRound;

  /// 一輪之中有幾題要打字（中翻英）。其餘是點「會 / 不會」。
  final int typeQuestions;

  /// 每天最多幾輪。做滿就擋住，這是防止做過頭然後放棄的核心。
  final int roundsPerDay;

  /// 每天最多幾分鐘。跟輪數哪個先到算哪個。
  final int minutesPerDay;

  /// 算「真的會」的門檻：答對次數要達到這個值，而且從沒答錯過。
  /// 調高之後，原本已確認但沒到新門檻的字會自動掉回未確認。
  final int confirmRight;

  int get questionsPerRound => newPerRound + reviewPerRound;

  RulesConfig copyWith({
    int? newPerRound,
    int? reviewPerRound,
    int? typeQuestions,
    int? roundsPerDay,
    int? minutesPerDay,
    int? confirmRight,
  }) {
    return RulesConfig(
      newPerRound: newPerRound ?? this.newPerRound,
      reviewPerRound: reviewPerRound ?? this.reviewPerRound,
      typeQuestions: typeQuestions ?? this.typeQuestions,
      roundsPerDay: roundsPerDay ?? this.roundsPerDay,
      minutesPerDay: minutesPerDay ?? this.minutesPerDay,
      confirmRight: confirmRight ?? this.confirmRight,
    );
  }

  Map<String, dynamic> toJson() => {
    'newPerRound': newPerRound,
    'reviewPerRound': reviewPerRound,
    'typeQuestions': typeQuestions,
    'roundsPerDay': roundsPerDay,
    'minutesPerDay': minutesPerDay,
    'confirmRight': confirmRight,
  };

  factory RulesConfig.fromJson(Map<String, dynamic> json) {
    const d = RulesConfig();
    return RulesConfig(
      newPerRound: json['newPerRound'] as int? ?? d.newPerRound,
      reviewPerRound: json['reviewPerRound'] as int? ?? d.reviewPerRound,
      typeQuestions: json['typeQuestions'] as int? ?? d.typeQuestions,
      roundsPerDay: json['roundsPerDay'] as int? ?? d.roundsPerDay,
      minutesPerDay: json['minutesPerDay'] as int? ?? d.minutesPerDay,
      confirmRight: json['confirmRight'] as int? ?? d.confirmRight,
    );
  }
}
