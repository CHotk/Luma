import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/cloud/r2_credentials_store.dart';
import 'data/repositories/error_log_repository.dart';
import 'data/repositories/yt_api_key_store.dart';
import 'data/seed/app_defaults_loader.dart';
import 'data/storage/platform_store.dart';
import 'shared/debug/app_log.dart';

/// 開機流程做兩件事：把要非同步準備的儲存後端先開好，
/// 也把單字庫標籤排序這種讀資產檔的設定先讀好，再用 override 注進
/// provider。這樣畫面層就不必處理「還沒準備好」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _wireAppLog();
  final store = await openPlatformStore();
  // 錯誤日誌持久化：之後的錯誤寫進本機儲存，先把上次留下的讀回來。
  final errorLog = ErrorLogRepository(store);
  AppLog.persistError = errorLog.add;
  AppLog.restore(await errorLog.loadAll());
  final tagOrder = await loadLibraryTagOrder();
  // 過期（存進去一週之後）就是 null，跟原本沒存過一樣——見
  // yt_api_key_store.dart 的說明。
  final savedYtApiKey = await YtApiKeyStore(store).load();
  final r2BucketName = await loadR2BucketName();
  final savedR2Credentials = await R2CredentialsStore(store).load();

  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        libraryTagOrderProvider.overrideWithValue(tagOrder),
        ytApiKeyProvider.overrideWith((ref) => savedYtApiKey),
        r2BucketNameProvider.overrideWithValue(r2BucketName),
        r2CredentialsProvider.overrideWith((ref) => savedR2Credentials),
      ],
      child: const LumeApp(),
    ),
  );
}

/// 把三個錯誤來源都接進 [AppLog]，讓設定頁「查看除錯訊息」看得到
/// 手機瀏覽器不方便叫出來的 console 內容（2026-09-18 使用者要求）：
/// 一般 `debugPrint` 輸出、Flutter build/渲染期間丟出的例外、跟沒人
/// 接的非同步例外。三個都只是「多存一份」，原本該印到瀏覽器 console
/// 的行為完全不變（`_originalDebugPrint` 照常呼叫、
/// `FlutterError.presentError` 照常呼叫、`onError` 照常回傳 false
/// 讓它繼續往下走）。
void _wireAppLog() {
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) AppLog.add(message);
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };

  FlutterError.onError = (details) {
    AppLog.add(details.exceptionAsString(), isError: true);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.add('$error\n$stack', isError: true);
    return false;
  };
}
