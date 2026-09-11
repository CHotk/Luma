/// 一輪裡要出哪些題型。
enum QuizStyle {
  /// 全部都是英翻中的點選題。最快，一輪兩分鐘結束。
  tapOnly('只點選', '看英文想中文，按會或不會'),

  /// 大部分點選，少數幾題要打字。
  mixed('混合', '多數點選，少數幾題中翻英要打字'),

  /// 全部都要打字。拼寫練得最扎實，但很容易做兩天就放棄。
  typeOnly('只打字', '全部中翻英，每題都要打出來');

  const QuizStyle(this.label, this.description);
  final String label;
  final String description;

  static QuizStyle parse(String? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return QuizStyle.tapOnly;
  }
}

/// 學習規則的參數集中在這裡。
///
/// 使用者隨時可能想調每輪幾題、上限幾輪、門檻幾次，
/// 所以這些數字絕對不准散落在畫面或邏輯裡。
/// 設定頁改的是覆寫後的 [RulesConfig] 實例，不是改這個檔的預設值。
class RulesConfig {
  const RulesConfig({
    this.newPerRound = 10,
    this.pendingPerRound = 2,
    this.reviewPerRound = 1,
    this.typeQuestions = 3,
    this.roundsPerDay = 5,
    this.minutesPerDay = 15,
    this.confirmRight = 3,
    this.quizStyle = QuizStyle.tapOnly,
  });

  /// 每輪這一段有幾個題目。它不是「全新的字」的數量，
  /// 其中有 [pendingPerRound] 個會改抽待複習的字。
  final int newPerRound;

  /// 上面那幾題裡面，有幾題要抽答錯過又還沒答對的字。
  /// 錯過的字不主動回來考，它就只會一直躺在清單裡。
  final int pendingPerRound;

  /// 真正沒考過的字要出幾題。
  int get freshPerRound {
    final fresh = newPerRound - pendingPerRound;
    return fresh < 0 ? 0 : fresh;
  }

  /// 每輪回考幾個已經答對過的舊字。
  /// 用來驗證是真的會還是猜中的，連續答對兩次才算真的會。
  final int reviewPerRound;

  /// 混合模式下有幾題要打字。其他模式不看這個值。
  final int typeQuestions;

  /// 題型模式。預設只出點選題，打字題要自己去設定裡開。
  final QuizStyle quizStyle;

  /// 這一輪實際要出幾題打字題。出題規則只看這個，不要自己去判斷模式。
  int get effectiveTypeQuestions => switch (quizStyle) {
    QuizStyle.tapOnly => 0,
    QuizStyle.mixed => typeQuestions,
    QuizStyle.typeOnly => questionsPerRound,
  };

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
    int? pendingPerRound,
    int? reviewPerRound,
    int? typeQuestions,
    int? roundsPerDay,
    int? minutesPerDay,
    int? confirmRight,
    QuizStyle? quizStyle,
  }) {
    return RulesConfig(
      newPerRound: newPerRound ?? this.newPerRound,
      pendingPerRound: pendingPerRound ?? this.pendingPerRound,
      reviewPerRound: reviewPerRound ?? this.reviewPerRound,
      typeQuestions: typeQuestions ?? this.typeQuestions,
      roundsPerDay: roundsPerDay ?? this.roundsPerDay,
      minutesPerDay: minutesPerDay ?? this.minutesPerDay,
      confirmRight: confirmRight ?? this.confirmRight,
      quizStyle: quizStyle ?? this.quizStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'newPerRound': newPerRound,
    'pendingPerRound': pendingPerRound,
    'reviewPerRound': reviewPerRound,
    'typeQuestions': typeQuestions,
    'quizStyle': quizStyle.name,
    'roundsPerDay': roundsPerDay,
    'minutesPerDay': minutesPerDay,
    'confirmRight': confirmRight,
  };

  factory RulesConfig.fromJson(Map<String, dynamic> json) {
    const d = RulesConfig();
    return RulesConfig(
      newPerRound: json['newPerRound'] as int? ?? d.newPerRound,
      pendingPerRound: json['pendingPerRound'] as int? ?? d.pendingPerRound,
      reviewPerRound: json['reviewPerRound'] as int? ?? d.reviewPerRound,
      typeQuestions: json['typeQuestions'] as int? ?? d.typeQuestions,
      quizStyle: QuizStyle.parse(json['quizStyle'] as String?),
      roundsPerDay: json['roundsPerDay'] as int? ?? d.roundsPerDay,
      minutesPerDay: json['minutesPerDay'] as int? ?? d.minutesPerDay,
      confirmRight: json['confirmRight'] as int? ?? d.confirmRight,
    );
  }
}
