import 'package:flutter/foundation.dart';

import '../../data/export/device_label.dart';

/// App 內建的除錯訊息記錄。
///
/// 手機瀏覽器不方便叫出開發者工具看 console，設定頁「查看除錯訊息」
/// 就是要給使用者一個不用接電腦也能看到最近發生了什麼的地方
/// （2026-09-18 使用者要求）。[main.dart] 在啟動時把 `debugPrint`、
/// `FlutterError.onError`、`PlatformDispatcher.onError` 都接到這裡，
/// 三個來源涵蓋：一般的除錯輸出、Flutter 畫面渲染/build 期間丟出的
/// 例外、跟沒人接的非同步例外（例如 [KanaPracticeRepository.upsert]
/// 那次沒人 await 的 Future 例外，就是這種）。
///
/// 一般訊息只在記憶體裡存最近 [_maxEntries] 筆，重新整理就清空。
/// **錯誤訊息不一樣**（2026-09-24 使用者要求：錯誤日誌也是 log，要存
/// 雲端、不可清除）：錯誤會透過 [persistError] 寫進本機儲存、跟著多
/// 裝置同步存到 R2，啟動時用 [restore] 讀回來，只增不刪、沒有清空功能，
/// 也不受 [_maxEntries] 上限影響。
class AppLog {
  AppLog._();

  static const _maxEntries = 300;

  static final ValueNotifier<List<AppLogEntry>> entries = ValueNotifier(
    const [],
  );

  /// 側邊選單「除錯」項目的角標要知道「有幾筆錯誤還沒看過」，不是
  /// 「總共有幾筆錯誤」——不然只要出過一次錯，角標就會一直掛著不會
  /// 消失，起不到「有新狀況」的提醒作用（2026-09-23 使用者要求除錯
  /// 項目用圖示角標式，見 `app_side_drawer.dart`）。打開除錯頁那刻
  /// 更新這個時間戳記，在那之後才發生的錯誤才會計進角標。
  static DateTime lastViewedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void markViewed() => lastViewedAt = DateTime.now();

  /// 錯誤要持久化時呼叫的回呼，`main()` 開好儲存後注入
  /// （見 `ErrorLogRepository`）。
  static void Function(AppLogEntry entry)? persistError;

  /// 把持久化的錯誤（啟動時讀本機、或同步從雲端合併進來之後）併回
  /// 畫面用的清單，已經有的不重複加。
  static void restore(List<AppLogEntry> persisted) {
    final known = {for (final e in entries.value) e.identity};
    final fresh = [
      for (final e in persisted)
        if (known.add(e.identity)) e,
    ];
    if (fresh.isEmpty) return;
    entries.value = [...entries.value, ...fresh]
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  static void add(String message, {bool isError = false}) {
    final entry = AppLogEntry(
      message: message,
      at: DateTime.now(),
      isError: isError,
      device: currentDeviceLabel(),
    );
    var next = [...entries.value, entry];
    // 只裁掉多出來的一般訊息，錯誤一筆都不丟。
    final overflow = next.where((e) => !e.isError).length - _maxEntries;
    if (overflow > 0) {
      var toDrop = overflow;
      next = [
        for (final e in next)
          if (e.isError || toDrop-- <= 0) e,
      ];
    }
    entries.value = next;
    if (isError) persistError?.call(entry);
  }
}

class AppLogEntry {
  const AppLogEntry({
    required this.message,
    required this.at,
    required this.isError,
    this.device,
  });

  final String message;
  final DateTime at;
  final bool isError;

  /// 哪台裝置發生的（如「Android・Chrome」），多裝置合併紀錄時分辨用。
  final String? device;

  String get identity => '${at.toUtc().toIso8601String()}|$device|$message';

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'message': message,
    'isError': isError,
    'device': device,
  };

  factory AppLogEntry.fromJson(Map<String, dynamic> json) => AppLogEntry(
    at: DateTime.parse(json['at'] as String),
    message: json['message'] as String,
    isError: json['isError'] as bool? ?? true,
    device: json['device'] as String?,
  );
}
