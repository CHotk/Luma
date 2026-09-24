import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/crypto_watch_stats.dart';
import '../../domain/models/crypto_watch.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

/// 看盤統計（設計稿 05）：今天次數、平均間隔、近 7 天長條圖、最常看的
/// 時段、觸發原因分布。從看盤記錄頁右上角統計按鈕進來。
class CryptoWatchStatsPage extends ConsumerStatefulWidget {
  const CryptoWatchStatsPage({super.key});

  @override
  ConsumerState<CryptoWatchStatsPage> createState() =>
      _CryptoWatchStatsPageState();
}

class _CryptoWatchStatsPageState extends ConsumerState<CryptoWatchStatsPage> {
  late final Future<List<CryptoWatchEntry>> _future = ref
      .read(cryptoWatchRepositoryProvider)
      .loadAll();

  @override
  Widget build(BuildContext context) {
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
                const AppTopBar(title: '看盤統計'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      return _Body(entries: snap.data!);
                    },
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

class _Body extends StatelessWidget {
  const _Body({required this.entries});

  final List<CryptoWatchEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = entries.where((e) => dayOf(e.at) == dayOf(now)).length;
    final avg = averageInterval(entries, now.subtract(const Duration(days: 7)));
    final week = lastDays(entries, now, 7);
    final weekMax = week.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    final buckets = countsByBucket(entries);
    final bucketMax = buckets.values.fold<int>(1, (m, v) => v > m ? v : m);
    final reasons = countsByReason(entries);
    final reasonTotal = reasons.values.fold<int>(0, (a, b) => a + b);

    if (entries.isEmpty) {
      return Center(child: Text('還沒有紀錄，先去記幾筆吧', style: AppText.bodyDim));
    }

    return ListView(
      children: [
        Row(
          children: [
            Expanded(child: _statCard('今天', '$today 次', AppColors.mid)),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _statCard(
                '近 7 天平均間隔',
                avg == null ? '—' : formatDuration(avg),
                AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('近 7 天', style: AppText.note),
              const SizedBox(height: Gap.sm),
              SizedBox(
                height: 130,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in week)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              d.count == 0 ? '' : '${d.count}',
                              style: AppText.note,
                            ),
                            const SizedBox(height: 2),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              height: d.count == 0 ? 2 : 90 * d.count / weekMax,
                              decoration: BoxDecoration(
                                color: d.count > 3
                                    ? AppColors.bad
                                    : AppColors.accent,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '一二三四五六日'[d.day.weekday - 1],
                              style: AppText.note,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最常看的時段（全部紀錄）', style: AppText.note),
              for (final b in timeBuckets) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  '$b・${buckets[b]} 次',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: buckets[b]! / bucketMax,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF1E1E2E),
                    color: b.startsWith('深夜')
                        ? AppColors.bad
                        : AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('為什麼看？', style: AppText.note),
              const SizedBox(height: Gap.sm),
              Text(
                [
                  for (final e in reasons.entries)
                    '${e.key} ${(e.value * 100 / reasonTotal).round()}%',
                ].join('・'),
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.note),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}
