/// 一支影片「被點開過」的記錄（2026-09-29 使用者要求：YT 管理點頻道、
/// 點影片，或用任何方式點開影片，都該標記成看過，還要記下第一次跟
/// 最近一次打開的時間戳）。
class YtVideoWatchRecord {
  const YtVideoWatchRecord({
    required this.firstWatchedAt,
    required this.lastOpenedAt,
  });

  /// 第一次點開的時間，之後重複點開不會再變——畫面上的「已看過」小
  /// 標籤用這個當依據。
  final DateTime firstWatchedAt;

  /// 最近一次點開的時間，每次點開都會更新。
  final DateTime lastOpenedAt;

  Map<String, dynamic> toJson() => {
    'firstWatchedAt': firstWatchedAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
  };

  factory YtVideoWatchRecord.fromJson(Map<String, dynamic> json) =>
      YtVideoWatchRecord(
        firstWatchedAt: DateTime.parse(json['firstWatchedAt'] as String),
        lastOpenedAt: DateTime.parse(json['lastOpenedAt'] as String),
      );
}
