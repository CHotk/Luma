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
  });

  /// 存檔當下的微秒時間戳字串，同時當 id 用，不會重複。
  final String id;

  final String kana;
  final String romaji;

  /// true＝背景印著淡淡的假名描摹輔助線，false＝純手寫、空白紙。
  final bool assisted;

  final DateTime savedAt;

  /// 整張練習紙的 PNG，base64 編碼。存的是格線＋輔助字＋墨跡疊在一起
  /// 那一刻紙面的樣子，不是只存筆畫座標——之後想單獨重播筆畫動畫的話
  /// 才需要換成存座標。
  final String imageBase64;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kana': kana,
    'romaji': romaji,
    'assisted': assisted,
    'savedAt': savedAt.toIso8601String(),
    'imageBase64': imageBase64,
  };

  factory KanaPracticeEntry.fromJson(Map<String, dynamic> json) =>
      KanaPracticeEntry(
        id: json['id'] as String,
        kana: json['kana'] as String,
        romaji: json['romaji'] as String,
        assisted: json['assisted'] as bool,
        savedAt: DateTime.parse(json['savedAt'] as String),
        imageBase64: json['imageBase64'] as String,
      );
}
