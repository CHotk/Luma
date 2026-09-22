import 'dart:convert' show utf8, JsonEncoder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/seed/diary_seed_loader.dart';
import '../../data/seed/seed_merge.dart';
import '../../domain/models/diary_entry.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';

/// 日記功能。走「極簡打卡」路線（設計稿 04），頂部日期跳轉條借設計稿
/// 02 的版面（2026-09-22 使用者拍板：頂部日期用 02 的，其餘照 04）。
///
/// 一天原則上打卡一次：今天已經記錄過，打卡卡會鎖住，要改就長按
/// 下面列表那一則刪掉重打，不是無限疊加同一天的紀錄。
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  late Future<List<DiaryEntry>> _future;
  final _textController = TextEditingController();
  String _mood = diaryMoods.first;

  @override
  void initState() {
    super.initState();
    _future = _loadWithSeedMerge();
  }

  /// 打開這頁那一瞬間先把日記快照（見 [loadDiarySeed]）併回本機，跟
  /// `kana_practice_history_page.dart` 的 `_loadWithSeedMerge` 同一套。
  Future<List<DiaryEntry>> _loadWithSeedMerge() async {
    final repo = ref.read(diaryRepositoryProvider);
    final seed = await loadDiarySeed();
    if (seed.isNotEmpty) await repo.mergeSeed(seed);
    return repo.loadAll();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = ref.read(diaryRepositoryProvider).loadAll();
    });
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(diaryRepositoryProvider);
    await repo.add(
      DiaryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        mood: _mood,
        text: text,
        savedAt: DateTime.now(),
      ),
    );
    _textController.clear();
    _mood = diaryMoods.first;
    _reload();
  }

  Future<void> _showEntry(DiaryEntry entry) async {
    final action = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  Text(entry.mood, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: Gap.sm),
                  Text(_dateLabel(entry.savedAt), style: AppText.bodyDim),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(entry.text, style: AppText.body),
              const SizedBox(height: Gap.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('刪除這篇'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.bad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (action != true) return;
    await ref.read(diaryRepositoryProvider).delete(entry.id);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const SizedBox(width: Gap.xs),
                    const Expanded(child: Text('日記', style: AppText.title)),
                    IconButton(
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出日記',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<DiaryEntry>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final all = [...snap.data!]
                        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
                      final today = DateTime.now();
                      final checkedInToday = all.any(
                        (e) => isSameDay(e.savedAt, today),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DateStrip(entries: all, onTapEntry: _showEntry),
                          const SizedBox(height: Gap.md),
                          _CheckInCard(
                            controller: _textController,
                            mood: _mood,
                            checkedInToday: checkedInToday,
                            onMoodChanged: (m) => setState(() => _mood = m),
                            onSubmit: _submit,
                          ),
                          const SizedBox(height: Gap.md),
                          const PanelLabel('最近'),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: all.isEmpty
                                ? Center(
                                    child: Text(
                                      '還沒有任何日記，上面打個卡開始吧',
                                      style: AppText.bodyDim,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: all.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: AppColors.glassEdge,
                                    ),
                                    itemBuilder: (_, i) => _SimpleRow(
                                      entry: all[i],
                                      onTap: () => _showEntry(all[i]),
                                    ),
                                  ),
                          ),
                        ],
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

/// 頂部日期跳轉條，借設計稿 02 的版面：橫向可滑動，本月每一天一顆，
/// 有打卡的日子下面標小點，點有打卡的日子直接跳出那篇內容
/// （2026-09-22 使用者拍板：頂部日期用 02 版）。
class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.entries, required this.onTapEntry});

  final List<DiaryEntry> entries;
  final void Function(DiaryEntry entry) onTapEntry;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // 同一天可能被打卡多次的歷史資料（例如刪了重打前的舊版本），
    // 只取最新一筆代表那一天。
    final byDay = <int, DiaryEntry>{};
    for (final e in entries) {
      if (e.savedAt.year == now.year && e.savedAt.month == now.month) {
        final day = e.savedAt.day;
        final existing = byDay[day];
        if (existing == null || e.savedAt.isAfter(existing.savedAt)) {
          byDay[day] = e;
        }
      }
    }

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: daysInMonth,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final day = i + 1;
          final entry = byDay[day];
          final isToday = day == now.day;
          return _DateChip(
            day: day,
            weekday: DateTime(now.year, now.month, day).weekday,
            hasEntry: entry != null,
            isToday: isToday,
            onTap: entry == null ? null : () => onTapEntry(entry),
          );
        },
      ),
    );
  }
}

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.day,
    required this.weekday,
    required this.hasEntry,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final int weekday;
  final bool hasEntry;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: hasEntry
              ? AppColors.diaryAccent.withValues(alpha: 0.16)
              : AppColors.glassFill,
          border: Border.all(
            color: isToday ? AppColors.diaryAccent : AppColors.glassEdge,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$day',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            Text(
              '週${_weekdayLabels[weekday - 1]}',
              style: const TextStyle(fontSize: 9, color: AppColors.ink3),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 4,
              height: 4,
              child: hasEntry
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.diaryAccent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 打卡卡：選心情＋一行文字＋送出，全部同一個操作完成（設計稿 04）。
/// 今天打過卡了就鎖住，不能重複打（要改就去下面列表刪掉那篇）。
class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.controller,
    required this.mood,
    required this.checkedInToday,
    required this.onMoodChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String mood;
  final bool checkedInToday;
  final ValueChanged<String> onMoodChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            checkedInToday ? '今天已經記錄過了 ✓' : '今天過得怎樣？一句話就好',
            style: AppText.bodyDim,
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              for (final m in diaryMoods) ...[
                Expanded(
                  child: _MoodButton(
                    mood: m,
                    selected: m == mood,
                    onTap: checkedInToday ? null : () => onMoodChanged(m),
                  ),
                ),
                if (m != diaryMoods.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !checkedInToday,
                  maxLength: 60,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '例如：把日記功能接上真的資料了',
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                onPressed: checkedInToday ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.diaryAccent,
                  foregroundColor: AppColors.diaryAccentInk,
                  disabledBackgroundColor: AppColors.glassFill,
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Icon(Icons.check, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final String mood;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? AppColors.diaryAccent.withValues(alpha: 0.26)
              : AppColors.glassFill,
          border: Border.all(
            color: selected ? AppColors.diaryAccent : AppColors.glassEdge,
          ),
        ),
        child: Text(mood, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}

/// 一行一則，滑過去就好，不是大卡片（設計稿 04）。
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(_shortDateLabel(entry.savedAt), style: AppText.note),
            ),
            Text(entry.mood, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                entry.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDateLabel(DateTime d) => '${d.month}/${d.day}';

String _dateLabel(DateTime d) {
  final weekday = _weekdayLabels[d.weekday - 1];
  return '${d.month} 月 ${d.day} 日・週$weekday';
}

/// 匯出的範圍：只匯出這台裝置 localStorage 裡的，還是連專案已經打包
/// 好的日記快照一起，跟 `kana_practice_history_page.dart` 的
/// `_ExportScope` 同一個用途。
enum _ExportScope { localOnly, withSeed }

Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(diaryRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final DiaryRepository repo;

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
      local: await widget.repo.loadAll(),
      seed: await loadDiarySeed(),
      idOf: (e) => e.id,
      // 本機為準：要的是「補齊這台裝置漏掉、但專案快照裡已經有」的
      // 紀錄，不是拿快照蓋掉這台裝置剛打的卡。
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
    final filename = 'lume-diary-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出日記',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_ExportScope>(
            segments: const [
              ButtonSegment(
                value: _ExportScope.localOnly,
                label: Text('僅這台裝置'),
              ),
              ButtonSegment(
                value: _ExportScope.withSeed,
                label: Text('連日記快照一起'),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => _setScope(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.glassFill,
              foregroundColor: AppColors.ink2,
              selectedBackgroundColor: AppColors.diaryAccent.withValues(
                alpha: 0.28,
              ),
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
              final sizeLabel = _formatExportSize(
                utf8.encode(data.text).length,
              );
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
            backgroundColor: AppColors.diaryAccent,
            foregroundColor: AppColors.diaryAccentInk,
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
