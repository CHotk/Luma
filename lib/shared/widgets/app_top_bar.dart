import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';

/// 全 App 共用的頁面頂部列：左邊固定三條線選單（開抽屜），右邊固定
/// 設定齒輪——這兩個位置整個 App 都一樣，不管哪個頁面都要在，不能
/// 因為某個頁面自己刻標題列就把它們拿掉或換位置（2026-09-22 使用者
/// 要求：三條線／設定是整個 App 固定的，不管哪個頁面都要在）。
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
        IconButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu, size: 20),
          color: AppColors.ink2,
          tooltip: '選單',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        if (showBack) ...[
          const SizedBox(width: Gap.sm),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppColors.ink2,
            tooltip: '返回',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
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
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined, size: 20),
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
