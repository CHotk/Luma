import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/fitness.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

/// 健身打卡首頁：設計稿 02（打卡日曆式）定案版本——連續天數／本月達成率
/// 這排數字＋月曆＋今天打卡卡片。統計儀表板（設計稿 04）收成「統計」
/// 按鈕點開的子頁，不是首頁本身（2026-09-23 使用者決定）。
class FitnessHomePage extends ConsumerStatefulWidget {
  const FitnessHomePage({super.key});

  @override
  ConsumerState<FitnessHomePage> createState() => _FitnessHomePageState();
}

class _FitnessHomePageState extends ConsumerState<FitnessHomePage> {
  late Future<List<FitnessEntry>> _future;
  FitnessType _selectedType = FitnessType.strength;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FitnessEntry>> _load() =>
      ref.read(fitnessRepositoryProvider).loadEntries();

  void _reload() => setState(() => _future = _load());

  Future<void> _checkIn() async {
    final now = DateTime.now();
    await ref.read(fitnessRepositoryProvider).addEntry(
      FitnessEntry(
        id: '${now.microsecondsSinceEpoch}',
        date: FitnessEntry.dayOnly(now),
        type: _selectedType,
        loggedAt: now,
      ),
    );
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已打卡：${_selectedType.label}')),
    );
  }

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
                AppTopBar(
                  title: '健身打卡',
                  showBack: false,
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/fitness/stats'),
                      icon: Image.asset(
                        'assets/images/fitness/stats_icon.png',
                        width: 20,
                        height: 20,
                        color: AppColors.ink2,
                        errorBuilder: (context, error, stack) => const Icon(
                          Icons.bar_chart_rounded,
                          size: 20,
                        ),
                      ),
                      color: AppColors.ink2,
                      tooltip: '統計',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<FitnessEntry>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final entries = snap.data!;
                      final days = <DateTime>{
                        for (final e in entries) FitnessEntry.dayOnly(e.date),
                      };
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StreakRow(days: days, totalCount: entries.length),
                            const SizedBox(height: Gap.md),
                            _MonthCalendar(
                              month: _visibleMonth,
                              days: days,
                              onPrev: () => setState(
                                () => _visibleMonth = DateTime(
                                  _visibleMonth.year,
                                  _visibleMonth.month - 1,
                                ),
                              ),
                              onNext: () => setState(
                                () => _visibleMonth = DateTime(
                                  _visibleMonth.year,
                                  _visibleMonth.month + 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                            _CheckInCard(
                              days: days,
                              selected: _selectedType,
                              onSelect: (t) =>
                                  setState(() => _selectedType = t),
                              onCheckIn: _checkIn,
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

/// 連續天數用「今天算不算」：今天還沒打卡不會讓昨天以前累積的連續
/// 天數歸零，從昨天開始往回數；今天已經打卡就從今天開始數
/// （2026-09-23：這是打卡類 App 的常見慣例，不然使用者一早打開 App
/// 會看到自己「連續天數」在還沒打卡前就已經是 0，很挫折）。
int _currentStreak(Set<DateTime> days) {
  final today = FitnessEntry.dayOnly(DateTime.now());
  var cursor = days.contains(today) ? today : today.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.days, required this.totalCount});

  final Set<DateTime> days;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthDays = days.where(
      (d) => d.year == now.year && d.month == now.month,
    ).length;
    final rate = ((monthDays / now.day) * 100).round();
    return GlassCard(
      child: Row(
        children: [
          _StatCell(value: '${_currentStreak(days)}', label: '連續天數'),
          _divider(),
          _StatCell(value: '$rate%', label: '本月達成率'),
          _divider(),
          _StatCell(value: '$totalCount', label: '累計次數'),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: AppColors.glassEdge);
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.number.copyWith(fontSize: 20)),
          const SizedBox(height: 2),
          Text(label, style: AppText.note),
        ],
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.days,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final Set<DateTime> days;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _dow = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstDay.weekday % 7;
    final today = FitnessEntry.dayOnly(DateTime.now());

    return GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.ink2,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right, size: 20),
                color: AppColors.ink2,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (final d in _dow)
                Center(
                  child: Text(
                    d,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
                  ),
                ),
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _DayCell(
                  day: d,
                  done: days.contains(DateTime(month.year, month.month, d)),
                  isToday: DateTime(month.year, month.month, d) == today,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.done, required this.isToday});

  final int day;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: done
            ? AppColors.accent.withValues(alpha: 0.22)
            : Colors.transparent,
        border: Border.all(
          color: done
              ? AppColors.accent
              : (isToday ? AppColors.ink2 : Colors.transparent),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 11,
          fontWeight: done ? FontWeight.w700 : FontWeight.w400,
          color: done ? AppColors.ink : AppColors.ink2,
        ),
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.onCheckIn,
  });

  final Set<DateTime> days;
  final FitnessType selected;
  final ValueChanged<FitnessType> onSelect;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final doneToday = days.contains(FitnessEntry.dayOnly(DateTime.now()));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doneToday ? '今天已經打卡了，要再記一項嗎？' : '今天練了嗎？',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in FitnessType.values)
                _TypeChip(
                  type: t,
                  selected: t == selected,
                  onTap: () => onSelect(t),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCheckIn,
              style: FilledButton.styleFrom(
                backgroundColor: selected.color,
                foregroundColor: Colors.black.withValues(alpha: 0.78),
              ),
              child: Text('＋ 打卡（${selected.label}）'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final FitnessType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? type.color.withValues(alpha: 0.24)
              : AppColors.glassFill,
          border: Border.all(color: selected ? type.color : AppColors.glassEdge),
        ),
        child: Text(
          '${type.emoji} ${type.label}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}
