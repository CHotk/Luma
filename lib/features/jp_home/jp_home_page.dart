import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/time_of_day_label.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/track_switcher.dart';
import 'jp_home_controller.dart';

/// 日文軌道的首頁。配色是設計稿定案的「櫻」（見 `design-history/`），
/// 只換 [AmbientBackground] 的底色跟四團模糊色塊——`GlassCard` 本身
/// 不用換色，設計稿裡玻璃面板一直是中性的白霧感，色系差別是靠背景
/// 光跟強調色表現，不是玻璃本身。
///
/// 內容目前只有一塊：五十音手寫練習的入口跟真實統計（已存幾筆、
/// 今天存了幾筆）。這個軌道還沒有像英文那樣的每日輪數規則，所以
/// 沒有圓環進度那種面板——那是英文軌道 [RulesConfig] 算出來的東西，
/// 日文還沒有對應的東西，硬套會是假資料，等真的有更多內容再加。
class JpHomePage extends ConsumerWidget {
  const JpHomePage({super.key});

  static const _accent = Color(0xFFEA92AC);
  static const _amb = [
    Color(0xFF4A2036),
    Color(0xFF6B3550),
    Color(0xFF2E2440),
    Color(0xFF7A3F55),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jpHomeStateProvider);

    return Scaffold(
      body: AmbientBackground(
        background: const Color(0xFF1B1420),
        blobColors: _amb,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    Text(
                      '${weekdayLabel(DateTime.now())} '
                      '${clockLabel(DateTime.now())} '
                      '${periodEmoji(DateTime.now())}',
                      style: AppText.title,
                    ),
                    const SizedBox(width: Gap.sm),
                    const TrackSwitcher(current: LearningTrack.ja),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                  error: (e, _) =>
                      Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
                  data: (state) => _PracticeEntry(state: state),
                ),
                const Spacer(),
                Text(
                  '假名之外的內容還在做，先從手寫練習開始',
                  textAlign: TextAlign.center,
                  style: AppText.bodyDim,
                ),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeEntry extends StatelessWidget {
  const _PracticeEntry({required this.state});

  final JpHomeState state;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => context.push('/kana-practice'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '五十音・手寫練習',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.totalEntries == 0
                      ? '還沒有練習紀錄，點進去寫第一個字'
                      : '已存 ${state.totalEntries} 筆・今天 ${state.todayEntries} 筆',
                  style: AppText.bodyDim,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: JpHomePage._accent),
        ],
      ),
    );
  }
}
