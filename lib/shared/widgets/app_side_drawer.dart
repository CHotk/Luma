import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../debug/app_log.dart';

/// 全 App 共用的左側選單（毛玻璃抽屜），設計稿見
/// `design-history/2026-09-21_左側選單設計稿.html`。
///
/// 這裡選的是「功能大項目」，不是語言軌道或軌道內的子功能——英文／
/// 日文都算同一個「語言學習」類別，軌道切換跟單字庫/練習紀錄這些
/// 子功能已經在各軌道首頁自己的頂部列（[TrackSwitcher] 跟那排
/// IconButton）處理過，這裡重複列只會讓人分不清這兩層選單差在哪
/// （2026-09-22 使用者要求：不要英文/日文，也拿掉單字庫那些選項）。
class AppSideDrawer extends StatelessWidget {
  const AppSideDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // 依目前網址決定哪個大項目要標「選中」，不是寫死語言學習
    // （2026-09-22 使用者回報：進了日記/YT 頻道追蹤之後打開選單，
    // 選中的還是語言學習，沒有跟著換）。只有這三個大類別是真的做
    // 出來的，日記／YT 頻道追蹤以外的網址都算語言學習底下的頁面。
    final location = GoRouterState.of(context).uri.path;
    final isDiary = location.startsWith('/diary');
    final isYtTracker = location.startsWith('/yt-tracker');
    final isFitness = location.startsWith('/fitness');
    final isDebugLog = location.startsWith('/debug-log');
    final isLanguage = !isDiary && !isYtTracker && !isFitness && !isDebugLog;

    return Drawer(
      width: 270,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xB8141220),
              border: Border(right: BorderSide(color: AppColors.glassEdge)),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                children: [
                  Row(
                    children: [
                      const _BrandLogo(),
                      const SizedBox(width: 10),
                      const Text(
                        'Lume',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.ink3,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  _NavItem(
                    icon: Icons.school_rounded,
                    imageAsset: 'assets/images/nav_icons/language.png',
                    label: '語言學習',
                    active: isLanguage,
                    // 已經在語言學習裡面了，點這項只是關掉選單，不用再
                    // 導一次頁；不在的話（例如從日記點回來）才真的導頁。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isLanguage) context.go('/home');
                    },
                  ),
                  _NavItem(
                    icon: Icons.auto_stories_rounded,
                    imageAsset: 'assets/images/nav_icons/diary.png',
                    label: '日記',
                    active: isDiary,
                    // 日記做出來了（2026-09-22），從「敬請期待」那組
                    // 移出來變成真的可以點的大類別，跟語言學習同一層。
                    // 已經在日記裡就只關選單，不重複導頁。這裡一定要用
                    // go 不是 push——大分類切換是「換到另一個大類別」，
                    // 不是子頁面的往下鑽，用 push 的話每點一次選單就多疊
                    // 一頁，使用者在語言學習／日記／YT 頻道追蹤之間跳幾次
                    // 就疊出一長串歷史，返回鍵要按超多次才回得去
                    // （2026-09-23 使用者實機回報：點幾個小功能就開幾個
                    // 頁面一直堆上去）。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isDiary) context.go('/diary');
                    },
                  ),
                  _NavItem(
                    icon: Icons.subscriptions_rounded,
                    imageAsset: 'assets/images/nav_icons/yt_tracker.png',
                    label: 'YT 頻道追蹤',
                    active: isYtTracker,
                    // 分類／頻道管理做出來了（2026-09-22），從「敬請
                    // 期待」那組移出來，同上。同樣用 go，理由見上面
                    // 日記那項的註解。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isYtTracker) context.go('/yt-tracker');
                    },
                  ),
                  _NavItem(
                    icon: Icons.fitness_center_rounded,
                    imageAsset: 'assets/images/nav_icons/fitness.png',
                    label: '健身',
                    active: isFitness,
                    // 健身打卡做出來了（2026-09-23，設計稿 02 打卡日曆式
                    // 定案），從「敬請期待」那組移出來，同上。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isFitness) context.go('/fitness');
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: AppColors.glassEdge),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text(
                      '敬請期待',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                  const _MockNavItem(
                    icon: Icons.account_balance_wallet_rounded,
                    label: '記帳',
                  ),
                  const _MockNavItem(
                    icon: Icons.event_note_rounded,
                    label: '行程表',
                  ),
                  const _MockNavItem(icon: Icons.alarm_rounded, label: '鬧鐘'),
                  const _MockNavItem(icon: Icons.timer_rounded, label: '碼錶'),
                  // 純前端網頁沒有後端能在背景推播，App／分頁沒開著就
                  // 不可能準時提醒（2026-09-23 已經跟使用者說明這個限制）。
                  // 一開始只想到健身提醒才取名「健身提醒」，使用者後來
                  // 决定改成更通用的「提醒」，也明確表示不做退化版本
                  // （只開分頁才會響那種），純粹先記著構想。
                  const _MockNavItem(
                    icon: Icons.notifications_active_outlined,
                    label: '提醒',
                  ),
                  const _MockNavItem(
                    icon: Icons.restaurant_menu_rounded,
                    label: '飲食控制',
                  ),
                  const _MockNavItem(
                    icon: Icons.soup_kitchen_outlined,
                    label: '料理技能',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: AppColors.glassEdge),
                  ),
                  // 除錯放整個選單最後一項，圖示角標式（設計稿 04）：
                  // 平常就是普通圖示，只有「上次看過除錯頁之後又出現新的
                  // 錯誤」才冒紅點，不是「只要出過一次錯就一直掛著」
                  // （2026-09-23 使用者要求：放最後一個＋圖示角標式）。
                  ValueListenableBuilder<List<AppLogEntry>>(
                    valueListenable: AppLog.entries,
                    builder: (context, entries, _) {
                      final unread = entries
                          .where(
                            (e) => e.isError && e.at.isAfter(AppLog.lastViewedAt),
                          )
                          .length;
                      return _NavItem(
                        icon: Icons.bug_report_outlined,
                        imageAsset: 'assets/images/nav_icons/debug.png',
                        label: '除錯',
                        active: isDebugLog,
                        badgeCount: unread,
                        onTap: () {
                          Navigator.of(context).pop();
                          if (!isDebugLog) context.push('/debug-log');
                        },
                      );
                    },
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

/// 側邊選單頂端的品牌標誌。使用者準備了自己的圖放
/// `assets/images/app_logo/logo.png`，讀得到就用那張，讀不到（還沒放、
/// 路徑打錯）就退回原本設計的漸層方塊，跟 [StatsIcon]／[SettingsIcon]
/// 同一套防呆做法（2026-09-23 使用者要求：一樣要防呆，沒圖就退成目前
/// 設計版本）。
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/images/app_logo/logo.png',
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFF9B7BFF),
                Color(0xFF7EA6FF),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.imageAsset,
    this.badgeCount = 0,
  });

  final IconData icon;

  /// 使用者自己準備的圖示，放在 `assets/images/nav_icons/<name>.png`。
  /// 沒放圖的項目這個是 null，直接用 [icon]；有放的話優先顯示圖片，
  /// 圖片載入失敗（檔案還沒放、或路徑打錯）就退回 [icon]，不會整個
  /// 選單項目壞掉或丟例外（2026-09-23 使用者要求可以自訂選單圖示）。
  final String? imageAsset;
  final String label;
  final bool active;

  /// 右上角小紅點的未讀數，0 就不顯示——目前只有「除錯」項目在用
  /// （見 build() 裡的 ValueListenableBuilder），其他項目留預設值。
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.ink : AppColors.ink2;
    return Material(
      color: active
          ? AppColors.accent.withValues(alpha: 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  imageAsset == null
                      ? Icon(icon, size: 19, color: active ? AppColors.accent : color)
                      : Image.asset(
                          imageAsset!,
                          width: 19,
                          height: 19,
                          color: active ? AppColors.accent : color,
                          errorBuilder: (context, error, stack) => Icon(
                            icon,
                            size: 19,
                            color: active ? AppColors.accent : color,
                          ),
                        ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.bad,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「敬請期待」那組還沒做的功能大項目，純版面佔位——不掛
/// onTap，樣式本身就比一般項目暗，不用另外做 disabled 判斷
/// （2026-09-22 使用者要求：先記錄 YT 頻道追蹤／記帳／行程表／
/// 鬧鐘／碼錶／日記這六個構想，見 kana_exam_next_ideas 跟
/// personal_app_feature_ideas 兩份記憶）。日記、YT 頻道追蹤後來做出來
/// 了，移到上面變成真的可以點的項目，這裡只剩還沒開工的四個。
class _MockNavItem extends StatelessWidget {
  const _MockNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.ink3),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              border: Border.all(color: AppColors.glassEdge),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              '構想中',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
