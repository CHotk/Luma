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

/// 句子專用的標籤：標了這個標籤的 `Word` 其實是一整句英文（見
/// `assets/data/sentences.txt`），不是單字，出題規則要另外開一個句型池，
/// 不能跟一般單字混在待複習/新字/已掌握三個池子裡（見 `QuestionPicker`）。
///
/// 2026-09-16 之前類別（topic）是獨立的欄位跟 enum（食物、居家、月份、
/// 數字、顏色、水果、句型），使用者決定拿掉這個分類軸，全部併進自由標籤
/// [Word.tags]：類別本來就跟標籤一樣是「一個字可以貼好幾個」的自由分類，
/// 沒必要另外開一個固定選項的 enum，單字庫的「類別」下拉現在直接對 tags
/// 出現過的所有值，不是列舉這裡的常數。句型這個標籤比較特殊，是唯一一個
/// 真正影響出題邏輯（而不是只給畫面篩選用）的標籤，才把字串常數留在這裡
/// 而不是散在各處硬編碼。
const sentenceTag = '句型';

/// 單字有幾個意思，對應題庫檔的欄位。
/// 判斷標準是查字典的義項數：1 個算單義，2 到 4 個算多義，
/// 5 個以上算極多義。這是人工標記時要靠的標準，App 本身不會自動算，
/// 沒標過的字一律是未分類。
enum WordSenseCount {
  none('未分類'),
  single('單義'),
  few('多義'),
  many('極多義');

  const WordSenseCount(this.label);
  final String label;

  /// 有沒有真的被標過。未分類的不顯示標籤。
  bool get isTagged => this != WordSenseCount.none;

  static WordSenseCount parse(String? raw) {
    final text = raw?.trim() ?? '';
    for (final sense in values) {
      if (sense != WordSenseCount.none && sense.label == text) return sense;
    }
    return WordSenseCount.none;
  }
}

/// 一個字的三種狀態。判定規則寫在 [Word.statusWith]，不要在別處重算。
///
/// 只有三類是使用者 2026-09-11 拍板的：沒有「未確認」這種中間狀態。
/// 錯過的要回來，答對過但還沒到門檻的也要回來，
/// 對使用者來說那就是同一件事，都叫待複習。
enum WordStatus {
  /// 已經可以相信這個字真的會了。
  ///
  /// 兩種進法：從沒錯過而且答對達門檻，
  /// 或是錯過但後來答對次數是答錯次數的好幾倍。
  confirmed('掌握'),

  /// 考過但還沒到掌握的字，全部算這一類。
  pending('待複習'),

  /// 從來沒被考過。它不是待複習，因為你根本還沒碰過它。
  untested('新字');

  const WordStatus(this.label);
  final String label;

  /// 清單排序用。越需要看的排越前面。
  int get priority => switch (this) {
    WordStatus.pending => 0,
    WordStatus.untested => 1,
    WordStatus.confirmed => 2,
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
    this.senseCount = WordSenseCount.none,
    this.example = '',
    this.added,
    this.imagePath = '',
    this.right = 0,
    this.wrong = 0,
    this.lastTest,
    this.tags = const [],
    this.relatedWords = const [],
  });

  final int id;
  final String word;
  final String pos;
  final String zh;

  /// 有幾個意思。改題庫檔那一欄就能改，不用動程式。
  final WordSenseCount senseCount;

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

  /// 自由命名的分類標籤，方便之後搜尋用。改題庫檔最後一欄就能加，不用動程式。
  /// 沒標的字是空清單，不是 `['-']`——那個 `-` 只是題庫檔裡「沒有」的寫法。
  final List<String> tags;

  /// 這個字用到哪些學過的單字，目前只有句型（標了 [sentenceTag] 的字）
  /// 會用到，存的是文字（單字本身），不是 id——文字好讀好編輯，代價是
  /// 拼錯就對不上，這是使用者 2026-09-16 權衡過的決定。跟 [tags] 是不同
  /// 欄位、不同語意：tags 是自由分類（像多益、工程師、句型），這個是
  /// 「這句用到哪些字」的交叉參照，混在同一欄會分不出哪個是哪個。
  final List<String> relatedWords;

  /// 標籤用「、」分隔多個，題庫檔裡的 `-` 代表沒標，解析成空清單。
  /// [relatedWords] 也是同一套分隔規則，共用這個方法解析。
  static List<String> parseTags(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || text == '-') return const [];
    return text.split('、').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

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
    if (right >= 1) return WordStatus.pending;
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

  /// 對錯打平之後的權重，數字越高代表對得越多、越紮實。
  ///
  /// 跟 [rightNeededFor] 算的是同一套門檻，但不夾在 0：
  /// 沒錯過的字，權重就是答對次數本身；錯過的字，答對次數先扣掉
  /// 「錯的次數 × recoveryRatio」，再加回 confirmRight 校正基準，
  /// 這樣兩條路線剛好打平掌握門檻時，權重都會落在同一個數字
  /// （即 confirmRight）上，兩種字才排得進同一把尺，不會因為錯過而
  /// 被算得比從沒錯過的字還吃虧或還划算。
  int masteryWeight(RulesConfig rules) {
    final target = wrong > 0 ? wrong * rules.recoveryRatio : rules.confirmRight;
    return rules.confirmRight + right - target;
  }

  Word copyWith({
    int? id,
    WordSenseCount? senseCount,
    String? example,
    DateTime? added,
    String? imagePath,
    int? right,
    int? wrong,
    DateTime? lastTest,
    List<String>? tags,
    List<String>? relatedWords,
  }) {
    return Word(
      id: id ?? this.id,
      word: word,
      pos: pos,
      zh: zh,
      grade: grade,
      senseCount: senseCount ?? this.senseCount,
      example: example ?? this.example,
      added: added ?? this.added,
      imagePath: imagePath ?? this.imagePath,
      right: right ?? this.right,
      wrong: wrong ?? this.wrong,
      lastTest: lastTest ?? this.lastTest,
      tags: tags ?? this.tags,
      relatedWords: relatedWords ?? this.relatedWords,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'word': word,
    'pos': pos,
    'zh': zh,
    'grade': grade.label,
    'senseCount': senseCount.label,
    'example': example,
    'added': added?.toIso8601String(),
    'imagePath': imagePath,
    'right': right,
    'wrong': wrong,
    'lastTest': lastTest?.toIso8601String(),
    'tags': tags,
    'relatedWords': relatedWords,
  };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
    id: json['id'] as int,
    word: json['word'] as String,
    pos: json['pos'] as String,
    zh: json['zh'] as String,
    // 舊版存的是 level 兩級分法，讀得到就沿用，讀不到才當國小。
    grade: WordGrade.parse((json['grade'] ?? json['level']) as String? ?? '國小'),
    senseCount: WordSenseCount.parse(json['senseCount'] as String?),
    example: json['example'] as String? ?? '',
    added: _date(json['added']),
    imagePath: json['imagePath'] as String? ?? '',
    right: json['right'] as int? ?? 0,
    wrong: json['wrong'] as int? ?? 0,
    lastTest: _date(json['lastTest']),
    tags: (json['tags'] as List?)?.map((t) => t as String).toList() ?? const [],
    relatedWords:
        (json['relatedWords'] as List?)?.map((t) => t as String).toList() ??
        const [],
  );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}
