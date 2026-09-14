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
    this.roundSize = 10,
    this.pendingPerRound = 7,
    this.masteredPerRound = 1,
    this.typeQuestions = 3,
    this.roundsPerDay = 5,
    this.minutesPerDay = 15,
    this.confirmRight = 3,
    this.recoveryRatio = 7,
    this.quizStyle = QuizStyle.tapOnly,
  });

  /// 一輪總共幾題。
  final int roundSize;

  /// 其中有幾題抽待複習的字，其餘出新字。
  ///
  /// 待複習是「考過但還沒掌握」的字，
  /// 含答錯過的，也含答對過但還沒到門檻的。只有三種狀態，沒有中間類別。
  final int pendingPerRound;

  /// 每輪固定回頭考幾個已經掌握的字。
  ///
  /// 掌握不代表永遠不會忘，隔一陣子碰一次才知道是不是真的還記得。
  final int masteredPerRound;

  /// 真正沒考過的字要出幾題。剩下的位置都給新字。
  int get freshPerRound {
    final fresh = roundSize - pendingPerRound - masteredPerRound;
    return fresh < 0 ? 0 : fresh;
  }

  /// 混合模式下有幾題要打字。其他模式不看這個值。
  final int typeQuestions;

  /// 題型模式。預設只出點選題，打字題要自己去設定裡開。
  final QuizStyle quizStyle;

  /// 這一輪實際要出幾題打字題。出題規則只看這個，不要自己去判斷模式。
  int get effectiveTypeQuestions => switch (quizStyle) {
    QuizStyle.tapOnly => 0,
    QuizStyle.mixed => typeQuestions,
    QuizStyle.typeOnly => roundSize,
  };

  /// 每天最多幾輪。做滿就擋住，這是防止做過頭然後放棄的核心。
  final int roundsPerDay;

  /// 每天最多幾分鐘。跟輪數哪個先到算哪個。
  final int minutesPerDay;

  /// 從沒錯過的字要答對幾次才算掌握。
  /// 調高之後，原本掌握但沒到新門檻的字會自動掉回待複習。
  final int confirmRight;

  /// 錯過的字要翻身，答對次數得是答錯次數的幾倍。
  ///
  /// 預設七倍：錯五次就要答對三十五次才算掌握，整個字總共會被考四十次。
  /// 這個數字刻意訂得重，錯過的字本來就該被多考幾次才能相信。
  final int recoveryRatio;

  RulesConfig copyWith({
    int? roundSize,
    int? pendingPerRound,
    int? masteredPerRound,
    int? typeQuestions,
    int? roundsPerDay,
    int? minutesPerDay,
    int? confirmRight,
    int? recoveryRatio,
    QuizStyle? quizStyle,
  }) {
    return RulesConfig(
      roundSize: roundSize ?? this.roundSize,
      pendingPerRound: pendingPerRound ?? this.pendingPerRound,
      masteredPerRound: masteredPerRound ?? this.masteredPerRound,
      typeQuestions: typeQuestions ?? this.typeQuestions,
      roundsPerDay: roundsPerDay ?? this.roundsPerDay,
      minutesPerDay: minutesPerDay ?? this.minutesPerDay,
      confirmRight: confirmRight ?? this.confirmRight,
      recoveryRatio: recoveryRatio ?? this.recoveryRatio,
      quizStyle: quizStyle ?? this.quizStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'roundSize': roundSize,
    'pendingPerRound': pendingPerRound,
    'masteredPerRound': masteredPerRound,
    'typeQuestions': typeQuestions,
    'quizStyle': quizStyle.name,
    'roundsPerDay': roundsPerDay,
    'minutesPerDay': minutesPerDay,
    'confirmRight': confirmRight,
    'recoveryRatio': recoveryRatio,
  };

  factory RulesConfig.fromJson(Map<String, dynamic> json) {
    const d = RulesConfig();
    // 舊版把一輪拆成 newPerRound 加 reviewPerRound，讀到就併回 roundSize。
    final legacyTotal =
        (json['newPerRound'] as int? ?? 0) +
        (json['reviewPerRound'] as int? ?? 0);

    return RulesConfig(
      roundSize:
          json['roundSize'] as int? ??
          (legacyTotal > 0 ? legacyTotal : d.roundSize),
      pendingPerRound: json['pendingPerRound'] as int? ?? d.pendingPerRound,
      masteredPerRound: json['masteredPerRound'] as int? ?? d.masteredPerRound,
      typeQuestions: json['typeQuestions'] as int? ?? d.typeQuestions,
      quizStyle: QuizStyle.parse(json['quizStyle'] as String?),
      roundsPerDay: json['roundsPerDay'] as int? ?? d.roundsPerDay,
      minutesPerDay: json['minutesPerDay'] as int? ?? d.minutesPerDay,
      confirmRight: json['confirmRight'] as int? ?? d.confirmRight,
      recoveryRatio: json['recoveryRatio'] as int? ?? d.recoveryRatio,
    );
  }
}
