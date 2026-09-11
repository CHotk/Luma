/// 單字大概是哪個階段學的，對應題庫檔的最後一欄。
///
/// 只分四級。曾經細分到小一小六，但那層沒有官方依據，
/// 課綱本身也只分國小與國中兩段，猜出來的年級只會讓人誤以為很準。
/// 覺得某個字擺錯階段就直接改題庫檔那一欄，不用動程式。
enum WordGrade {
  elementary('國小'),
  junior('國中'),
  senior('高中'),
  college('大學');

  const WordGrade(this.label);
  final String label;

  static WordGrade parse(String raw) {
    final text = raw.trim();
    for (final grade in values) {
      if (grade.label == text) return grade;
    }
    // 曾經用過的細分級，讀到就收斂回所屬階段。
    if (text.startsWith('小')) return WordGrade.elementary;
    if (text.startsWith('國')) return WordGrade.junior;
    return WordGrade.elementary;
  }
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
    required this.grade,
    this.example = '',
    this.added,
    this.imagePath = '',
    this.right = 0,
    this.wrong = 0,
    this.lastTest,
  });

  final int id;
  final String word;
  final String pos;
  final String zh;

  /// 大概幾年級學的。估計值，改題庫檔就能修正。
  final WordGrade grade;

  /// 例句。題庫的字還沒有例句，考過之後才補，所以可能是空字串。
  ///
  /// 這一欄現在畫面上用不到，但一定要留著：
  /// words.txt 有這一欄，少了它匯出就會掉資料，兩邊格式也就對不起來。
  final String example;

  /// 首次加入的日期。同樣是為了能無損還原成 words.txt。
  final DateTime? added;

  /// 這個字的配圖檔名。空字串代表沒有圖。
  ///
  /// 欄位先留著，畫面之後才做。
  /// 圖片本身不進資料庫，存在 App 的檔案目錄，這裡只放檔名，
  /// 不然備份檔會被圖撐爆。
  final String imagePath;

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

  Word copyWith({
    int? id,
    String? example,
    DateTime? added,
    String? imagePath,
    int? right,
    int? wrong,
    DateTime? lastTest,
  }) {
    return Word(
      id: id ?? this.id,
      word: word,
      pos: pos,
      zh: zh,
      grade: grade,
      example: example ?? this.example,
      added: added ?? this.added,
      imagePath: imagePath ?? this.imagePath,
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
    'grade': grade.label,
    'example': example,
    'added': added?.toIso8601String(),
    'imagePath': imagePath,
    'right': right,
    'wrong': wrong,
    'lastTest': lastTest?.toIso8601String(),
  };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
    id: json['id'] as int,
    word: json['word'] as String,
    pos: json['pos'] as String,
    zh: json['zh'] as String,
    // 舊版存的是 level 兩級分法，讀得到就沿用，讀不到才當國小。
    grade: WordGrade.parse(
      (json['grade'] ?? json['level']) as String? ?? '國小',
    ),
    example: json['example'] as String? ?? '',
    added: _date(json['added']),
    imagePath: json['imagePath'] as String? ?? '',
    right: json['right'] as int? ?? 0,
    wrong: json['wrong'] as int? ?? 0,
    lastTest: _date(json['lastTest']),
  );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}
