/// 50 音考試的一次記錄。
///
/// 跟 [KanaPracticeEntry] 相似的結構，但用於考試模式，需要額外記錄：
/// - 是否答對
/// - 考試的題目類型（50音或詞彙）
class KanaExamEntry {
  const KanaExamEntry({
    required this.id,
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

  /// 答案的平假名。
  final String kana;

  /// 答案的羅馬字。
  final String romaji;

  /// 是否答對。
  final bool isCorrect;

  /// 考試類型：'kana' 為 50 音，'vocab' 為詞彙。
  final String examType;

  final DateTime savedAt;

  /// 手寫筆畫的 base64 編碼圖片（可選）。
  final String? imageBase64;

  /// 整筆紀錄的筆畫軌跡：`(x, y, t)`。
  /// - x, y：正規化座標（0~1）
  /// - t：從第一筆落筆起的毫秒數
  final List<List<(double x, double y, double t)>> strokes;

  Map<String, dynamic> toJson() => {
    'id': id,
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
