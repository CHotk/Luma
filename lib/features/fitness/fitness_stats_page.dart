import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/fitness.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

/// 健身統計頁：設計稿 04（統計儀表板式），從首頁「統計」按鈕點進來
/// （2026-09-23 使用者決定：04 不當首頁，收成子頁）。
///
/// 首頁打卡目前沒有收「時長」這個欄位（[FitnessEntry.durationMinutes]
/// 選填、打卡當下不強制輸入，理由見 fitness_home_page.dart），所以這頁
/// 的統計格改成「本週次數／本月次數／連續天數／累計次數」，不是設計稿
/// 原本畫的「本週總時長」——資料模型沒有可靠的時長資料可以加總。
class FitnessStatsPage extends ConsumerWidget {
  const FitnessStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const AppTopBar(title: '健身統計'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<FitnessEntry>>(
                    future: ref.read(fitnessRepositoryProvider).loadEntries(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final entries = snap.data!;
                      if (entries.isEmpty) {
                        return Center(
                          child: Text('還沒有任何打卡紀錄', style: AppText.bodyDim),
                        );
                      }
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StatGrid(entries: entries),
                            const SizedBox(height: Gap.md),
                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const PanelLabel('近 8 週次數'),
                                  const SizedBox(height: Gap.sm),
                                  _WeeklyBarChart(entries: entries),
                                ],
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const PanelLabel('類型佔比'),
                                  const SizedBox(height: Gap.sm),
                                  _TypeDonut(entries: entries),
                                ],
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                          ],
                        ),
                      );
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

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.entries});

  final List<FitnessEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final days = <DateTime>{
      for (final e in entries) FitnessEntry.dayOnly(e.date),
    };
    final weekCount = days.where((d) => !d.isBefore(weekStart)).length;
    final monthCount = days
        .where((d) => d.year == now.year && d.month == now.month)
        .length;
    var streak = 0;
    var cursor = days.contains(FitnessEntry.dayOnly(now))
        ? FitnessEntry.dayOnly(now)
        : FitnessEntry.dayOnly(now).subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Gap.sm,
      crossAxisSpacing: Gap.sm,
      childAspectRatio: 1.8,
      children: [
        _StatCard(value: '$weekCount', label: '本週次數'),
        _StatCard(value: '$monthCount', label: '本月次數'),
        _StatCard(value: '$streak', label: '連續天數'),
        _StatCard(value: '${entries.length}', label: '累計次數'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: AppText.number.copyWith(fontSize: 20)),
          const SizedBox(height: 2),
          Text(label, style: AppText.note),
        ],
      ),
    );
  }
}

/// 近 8 週（含本週）每週次數的長條圖，週一為一週的開始。
class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.entries});

  final List<FitnessEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekStarts = [
      for (var i = 7; i >= 0; i--) thisWeekStart.subtract(Duration(days: i * 7)),
    ];
    final counts = [
      for (final ws in weekStarts)
        entries.where((e) {
          final d = FitnessEntry.dayOnly(e.date);
          return !d.isBefore(ws) && d.isBefore(ws.add(const Duration(days: 7)));
        }).length,
    ];
    final maxCount = counts.fold<int>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final c in counts)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 62 * (c / maxCount).clamp(0.04, 1.0),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.65),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$c', style: const TextStyle(fontSize: 8.5, color: AppColors.ink3)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypeDonut extends StatelessWidget {
  const _TypeDonut({required this.entries});

  final List<FitnessEntry> entries;

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final t in FitnessType.values)
        t: entries.where((e) => e.type == t).length,
    };
    final total = entries.length;

    return Row(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CustomPaint(
            painter: _DonutPainter(counts: counts, total: total),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in FitnessType.values)
                if (counts[t]! > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: t.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${t.label} ${(counts[t]! / total * 100).round()}%',
                          style: AppText.note,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.counts, required this.total});

  final Map<FitnessType, int> counts;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -90 * (3.14159265 / 180);
    final strokeWidth = size.width * 0.22;
    for (final t in FitnessType.values) {
      final count = counts[t] ?? 0;
      if (count == 0) continue;
      final sweep = (count / total) * 2 * 3.14159265;
      final paint = Paint()
        ..color = t.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.counts != counts || oldDelegate.total != total;
}
