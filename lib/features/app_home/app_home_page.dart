import 'package:flutter/material.dart';
import '../../domain/habit_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/track_switcher.dart';

/// 整個 App 的首頁（2026-09-24 使用者要求：功能變多了，不想一打開就
/// 是語言學習）。設計稿 `design-history/首頁設計/01_圖示格啟動器(主流).html`
/// 定案：像手機桌面的圖示格，每個功能一格，圖示沿用側邊選單那組
/// （`assets/images/nav_icons/`，沒有圖的退回內建圖示），風格跟其他頁面
/// 一樣用毛玻璃卡片。
class AppHomePage extends ConsumerWidget {
  const AppHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <_HomeItem>[
      _HomeItem(
        label: '語言學習',
        icon: Icons.school_rounded,
        imageAsset: 'assets/images/nav_icons/language.png',
        color: AppColors.accent,
        // 跟以前開機畫面一樣進上次用的軌道（英文／日文）。
        onTap: () async {
          final last = await ref
              .read(settingsRepositoryProvider)
              .loadLastTrack();
          final track = last == LearningTrack.ja.name
              ? LearningTrack.ja
              : LearningTrack.en;
          if (context.mounted) context.go(track.homeRoute);
        },
      ),
      const _HomeItem(
        label: '日記',
        icon: Icons.auto_stories_rounded,
        imageAsset: 'assets/images/nav_icons/diary.png',
        color: AppColors.diaryAccent,
        route: '/diary',
      ),
      const _HomeItem(
        label: 'YT 頻道',
        icon: Icons.subscriptions_rounded,
        imageAsset: 'assets/images/nav_icons/yt_tracker.png',
        color: AppColors.ytAccent,
        route: '/yt-tracker',
      ),
      const _HomeItem(
        label: '健身',
        icon: Icons.fitness_center_rounded,
        imageAsset: 'assets/images/nav_icons/fitness.png',
        color: Color(0xFFF2A65A),
        route: '/fitness',
      ),
      for (final habit in allHabits)
        _HomeItem(
          label: habit.title,
          icon: habit.icon,
          color: habit.color,
          route: habit.route,
        ),
      const _HomeItem(
        label: '多裝置同步',
        icon: Icons.cloud_sync_outlined,
        color: Color(0xFF7ED6D0),
        route: '/sync',
      ),
      const _HomeItem(
        label: '除錯',
        icon: Icons.bug_report_outlined,
        imageAsset: 'assets/images/nav_icons/debug.png',
        color: Color(0xFFB39DDB),
        route: '/debug-log',
      ),
    ];

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                const AppTopBar(title: 'Lume', showBack: false),
                const SizedBox(height: Gap.lg),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_dateLabel(DateTime.now()), style: AppText.note),
                        const SizedBox(height: Gap.md),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: Gap.md,
                          crossAxisSpacing: Gap.md,
                          childAspectRatio: 0.95,
                          children: [
                            for (final item in items) _HomeTile(item: item),
                          ],
                        ),
                        const SizedBox(height: Gap.lg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime d) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.year} 年 ${d.month} 月 ${d.day} 日・週${weekdays[d.weekday - 1]}';
}

class _HomeItem {
  const _HomeItem({
    required this.label,
    required this.icon,
    required this.color,
    this.imageAsset,
    this.route,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String? imageAsset;
  final Color color;
  final String? route;
  final Future<void> Function()? onTap;
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.item});

  final _HomeItem item;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(item.icon, size: 28, color: item.color);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      onTap: () {
        if (item.onTap != null) {
          item.onTap!();
        } else {
          context.go(item.route!);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: item.color.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: item.imageAsset == null
                ? fallback
                : Image.asset(
                    item.imageAsset!,
                    width: 28,
                    height: 28,
                    color: item.color,
                    errorBuilder: (context, error, stack) => fallback,
                  ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
