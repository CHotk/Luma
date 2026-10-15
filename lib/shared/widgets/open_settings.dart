import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 全 App 共用的「點齒輪」動作。設定全部在同一頁（2026-10-15 使用者選
/// 設計稿第 5 版），把目前路徑用 `extra` 帶過去，設定頁就先跳到這個功能
/// 那一段（見 `settingsSectionFor`）。
void openSettings(BuildContext context) {
  final location = GoRouterState.of(context).uri.path;
  context.push('/settings', extra: location);
}
