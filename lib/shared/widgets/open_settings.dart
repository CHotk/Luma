import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 目前這頁「不屬於英文學習」的功能路徑前綴。齒輪點進去的設定頁
/// 目前只有英文學習用（測驗規則、發音、單字庫排序），其他功能還沒有
/// 自己的設定項目，先導到空白的設定頁，之後哪個功能有設定了再各自做
/// （2026-09-24 使用者要求：其他齒輪的內容可以先留白）。
const _nonEnglishPrefixes = [
  '/jp-',
  '/kana-',
  '/diary',
  // 負債管理（2026-10-08：齒輪裡改密碼，跟日記同一組）。
  '/debt',
  '/yt-tracker',
  '/fitness',
  '/sync',
  '/debug-log',
  // App 首頁（2026-10-05：有「首頁樣式」可以切）。
  '/start',
];

/// 全 App 共用的「點齒輪」動作：依目前所在的功能決定開哪一頁設定。
/// 把目前路徑用 `extra` 帶給 `/settings/other`，那頁才知道要顯示哪個
/// 功能專屬的設定項目（例如 YT 頻道追蹤的 API 金鑰／匯出，2026-09-29
/// 使用者要求把散落在各頁頂部列的設定移進齒輪裡）。
void openSettings(BuildContext context) {
  final location = GoRouterState.of(context).uri.path;
  final other = _nonEnglishPrefixes.any(location.startsWith);
  context.push(
    other ? '/settings/other' : '/settings',
    extra: other ? location : null,
  );
}
