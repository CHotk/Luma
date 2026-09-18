import 'package:flutter/foundation.dart';

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
/// 只在記憶體裡存最近 [_maxEntries] 筆，重新整理頁面就會清空——這是
/// 用來看「剛剛發生了什麼」的除錯工具，不是要另外做一份持久化紀錄檔。
class AppLog {
  AppLog._();

  static const _maxEntries = 300;

  static final ValueNotifier<List<AppLogEntry>> entries = ValueNotifier(
    const [],
  );

  static void add(String message, {bool isError = false}) {
    final next = [
      ...entries.value,
      AppLogEntry(message: message, at: DateTime.now(), isError: isError),
    ];
    entries.value = next.length > _maxEntries
        ? next.sublist(next.length - _maxEntries)
        : next;
  }

  static void clear() => entries.value = const [];
}

class AppLogEntry {
  const AppLogEntry({
    required this.message,
    required this.at,
    required this.isError,
  });

  final String message;
  final DateTime at;
  final bool isError;
}
