/// 單字的學習階段，對應題庫檔的最後一欄。
enum WordLevel {
  elementary('國小'),
  junior('國中');

  const WordLevel(this.label);
  final String label;

  static WordLevel parse(String raw) =>
      raw.trim() == '國中' ? WordLevel.junior : WordLevel.elementary;
}

/// 一個字的三種狀態。判定規則寫在 [Word.statusWith]，不要在別處重算。
enum WordStatus {
  /// 答對次數達到門檻，而且從沒答錯過。
  confirmed('已確認'),

  /// 會，但還沒到門檻，或曾經答錯過。
  learning('未確認'),

  /// 還沒答對過。這就是待複習清單。
  pending('待複習');

  const WordStatus(this.label);
  final String label;
}

/// 一個單字，以及它的累計成績。
///
/// 這是不可變物件，任何變動都用 [copyWith] 產生新的實例，
/// 這樣測試時比對前後狀態才不會踩到共用參考。
class Word {
  const Word({
    required this.id,
    required this.word,
    required this.pos,
    required this.zh,
    required this.level,
    this.right = 0,
    this.wrong = 0,
    this.lastTest,
  });

  final int id;
  final String word;
  final String pos;
  final String zh;
  final WordLevel level;

  /// 累計答對次數。
  final int right;

  /// 累計答錯次數。答錯的字永遠留著，這一欄就是待複習清單的依據。
  final int wrong;

  /// 最後一次被考的日期。回考舊字時挑最舊的優先。
  final DateTime? lastTest;

  /// 從沒被考過的字。出新題時只從這裡面挑。
  bool get isUntested => right == 0 && wrong == 0;

  /// 狀態要帶著門檻一起算，因為門檻是使用者可調的。
  /// 門檻調高之後，原本已確認的字會自動掉回未確認，這是刻意的行為。
  WordStatus statusWith(int confirmRight) {
    if (right >= confirmRight && wrong == 0) return WordStatus.confirmed;
    if (right >= 1) return WordStatus.learning;
    return WordStatus.pending;
  }

  Word copyWith({int? right, int? wrong, DateTime? lastTest}) {
    return Word(
      id: id,
      word: word,
      pos: pos,
      zh: zh,
      level: level,
      right: right ?? this.right,
      wrong: wrong ?? this.wrong,
      lastTest: lastTest ?? this.lastTest,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'word': word,
    'pos': pos,
    'zh': zh,
    'level': level.label,
    'right': right,
    'wrong': wrong,
    'lastTest': lastTest?.toIso8601String(),
  };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
    id: json['id'] as int,
    word: json['word'] as String,
    pos: json['pos'] as String,
    zh: json['zh'] as String,
    level: WordLevel.parse(json['level'] as String? ?? '國小'),
    right: json['right'] as int? ?? 0,
    wrong: json['wrong'] as int? ?? 0,
    lastTest: (json['lastTest'] as String?) == null
        ? null
        : DateTime.parse(json['lastTest'] as String),
  );
}
