import 'package:flutter/material.dart';

import '../../shared/widgets/app_notice.dart';
import 'notification_service.dart';

/// 測試按鈕：只是想確認這個瀏覽器／裝置真的收得到通知，不是真的推播
/// （見 `docs/規則.md` YT 頻道追蹤一節：真的推播要有後端，這個 App
/// 還沒有）。要權限、送一則本機通知，結果用 [showAppNotice] 講清楚，
/// 因為通知本身跳不跳得出來使用者不一定馬上看得到。
///
/// YT 頻道追蹤首頁跟除錯訊息頁都會用到這顆，抽出來共用，不要各刻一份
/// （2026-09-23 使用者要求除錯頁也要有測試通知按鈕）。
Future<void> testNotification(BuildContext context) async {
  final granted = await requestNotificationPermission();
  if (!granted) {
    if (!context.mounted) return;
    showAppNotice(
      context,
      '沒有通知權限，或這個瀏覽器/裝置不支援——去系統設定允許通知後再試一次',
      isError: true,
    );
    return;
  }
  await showTestNotification();
  if (!context.mounted) return;
  showAppNotice(context, '已送出測試通知，注意看有沒有跳出來');
}
