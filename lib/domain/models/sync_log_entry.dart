/// 多裝置同步頁做過的動作——目前有「立即同步」跟「備份下載」兩種，
/// 之後這個功能頁如果再加別的動作（例如手動還原），這裡多加一個值。
enum SyncLogAction { sync, backup }

extension SyncLogActionX on SyncLogAction {
  String get label => switch (this) {
    SyncLogAction.sync => '同步',
    SyncLogAction.backup => '備份下載',
  };
}

/// 一筆同步／備份下載的歷史紀錄。見 [SyncLogRepository] 的說明：這個
/// 跟 `AppLog`（除錯用、記憶體、重新整理就清空）不一樣，是要留著回頭
/// 查「上次同步是什麼時候、動了幾筆」的持久化紀錄
/// （2026-09-24 使用者要求）。
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    required this.action,
    required this.success,
    this.detail,
  });

  final DateTime at;
  final SyncLogAction action;
  final bool success;

  /// 成功時是各功能異動／筆數的細節文字，失敗時是錯誤訊息。
  final String? detail;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'action': action.name,
    'success': success,
    'detail': detail,
  };

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
    at: DateTime.parse(json['at'] as String),
    action: SyncLogAction.values.firstWhere(
      (a) => a.name == json['action'],
      orElse: () => SyncLogAction.sync,
    ),
    success: json['success'] as bool,
    detail: json['detail'] as String?,
  );
}
