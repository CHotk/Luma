import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/cloud/r2_credentials_store.dart';
import 'data/repositories/app_home_style_store.dart';
import 'data/repositories/app_logo_store.dart';
import 'data/repositories/error_log_repository.dart';
import 'data/repositories/jp_home_ring_store.dart';
import 'data/repositories/usdt_twd_rate_store.dart';
import 'data/repositories/yt_api_key_store.dart';
import 'data/repositories/yt_embed_player_style_store.dart';
import 'data/repositories/yt_stats_refresh_setting_store.dart';
import 'data/repositories/yt_video_open_mode_store.dart';
import 'data/seed/app_defaults_loader.dart';
import 'data/storage/platform_store.dart';
import 'data/storage/retired_data_cleanup.dart';
import 'shared/debug/app_log.dart';

/// 開機流程做兩件事：把要非同步準備的儲存後端先開好，
/// 也把單字庫標籤排序這種讀資產檔的設定先讀好，再用 override 注進
/// provider。這樣畫面層就不必處理「還沒準備好」。
///
/// 整個開機包在 [runZonedGuarded] 裡：網頁版上沒人 await 的非同步例外
/// **不會**走 `PlatformDispatcher.onError`，只會印在瀏覽器 console，設定
/// 頁「查看除錯訊息」完全看不到（2026-10-06 使用者回報：置頂／一般要
/// 按兩次，console 有 Uncaught Error、除錯頁卻什麼都沒有）。zone 接住
/// 之後一樣寫進 [AppLog]、照常印到 console。
void main() {
  runZonedGuarded(_start, (error, stack) {
    AppLog.add('$error\n$stack', isError: true);
    // ignore: avoid_print
    print('Uncaught: $error\n$stack');
  });
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  _wireAppLog();
  // 開機流程整包包進 try/catch（2026-09-30 使用者回報：手機 iOS Safari
  // 打開 App 一直轉圈轉不出來，除錯日誌完全沒有任何新錯誤）。根因多半
  // 是 `openPlatformStore()` 內部的 IndexedDB 卡住（iOS Safari 已知
  // bug，見那邊的說明，現在已經加上逾時）——但這裡開機流程本身完全
  // 沒有 try/catch，`runApp` 之前任何一步丟例外，畫面就是永遠停在
  // Flutter 引擎初始化那個轉圈，連錯誤畫面都看不到。現在失敗會顯示
  // 一個簡單的錯誤畫面，至少讓使用者知道發生什麼事、能怎麼做，不是
  // 一片空白猜半天。
  try {
    final store = await openPlatformStore();
    // 錯誤日誌持久化：之後的錯誤寫進本機儲存，先把上次留下的讀回來。
    final errorLog = ErrorLogRepository(store);
    AppLog.persistError = errorLog.add;
    AppLog.restore(await errorLog.loadAll());
    // 已移除功能的舊資料（看盤次數）順手清掉；失敗不影響開機。
    try {
      await removeRetiredLocalData(store);
    } catch (e, stack) {
      AppLog.add('清除已移除功能的舊資料失敗：$e\n$stack', isError: true);
    }
    final tagOrder = await loadLibraryTagOrder();
    // 過期（存進去一週之後）就是 null，跟原本沒存過一樣——見
    // yt_api_key_store.dart 的說明。
    final savedYtApiKey = await YtApiKeyStore(store).load();
    final savedYtStatsRefreshDays = await YtStatsRefreshSettingStore(
      store,
    ).load();
    final savedAppLogoAssetPath = await AppLogoStore(store).load();
    final savedYtVideoOpenMode = await YtVideoOpenModeStore(store).load();
    final savedYtEmbedPlayerStyle = await YtEmbedPlayerStyleStore(store).load();
    final savedJpShowRing = await JpHomeRingStore(store).load();
    final savedAppHomeStyle = await AppHomeStyleStore(store).load();
    final savedUsdtTwdRate = await UsdtTwdRateStore(store).load();
    final r2BucketName = await loadR2BucketName();
    final savedR2Credentials = await R2CredentialsStore(store).load();

    runApp(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          libraryTagOrderProvider.overrideWithValue(tagOrder),
          ytApiKeyProvider.overrideWith((ref) => savedYtApiKey),
          ytStatsRefreshDaysProvider.overrideWith(
            (ref) => savedYtStatsRefreshDays,
          ),
          appLogoAssetProvider.overrideWith((ref) => savedAppLogoAssetPath),
          ytVideoOpenModeProvider.overrideWith((ref) => savedYtVideoOpenMode),
          ytEmbedPlayerStyleProvider.overrideWith(
            (ref) => savedYtEmbedPlayerStyle,
          ),
          jpShowProgressRingProvider.overrideWith((ref) => savedJpShowRing),
          appHomeStyleProvider.overrideWith((ref) => savedAppHomeStyle),
          usdtTwdRateProvider.overrideWith((ref) => savedUsdtTwdRate),
          r2BucketNameProvider.overrideWithValue(r2BucketName),
          r2CredentialsProvider.overrideWith((ref) => savedR2Credentials),
        ],
        child: const LumeApp(),
      ),
    );
  } catch (e, stack) {
    AppLog.add('開機失敗：$e\n$stack', isError: true);
    runApp(_StartupErrorApp(message: '$e'));
  }
}

/// 開機流程失敗時的退回畫面——純靜態文字，不依賴任何還沒準備好的
/// provider／儲存後端，盡量不再出錯。
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0C0C13),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 40,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'App 開機失敗',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '可以先試試：重新整理、關掉其他分頁、或重開瀏覽器',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
