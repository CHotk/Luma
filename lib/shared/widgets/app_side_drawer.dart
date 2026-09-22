import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

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
    final isLanguage = !isDiary && !isYtTracker;

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
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
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
                    label: '日記',
                    active: isDiary,
                    // 日記做出來了（2026-09-22），從「敬請期待」那組
                    // 移出來變成真的可以點的大類別，跟語言學習同一層。
                    // 已經在日記裡就只關選單，不重複 push 疊一頁。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isDiary) context.push('/diary');
                    },
                  ),
                  _NavItem(
                    icon: Icons.subscriptions_rounded,
                    label: 'YT 頻道追蹤',
                    active: isYtTracker,
                    // 分類／頻道管理做出來了（2026-09-22），從「敬請
                    // 期待」那組移出來，同上。
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isYtTracker) context.push('/yt-tracker');
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
                ],
              ),
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
  });

  final IconData icon;
  final String label;
  final bool active;
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
              Icon(
                icon,
                size: 19,
                color: active ? AppColors.accent : color,
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
