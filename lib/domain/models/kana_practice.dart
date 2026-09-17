/// 五十音手寫練習的一次存檔。
///
/// 只增不改，跟 [HistoryEntry] 同一套規矩——這是練字過程的紀錄，
/// 不是拿來覆蓋修改的檔案。
class KanaPracticeEntry {
  const KanaPracticeEntry({
    required this.id,
    required this.kana,
    required this.romaji,
    required this.assisted,
    required this.savedAt,
    required this.imageBase64,
    required this.strokes,
  });

  /// 存檔當下的微秒時間戳字串，同時當 id 用，不會重複。
  final String id;

  final String kana;
  final String romaji;

  /// true＝背景印著淡淡的假名描摹輔助線，false＝純手寫、空白紙。
  final bool assisted;

  final DateTime savedAt;

  /// 整張練習紙的 PNG，base64 編碼。存的是格線＋輔助字＋墨跡疊在一起
  /// 那一刻紙面的樣子，不是只存筆畫座標，靜態預覽跟匯入的圖片都靠這個。
  final String imageBase64;

  /// 每一筆的落筆軌跡：`(x, y, t)`，`t` 是從整次練習第一次落筆算起的
  /// 毫秒數，同一份紀錄裡所有筆畫共用同一條時間軸（不是每筆各自從零
  /// 算），這樣重播時筆畫之間停頓多久、每一筆寫多快，都跟當初實際
  /// 寫的時候一致（使用者 2026-09-17 要求：位置跟間隔都要對，不接受
  /// 用固定配速假裝重播）。
  ///
  /// 從「匯入既有圖片」進來的紀錄沒有這份資料（外部圖片本來就沒有
  /// 筆畫過程可言），會是空陣列，畫面要能處理「沒有筆畫可重播」這種
  /// 情況，不能假設一定有資料。
  final List<List<(double x, double y, double t)>> strokes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kana': kana,
    'romaji': romaji,
    'assisted': assisted,
    'savedAt': savedAt.toIso8601String(),
    'imageBase64': imageBase64,
    'strokes': [
      for (final stroke in strokes)
        [for (final p in stroke) [p.$1, p.$2, p.$3]],
    ],
  };

  factory KanaPracticeEntry.fromJson(Map<String, dynamic> json) =>
      KanaPracticeEntry(
        id: json['id'] as String,
        kana: json['kana'] as String,
        romaji: json['romaji'] as String,
        assisted: json['assisted'] as bool,
        savedAt: DateTime.parse(json['savedAt'] as String),
        imageBase64: json['imageBase64'] as String,
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
