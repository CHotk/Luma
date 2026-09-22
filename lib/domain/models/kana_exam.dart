/// 50 音考試的一次記錄。
///
/// 跟 [KanaPracticeEntry] 相似的結構，但用於考試模式，需要額外記錄：
/// - 是否答對
/// - 考試的題目類型（50音或詞彙）
/// - 屬於哪一輪考試（[roundId]）
class KanaExamEntry {
  const KanaExamEntry({
    required this.id,
    required this.roundId,
    required this.kana,
    required this.romaji,
    required this.isCorrect,
    required this.examType,
    required this.savedAt,
    required this.strokes,
    this.imageBase64,
  });

  /// 存檔當下的微秒時間戳字串，同時當 id 用。
  final String id;

  /// 同一次考試（從進選題頁到寫完最後一題）的所有題目共用同一個
  /// roundId——考試頁開場那一刻的時間戳字串。沒有這個欄位的話，考試
  /// 紀錄頁只能看到一堆各自獨立的題目，分不出「這 20 題是同一次考的」
  /// 還是「分散在不同時間各自寫的」（2026-09-21 使用者要求：要有
  /// 輪次）。
  final String roundId;

  /// 答案的平假名。
  final String kana;

  /// 答案的羅馬字。
  final String romaji;

  /// 是否答對。
  final bool isCorrect;

  /// 考試類型：'kana' 為 50 音，'vocab' 為詞彙。
  final String examType;

  /// 這一題送出（提交自評或按不會）的當下時間，精確到微秒
  /// （[DateTime] 本身的精度），輪次列表跟逐題明細都直接讀這個欄位，
  /// 不用另外存一份時間戳（2026-09-21 使用者要求：每一次答對答錯都
  /// 要精確記錄時間）。
  final DateTime savedAt;

  /// 手寫筆畫的 base64 編碼圖片（可選）。
  final String? imageBase64;

  /// 整筆紀錄的筆畫軌跡：`(x, y, t)`。
  /// - x, y：正規化座標（0~1）
  /// - t：從第一筆落筆起的毫秒數
  final List<List<(double x, double y, double t)>> strokes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'roundId': roundId,
    'kana': kana,
    'romaji': romaji,
    'isCorrect': isCorrect,
    'examType': examType,
    'savedAt': savedAt.toIso8601String(),
    'imageBase64': imageBase64,
    'strokes': [
      for (final stroke in strokes)
        [
          for (final p in stroke) [p.$1, p.$2, p.$3],
        ],
    ],
  };

  factory KanaExamEntry.fromJson(Map<String, dynamic> json) => KanaExamEntry(
    id: json['id'] as String,
    // 舊資料（加 roundId 欄位之前存的）沒有這個 key，退回用自己的
    // id 當 roundId——每一筆自成一輪，不會因為缺欄位就解析失敗。
    roundId: json['roundId'] as String? ?? json['id'] as String,
    kana: json['kana'] as String,
    romaji: json['romaji'] as String,
    isCorrect: json['isCorrect'] as bool,
    examType: json['examType'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
    imageBase64: json['imageBase64'] as String?,
    strokes: [
      for (final stroke in (json['strokes'] as List? ?? const []))
        [
          for (final p in (stroke as List))
            (
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
              (p[2] as num).toDouble(),
            ),
        ],
    ],
  );
}
