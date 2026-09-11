import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/history.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';

/// 總歷史。從第一天用到現在的累計，加上每一輪的明細。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyOverviewProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const Text('總紀錄', style: AppText.title),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator.adaptive()),
                    error: (e, _) =>
                        Center(child: Text('讀不到紀錄：$e', style: AppText.bodyDim)),
                    data: (data) => _Body(stats: data.stats, rounds: data.rounds),
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

/// 這頁要的兩份資料一起抓，省掉畫面裡串兩個 future。
final historyOverviewProvider = FutureProvider.autoDispose<
    ({LifetimeStats stats, List<RoundLog> rounds})>((ref) async {
  final repo = ref.watch(historyRepositoryProvider);
  return (stats: await repo.lifetime(), rounds: await repo.rounds());
});

class _Body extends StatelessWidget {
  const _Body({required this.stats, required this.rounds});

  final LifetimeStats stats;
  final List<RoundLog> rounds;

  @override
  Widget build(BuildContext context) {
    if (stats.rounds == 0) {
      return const Center(child: Text('還沒有紀錄，做完一輪就會出現', style: AppText.bodyDim));
    }

    // 新的排前面，看紀錄通常是想看最近做了什麼。
    final recent = rounds.reversed.toList();

    return ListView(
      children: [
        Row(
          children: [
            Expanded(child: _Tile('${stats.rounds}', '總輪數')),
            const SizedBox(width: Gap.sm),
            Expanded(child: _Tile('${stats.questions}', '總題數')),
            const SizedBox(width: Gap.sm),
            Expanded(child: _Tile('${stats.activeDays}', '使用天數')),
          ],
        ),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelLabel('累計'),
              const SizedBox(height: Gap.sm),
              _Row('答對', '${stats.right} 題'),
              _Row('答錯', '${stats.wrong} 題'),
              _Row('正確率', '${(stats.accuracy * 100).toStringAsFixed(0)}%'),
              _Row('總作答時間', _duration(stats.seconds)),
              _Row('偽裝模式', '${stats.stealthRounds} 輪'),
              if (stats.since != null) _Row('從', _day(stats.since!)),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        const PanelLabel('每一輪'),
        const SizedBox(height: Gap.xs),
        for (final r in recent) _RoundRow(log: r),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  static String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h 小時 $m 分';
    return '$m 分 ${seconds % 60} 秒';
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.number),
          const SizedBox(height: 1),
          Text(label, style: AppText.note),
        ],
      ),
    );
  }
}

class _RoundRow extends StatelessWidget {
  const _RoundRow({required this.log});

  final RoundLog log;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text('R${log.round}', style: AppText.bodyDim),
          ),
          Expanded(
            child: Text(
              _Body._day(log.at),
              style: AppText.note,
            ),
          ),
          // 偽裝模式做的那幾輪標一下，自己看得懂就好。
          if (log.stealth)
            const Padding(
              padding: EdgeInsets.only(right: Gap.sm),
              child: Text('cmd', style: TextStyle(
                fontSize: 10,
                color: AppColors.ink3,
                fontFamily: 'Consolas',
              )),
            ),
          Text(
            '${log.right} / ${log.total}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: log.right * 2 >= log.total ? AppColors.ok : AppColors.mid,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.bodyDim),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
