/// 一支影片「被點開過」的記錄（2026-09-29 使用者要求：YT 管理點頻道、
/// 點影片，或用任何方式點開影片，都該標記成看過；後來使用者又糾正：
/// 不是只記第一次跟最近一次，每一次點開都該記一筆，跟其他「只增不改」
/// 的紀錄同一套邏輯——見 `YtVideoWatchStore` 的合併說明）。
class YtVideoWatchRecord {
  const YtVideoWatchRecord({required this.openedAt});

  /// 每一次點開的時間戳，由舊到新排序，不去重（同一秒點兩次也各自算
  /// 一筆，反映真實點開次數）。
  final List<DateTime> openedAt;

  /// 第一次點開的時間——畫面上的「已看過」小標籤用這個當依據。
  DateTime get firstWatchedAt => openedAt.first;

  /// 最近一次點開的時間。
  DateTime get lastOpenedAt => openedAt.last;

  Map<String, dynamic> toJson() => {
    'openedAt': [for (final t in openedAt) t.toIso8601String()],
  };

  factory YtVideoWatchRecord.fromJson(Map<String, dynamic> json) =>
      YtVideoWatchRecord(
        openedAt: (json['openedAt'] as List)
            .map((e) => DateTime.parse(e as String))
            .toList(),
      );
}
