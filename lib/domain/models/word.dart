import '../rules_config.dart';

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

/// 一個字的四種狀態。判定規則寫在 [Word.statusWith]，不要在別處重算。
enum WordStatus {
  /// 已經可以相信這個字真的會了。
  ///
  /// 兩種進法：從沒錯過而且答對達門檻，
  /// 或是錯過但後來答對次數是答錯次數的好幾倍。
  confirmed('掌握'),

  /// 會，但還沒到門檻。從沒錯過才算這一類。
  learning('未確認'),

  /// 錯過就算，跟後來有沒有答對無關。
  ///
  /// 這條定義是使用者 2026-09-11 明確講的：
  /// 「待複習本身就是有答錯過的就算，而不是沒答對過」。
  /// 要離開這一類只有一條路：答對次數累積到答錯次數的 recoveryRatio 倍。
  pending('待複習'),

  /// 從來沒被考過。它不是待複習，因為你根本還沒碰過它。
  untested('沒考過');

  const WordStatus(this.label);
  final String label;

  /// 清單排序用。越需要看的排越前面。
  int get priority => switch (this) {
    WordStatus.pending => 0,
    WordStatus.learning => 1,
    WordStatus.untested => 2,
    WordStatus.confirmed => 3,
  };
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
  WordStatus statusWith(RulesConfig rules) {
    if (wrong > 0) {
      // 錯過的字要翻身，答對次數得是答錯次數的好幾倍。
      // 錯五次、倍率十，就是要答對五十次。訂得重是刻意的。
      return right >= wrong * rules.recoveryRatio
          ? WordStatus.confirmed
          : WordStatus.pending;
    }
    if (right >= rules.confirmRight) return WordStatus.confirmed;
    if (right >= 1) return WordStatus.learning;
    return WordStatus.untested;
  }

  /// 這個字離掌握還差幾次答對。已經掌握就是 0，代表「不差了」。
  ///
  /// 注意：這只是算給畫面看的，對錯次數本身永遠繼續累加，
  /// 不會因為掌握了就歸零或停止計數。
  int rightNeededFor(RulesConfig rules) {
    final target = wrong > 0 ? wrong * rules.recoveryRatio : rules.confirmRight;
    final left = target - right;
    return left < 0 ? 0 : left;
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
    grade: WordGrade.parse((json['grade'] ?? json['level']) as String? ?? '國小'),
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
