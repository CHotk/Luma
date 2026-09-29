import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import 'open_settings.dart';
import 'settings_icon.dart';

/// 全 App 共用的頁面頂部列：左邊固定選單／返回其中一個，右邊固定設定
/// 齒輪。齒輪整個 App 都要在（2026-09-22 使用者要求）；左邊原本三條線
/// 選單跟返回鍵會一起顯示，後來使用者決定（2026-09-29）：有返回鍵的子
/// 頁不用再顯示三條線——反正按返回就會回到上層的各功能首頁，三條線在
/// 那裡才會出現。所以左邊兩個是互斥的：[showBack] 為 true 顯示返回鍵、
/// 不顯示三條線；為 false（各功能首頁）顯示三條線、不顯示返回鍵。
///
/// 用 `Scaffold.of(context).openDrawer()` 開抽屜，所以這個 widget 必須
/// 是 Scaffold 的子孫節點——呼叫端的 Scaffold 要帶
/// `drawer: const AppSideDrawer()`，也不能把 [AppTopBar] 直接寫在建立
/// 那個 Scaffold 的 `build()` 最外層（那層的 context 是 Scaffold 的
/// 上層，抓不到它，見 `diary_page.dart` 的 `_DiaryTopBar` 說明——這裡
/// 抽成獨立 widget 就是為了每個頁面都不用再各自想一次這件事）。
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.showBack = true,
    this.showSettings = true,
    this.actions = const [],
  });

  final String title;

  /// 大部分子頁面是 true（從別的頁面點進來的）；只有那種本來就是靠
  /// 選單／首頁進來、退回去也沒地方好退的頁面才會是 false。
  final bool showBack;

  /// 設定頁自己不需要再顯示一顆連去設定的齒輪。
  final bool showSettings;

  /// 頁面自己專屬的按鈕（例如匯出、清空紀錄），排在標題右邊、
  /// 設定齒輪左邊。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppColors.ink2,
            tooltip: '返回',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )
        else
          IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu, size: 20),
            color: AppColors.ink2,
            tooltip: '選單',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            title,
            style: AppText.title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...actions,
        if (showSettings)
          IconButton(
            onPressed: () => openSettings(context),
            icon: const SettingsIcon(size: 20),
            color: AppColors.ink2,
            tooltip: '設定',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
      ],
    );
  }
}
