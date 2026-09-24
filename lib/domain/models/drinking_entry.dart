/// 一次「喝了一杯酒」的紀錄（2026-09-24 使用者要求：記錄自己多久一次，督促
/// 自己不要太頻繁）。看盤／抽菸／喝酒各自獨立一份程式，不共用。
///
/// 只增不改；刪除用墓碑標記（[deletedAt]），跟日記／健身同一套多裝置同步
/// 規矩。[reason] 是選填的觸發原因（焦慮、無聊…），統計頁會用。
class DrinkingEntry {
  const DrinkingEntry({
    required this.id,
    required this.at,
    this.reason,
    this.updatedAt,
    this.deletedAt,
  });

  /// 用微秒時間戳字串當 id，不會重複。
  final String id;

  /// 看價格的時間。
  final DateTime at;

  /// 觸發原因，沒選就是 null。
  final String? reason;

  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// 合併時比新舊用；舊資料沒有 [updatedAt] 就退回 [at]。
  DateTime get syncedAt => updatedAt ?? at;

  DrinkingEntry stamped({bool deleted = false}) {
    final now = DateTime.now();
    return DrinkingEntry(
      id: id,
      at: at,
      reason: reason,
      updatedAt: now,
      deletedAt: deleted ? now : deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'reason': reason,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory DrinkingEntry.fromJson(Map<String, dynamic> json) => DrinkingEntry(
    id: json['id'] as String,
    at: DateTime.parse(json['at'] as String),
    reason: json['reason'] as String?,
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
    deletedAt: json['deletedAt'] == null
        ? null
        : DateTime.parse(json['deletedAt'] as String),
  );
}
