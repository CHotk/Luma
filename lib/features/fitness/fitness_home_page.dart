import 'dart:convert' show utf8, JsonEncoder;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/repositories/fitness_repository.dart';
import '../../data/seed/fitness_seed_loader.dart';
import '../../data/seed/seed_merge.dart';
import '../../domain/models/fitness.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/stats_icon.dart';

const _dayOffsetLabels = ['今天', '昨天', '前天'];

enum _EntryAction { edit, delete }

/// 最近打卡清單只列最新 30 筆——這是首頁的「快速看一眼＋順手改」用，
/// 不是完整歷史查詢，資料多了全塞在首頁只會讓捲動變得很長。
List<FitnessEntry> _recentEntries(List<FitnessEntry> all) {
  final sorted = [...all]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  return sorted.take(30).toList();
}

String _entryDateLabel(DateTime d) {
  const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year} 年 ${d.month} 月 ${d.day} 日・週${weekdayLabels[d.weekday - 1]} '
      '${two(d.hour)}:${two(d.minute)}';
}

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

  /// 0 = 今天／1 = 昨天／2 = 前天，跟日記的補寫下拉同一套邏輯
  /// （2026-09-23 使用者要求：也要能補打昨天或前天的卡）。
  int _dayOffset = 0;

  /// 打卡時間，預設現在——不強制填，但想調整的話用 iOS 風格滾輪選
  /// （2026-09-23 使用者要求：像 iPhone 鬧鐘調分鐘那樣的效果）。
  TimeOfDay _pickedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FitnessEntry>> _load() async {
    final repo = ref.read(fitnessRepositoryProvider);
    // 跟日記／YT 頻道追蹤同一套：每次進頁面先把內建快照併回本機，
    // 讓別的裝置匯出、貼回 git 的紀錄能補齊這台裝置漏掉的部分。
    await repo.mergeSeed(await loadFitnessSeed());
    return repo.loadEntries();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _pickTime() async {
    var draft = _pickedTime;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Text('選打卡時間', style: AppText.body),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.dark),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: DateTime(
                    2000,
                    1,
                    1,
                    draft.hour,
                    draft.minute,
                  ),
                  onDateTimeChanged: (t) =>
                      draft = TimeOfDay(hour: t.hour, minute: t.minute),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) setState(() => _pickedTime = draft);
  }

  Future<void> _checkIn() async {
    final now = DateTime.now();
    final targetDay = FitnessEntry.dayOnly(
      now.subtract(Duration(days: _dayOffset)),
    );
    final loggedAt = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      _pickedTime.hour,
      _pickedTime.minute,
    );
    await ref.read(fitnessRepositoryProvider).addEntry(
      FitnessEntry(
        id: '${now.microsecondsSinceEpoch}',
        date: targetDay,
        type: _selectedType,
        loggedAt: loggedAt,
      ),
    );
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已打卡：${_dayOffsetLabels[_dayOffset]}・${_selectedType.label}',
        ),
      ),
    );
  }

  /// 點一筆歷史紀錄跳出操作選單，跟日記的 `_showEntry` 同一套做法
  /// （2026-09-23 使用者要求：健身也要能看歷史打卡、編輯或刪除）。
  Future<void> _showEntrySheet(FitnessEntry entry) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(entry.type.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: Gap.sm),
                  Text(
                    '${entry.type.label} ・ ${_entryDateLabel(entry.loggedAt)}',
                    style: AppText.body,
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(sheetContext, _EntryAction.edit),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('編輯'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                  ),
                  const SizedBox(width: Gap.xs),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(sheetContext, _EntryAction.delete),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('刪除'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.bad),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == _EntryAction.edit) {
      await _showEditEntryDialog(entry);
    } else if (action == _EntryAction.delete) {
      final confirmed = await _confirmDeleteEntry(entry);
      if (confirmed != true) return;
      await ref.read(fitnessRepositoryProvider).deleteEntry(entry.id);
      if (!mounted) return;
      _reload();
    }
  }

  Future<bool?> _confirmDeleteEntry(FitnessEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('確定要刪除這筆打卡？', style: TextStyle(color: AppColors.ink)),
        content: Text(
          '${_entryDateLabel(entry.loggedAt)}\n刪除後無法復原。',
          style: AppText.bodyDim,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.bad),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  /// 編輯只改運動類型跟時間，日期不變——跟日記編輯只改內容、不動
  /// 原始打卡日期同一個理由：日期是「哪天發生的」，不該因為編輯內容
  /// 就跑掉。
  Future<void> _showEditEntryDialog(FitnessEntry entry) async {
    var type = entry.type;
    var time = TimeOfDay.fromDateTime(entry.loggedAt);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('編輯打卡', style: TextStyle(color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in FitnessType.values)
                    _TypeChip(
                      type: t,
                      selected: t == type,
                      onTap: () => setDialogState(() => type = t),
                    ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              InkWell(
                onTap: () async {
                  var draft = time;
                  final confirmed = await showModalBottomSheet<bool>(
                    context: dialogContext,
                    backgroundColor: const Color(0xFF1A1A24),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (sheetContext) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                            child: Row(
                              children: [
                                Text('選打卡時間', style: AppText.body),
                                const Spacer(),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext, true),
                                  child: const Text('完成'),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 200,
                            child: CupertinoTheme(
                              data: const CupertinoThemeData(
                                brightness: Brightness.dark,
                              ),
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                initialDateTime: DateTime(
                                  2000,
                                  1,
                                  1,
                                  draft.hour,
                                  draft.minute,
                                ),
                                onDateTimeChanged: (t) => draft = TimeOfDay(
                                  hour: t.hour,
                                  minute: t.minute,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (confirmed == true) setDialogState(() => time = draft);
                },
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 15, color: AppColors.ink3),
                    const SizedBox(width: 6),
                    Text(
                      '時間 ${time.hour.toString().padLeft(2, '0')}:'
                      '${time.minute.toString().padLeft(2, '0')}',
                      style: AppText.note,
                    ),
                    const Spacer(),
                    const Icon(Icons.expand_more, size: 16, color: AppColors.ink3),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bgDeep,
              ),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final d = FitnessEntry.dayOnly(entry.date);
    await ref.read(fitnessRepositoryProvider).updateEntry(
      FitnessEntry(
        id: entry.id,
        date: d,
        type: type,
        loggedAt: DateTime(d.year, d.month, d.day, time.hour, time.minute),
      ),
    );
    if (!mounted) return;
    _reload();
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
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出打卡紀錄',
                    ),
                    IconButton(
                      onPressed: () => context.push('/fitness/stats'),
                      icon: const StatsIcon(size: 20, color: AppColors.ink2),
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
                              dayOffset: _dayOffset,
                              onDayOffsetChanged: (v) =>
                                  setState(() => _dayOffset = v),
                              pickedTime: _pickedTime,
                              onPickTime: _pickTime,
                            ),
                            const SizedBox(height: Gap.md),
                            if (entries.isNotEmpty) ...[
                              const PanelLabel('最近打卡'),
                              const SizedBox(height: Gap.xs),
                              GlassCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Column(
                                  children: [
                                    for (final e in _recentEntries(entries))
                                      _HistoryRow(
                                        entry: e,
                                        onTap: () => _showEntrySheet(e),
                                      ),
                                  ],
                                ),
                              ),
                            ],
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
    required this.dayOffset,
    required this.onDayOffsetChanged,
    required this.pickedTime,
    required this.onPickTime,
  });

  final Set<DateTime> days;
  final FitnessType selected;
  final ValueChanged<FitnessType> onSelect;
  final VoidCallback onCheckIn;
  final int dayOffset;
  final ValueChanged<int> onDayOffsetChanged;
  final TimeOfDay pickedTime;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final targetDay = FitnessEntry.dayOnly(
      DateTime.now().subtract(Duration(days: dayOffset)),
    );
    final doneThatDay = days.contains(targetDay);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  doneThatDay
                      ? '${_dayOffsetLabels[dayOffset]}已經打卡了，要再記一項嗎？'
                      : '${_dayOffsetLabels[dayOffset]}練了嗎？',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _DayOffsetDropdown(value: dayOffset, onChanged: onDayOffsetChanged),
            ],
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
          InkWell(
            onTap: onPickTime,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: AppColors.ink3),
                  const SizedBox(width: 6),
                  Text(
                    '打卡時間 ${pickedTime.hour.toString().padLeft(2, '0')}:'
                    '${pickedTime.minute.toString().padLeft(2, '0')}',
                    style: AppText.note,
                  ),
                  const Spacer(),
                  const Icon(Icons.expand_more, size: 16, color: AppColors.ink3),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xs),
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

/// 補寫今天／昨天／前天的小選單，跟日記的 `_DayOffsetDropdown` 同一套
/// 做法：用 [PopupMenuButton] 不是 [DropdownButton]，理由見
/// `diary_page.dart` 該元件的說明（固定貼著按鈕下面展開，不會因為選中
/// 項在清單下面就整個跳位置）。
class _DayOffsetDropdown extends StatelessWidget {
  const _DayOffsetDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      color: const Color(0xFF1A1A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      itemBuilder: (context) => [
        for (var i = 0; i < _dayOffsetLabels.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              _dayOffsetLabels[i],
              style: TextStyle(
                color: i == value ? AppColors.accent : AppColors.ink2,
                fontWeight: i == value ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        radius: Radii.chip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _dayOffsetLabels[value],
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: AppColors.ink3),
          ],
        ),
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

/// 「最近打卡」清單的一行，一部影片一行的密度，不是大卡片——這裡是
/// 快速瀏覽＋點進去改，不是主要瀏覽介面（日曆＋打卡卡片才是）。
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onTap});

  final FitnessEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Text(entry.type.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                entry.type.label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
              ),
            ),
            Text(_entryDateLabel(entry.loggedAt), style: AppText.note),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// 匯出的範圍：只匯出這台裝置 localStorage 裡的，還是連專案已經打包
/// 好的打卡快照一起，跟 `diary_page.dart`／`yt_tracker_home_page.dart`
/// 同一個用途。
enum _ExportScope { localOnly, withSeed }

Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(fitnessRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final FitnessRepository repo;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  _ExportScope _scope = _ExportScope.localOnly;
  late Future<({String text, int count})> _future;

  @override
  void initState() {
    super.initState();
    _future = _build(_scope);
  }

  Future<({String text, int count})> _build(_ExportScope scope) async {
    if (scope == _ExportScope.localOnly) {
      return widget.repo.exportJson();
    }
    final merged = mergeSeedRecords(
      local: await widget.repo.loadEntries(),
      seed: await loadFitnessSeed(),
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
    );
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in merged) e.toJson()]),
      count: merged.length,
    );
  }

  void _setScope(_ExportScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _future = _build(scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filename = 'lume-fitness-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出打卡紀錄',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_ExportScope>(
            segments: const [
              ButtonSegment(value: _ExportScope.localOnly, label: Text('僅這台裝置')),
              ButtonSegment(value: _ExportScope.withSeed, label: Text('連快照一起')),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => _setScope(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.glassFill,
              foregroundColor: AppColors.ink2,
              selectedBackgroundColor: AppColors.accent.withValues(alpha: 0.28),
              selectedForegroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.glassEdge),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FutureBuilder<({String text, int count})>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.md),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final data = snap.data!;
              final sizeLabel = _formatExportSize(utf8.encode(data.text).length);
              return Text(
                '$filename\n共 ${data.count} 筆 ・ 約 $sizeLabel',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
              );
            },
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () async {
            final data = await _future;
            final ok = saveTextFile(filename, data.text);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? '已下載 $filename' : '這個平台還不支援下載，改用複製')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.bgDeep,
          ),
          child: const Text('下載'),
        ),
        OutlinedButton(
          onPressed: () async {
            final data = await _future;
            await Clipboard.setData(ClipboardData(text: data.text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已複製到剪貼簿')));
          },
          child: const Text('複製'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

String _formatExportSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _exportTodayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}
