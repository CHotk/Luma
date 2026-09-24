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
    required this.strokes,
    this.imageBase64,
    this.updatedAt,
    this.deletedAt,
  });

  /// 多裝置同步用（2026-09-24）：刪除是墓碑標記不是物理刪除、合併時刪除
  /// 永遠贏、其餘比 [syncedAt] 新舊，同 `DiaryEntry.deletedAt`。舊資料
  /// 沒有這兩欄，[syncedAt] 退回 [savedAt]。
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? savedAt;

  /// 內容有變（新增／編輯／刪除）時蓋上現在的時間，見 [KanaPracticeRepository]。
  KanaPracticeEntry stamped({bool deleted = false}) {
    final now = DateTime.now();
    return KanaPracticeEntry(
      id: id,
      kana: kana,
      romaji: romaji,
      assisted: assisted,
      savedAt: savedAt,
      strokes: strokes,
      imageBase64: imageBase64,
      updatedAt: now,
      deletedAt: deleted ? now : deletedAt,
    );
  }

  /// 存檔當下的微秒時間戳字串，同時當 id 用，不會重複。
  final String id;

  final String kana;
  final String romaji;

  /// true＝背景印著淡淡的假名描摹輔助線，false＝純手寫、空白紙。
  final bool assisted;

  final DateTime savedAt;

  /// 整張練習紙的 PNG，base64 編碼，只有「匯入既有圖片」進來的紀錄才有
  /// ——外部圖片沒有 [strokes] 可以重畫，只能存死圖。App 現寫存的紀錄
  /// 這裡是 null：有 [strokes] 就能隨時畫出同樣的畫面（列表縮圖、重播
  /// 都靠現算，不用另外存一張圖），純數字比一張 PNG 小很多，這份紀錄
  /// 會越存越多（現在自動存，不用手動按），省下來的空間差很多
  /// （使用者 2026-09-17 決定）。
  final String? imageBase64;

  /// 每一筆的落筆軌跡：`(x, y, t)`。`x`／`y` 是**正規化座標**（紙寬／
  /// 紙高的 0~1 比例，不是實際像素）——練習當下紙的大小依螢幕寬度
  /// 而不同，存正規化座標才能保證同一筆紀錄不管在多大的畫布上重播、
  /// 匯出，字都置中、填滿，不會跑位。`t` 是從整次練習第一次落筆算起
  /// 的毫秒數，同一份紀錄裡所有筆畫共用同一條時間軸（不是每筆各自
  /// 從零算），這樣重播時筆畫之間停頓多久、每一筆寫多快，都跟當初
  /// 實際寫的時候一致（使用者 2026-09-17 要求：位置跟間隔都要對，
  /// 不接受用固定配速假裝重播）。
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
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
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
        imageBase64: json['imageBase64'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
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
