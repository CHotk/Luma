import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/repositories/kana_exam_repository.dart';
import '../../domain/models/kana_exam.dart';
import '../../shared/widgets/ambient_background.dart';
import '../kana_practice/kana_paper.dart';

/// 手寫考試的歷史紀錄。跟 [KanaPracticeHistoryPage] 是同一套結構、
/// 分開存檔——考試紀錄要能單獨看正確率、單獨匯出，混進練習紀錄裡
/// 反而看不出「這是考試表現」還是「這是隨便練練」（2026-09-21
/// 使用者要求：考試查看的歷史手寫紀錄要跟日常手寫區分開）。
class KanaExamHistoryPage extends ConsumerStatefulWidget {
  const KanaExamHistoryPage({super.key});

  @override
  ConsumerState<KanaExamHistoryPage> createState() =>
      _KanaExamHistoryPageState();
}

class _KanaExamHistoryPageState extends ConsumerState<KanaExamHistoryPage> {
  late Future<List<KanaExamEntry>> _future;

  /// null 表示「全部」。
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _future = ref.read(kanaExamRepositoryProvider).loadAll();
  }

  void _reload() {
    setState(() {
      _future = ref.read(kanaExamRepositoryProvider).loadAll();
    });
  }

  Future<void> _confirmClearAll() async {
    // 不可逆操作要二次確認，不能點一下就整份紀錄清空
    // （2026-09-21 使用者要求）。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('清空所有考試紀錄？', style: TextStyle(color: AppColors.ink)),
        content: const Text(
          '這個動作無法復原，這台裝置上的考試紀錄會全部刪除。',
          style: TextStyle(color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(kanaExamRepositoryProvider).clearAll();
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空所有考試紀錄')));
  }

  Future<void> _editEntry(KanaExamEntry entry) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Gap.sm),
            Text(
              '${entry.kana}（${entry.romaji}）',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: Gap.sm),
            ListTile(
              leading: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.ok,
              ),
              title: const Text(
                '標記為答對',
                style: TextStyle(color: AppColors.ink),
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, _EntryAction.markCorrect),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_rounded, color: AppColors.bad),
              title: const Text(
                '標記為答錯',
                style: TextStyle(color: AppColors.ink),
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, _EntryAction.markIncorrect),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.bad),
              title: const Text(
                '刪除這筆紀錄',
                style: TextStyle(color: AppColors.bad),
              ),
              onTap: () => Navigator.pop(sheetContext, _EntryAction.delete),
            ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
    if (action == null) return;

    final repo = ref.read(kanaExamRepositoryProvider);
    switch (action) {
      case _EntryAction.markCorrect:
        await repo.upsert(_copyWith(entry, isCorrect: true));
      case _EntryAction.markIncorrect:
        await repo.upsert(_copyWith(entry, isCorrect: false));
      case _EntryAction.delete:
        await repo.delete(entry.id);
    }
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
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
                    const Expanded(child: Text('考試紀錄', style: AppText.title)),
                    IconButton(
                      onPressed: _confirmClearAll,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      color: AppColors.ink2,
                      tooltip: '清空紀錄',
                    ),
                    IconButton(
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出紀錄',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<KanaExamEntry>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final all = [...snap.data!]
                        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
                      if (all.isEmpty) {
                        return Center(
                          child: Text('還沒有任何考試紀錄', style: AppText.bodyDim),
                        );
                      }

                      final kanaCount = all
                          .where((e) => e.examType == 'kana')
                          .length;
                      final vocabCount = all.length - kanaCount;

                      final filtered = _typeFilter == null
                          ? all
                          : all
                                .where((e) => e.examType == _typeFilter)
                                .toList();
                      final correct = filtered.where((e) => e.isCorrect).length;
                      final accuracy = filtered.isEmpty
                          ? 0
                          : (correct / filtered.length * 100).round();

                      // 按 roundId 分組成一輪一輪——filtered 已經是新到
                      // 舊排序，同一輪裡第一筆自然就是那一輪最新的一筆，
                      // 拿來當這一輪的排序依據跟顯示時間就夠，不用另外
                      // 存「這一輪何時開始」（2026-09-21 使用者要求：
                      // 要有輪次）。
                      final rounds = <String, List<KanaExamEntry>>{};
                      for (final e in filtered) {
                        (rounds[e.roundId] ??= []).add(e);
                      }
                      final roundList = rounds.values.toList()
                        ..sort(
                          (a, b) => b.first.savedAt.compareTo(a.first.savedAt),
                        );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _FilterChip(
                                label: '全部',
                                count: all.length,
                                selected: _typeFilter == null,
                                onTap: () => setState(() => _typeFilter = null),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '50 音',
                                count: kanaCount,
                                selected: _typeFilter == 'kana',
                                onTap: () =>
                                    setState(() => _typeFilter = 'kana'),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '詞彙',
                                count: vocabCount,
                                selected: _typeFilter == 'vocab',
                                onTap: () =>
                                    setState(() => _typeFilter = 'vocab'),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            '正確率 $accuracy%（$correct / ${filtered.length} 題）',
                            style: AppText.note,
                          ),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: roundList.isEmpty
                                ? Center(
                                    child: Text(
                                      '沒有符合篩選條件的紀錄',
                                      style: AppText.bodyDim,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: roundList.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: Gap.sm),
                                    itemBuilder: (_, i) => _RoundCard(
                                      entries: roundList[i],
                                      onEditEntry: _editEntry,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.jpAccent.withValues(alpha: 0.28)
              : AppColors.glassFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.jpAccent.withValues(alpha: 0.6)
                : AppColors.glassEdge,
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// 一輪考試的摘要卡片：時間、題型、題數、正確率，點一下展開看這輪
/// 逐題的明細（2026-09-21 使用者要求：要有輪次，不是扁平的一堆
/// 題目）。
class _RoundCard extends StatefulWidget {
  const _RoundCard({required this.entries, required this.onEditEntry});

  /// 同一輪的所有題目，呼叫端已經是新到舊排序。
  final List<KanaExamEntry> entries;
  final void Function(KanaExamEntry entry) onEditEntry;

  @override
  State<_RoundCard> createState() => _RoundCardState();
}

class _RoundCardState extends State<_RoundCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final latest = entries.first.savedAt;
    final correct = entries.where((e) => e.isCorrect).length;
    final accuracy = (correct / entries.length * 100).round();
    final examType = entries.first.examType;

    String two(int n) => n.toString().padLeft(2, '0');
    final timeLabel =
        '${latest.month}/${latest.day} ${two(latest.hour)}:${two(latest.minute)}:${two(latest.second)}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        border: Border.all(color: AppColors.glassEdge),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.jpAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      examType == 'kana' ? '50 音' : '詞彙',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.jpAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '正確率 $accuracy%（$correct / ${entries.length} 題）',
                          style: AppText.note,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
              child: Column(
                children: [
                  const Divider(color: AppColors.glassEdge, height: Gap.md),
                  for (final entry in entries) ...[
                    _EntryCard(
                      entry: entry,
                      onLongPress: () => widget.onEditEntry(entry),
                    ),
                    if (entry != entries.last) const SizedBox(height: Gap.xs),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _EntryAction { markCorrect, markIncorrect, delete }

KanaExamEntry _copyWith(KanaExamEntry entry, {required bool isCorrect}) =>
    KanaExamEntry(
      id: entry.id,
      roundId: entry.roundId,
      kana: entry.kana,
      romaji: entry.romaji,
      isCorrect: isCorrect,
      examType: entry.examType,
      savedAt: entry.savedAt,
      imageBase64: entry.imageBase64,
      strokes: entry.strokes,
    );

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onLongPress});

  final KanaExamEntry entry;

  /// 長按跳出操作選單：標記答對／答錯（真的改資料，不只是畫面上換
  /// 圖示）、刪除這筆紀錄（2026-09-21 使用者要求）。
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final time = entry.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    // 精確到秒——同一輪裡好幾題可能落在同一分鐘，只到分鐘看不出
    // 先後順序（2026-09-21 使用者要求：每一次答對答錯都要精確記錄
    // 時間）。
    final timeLabel =
        '${time.month}/${time.day} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';

    return InkWell(
      // 單擊重播這一題當下的手寫過程，長按才是修改/刪除——重播不動
      // 資料，長按才是有破壞性的操作，兩個手勢分開才不會誤觸
      // （2026-09-21 使用者要求：點個別答題要能跳出視窗自動重播）。
      // 「不會」按下去時如果根本沒落筆，strokes 會是空的——這種還是
      // 要能點開，只是對話框裡老實講「沒有落筆」，不能整個沒反應讓人
      // 以為壞掉（2026-09-21 使用者回報：答錯的不能看）。
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _ExamReplayDialog(entry: entry),
      ),
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassEdge),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: paperColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: entry.strokes.isEmpty
                  ? Text(
                      entry.kana,
                      style: const TextStyle(fontSize: 20, color: inkColor),
                    )
                  // CustomPaint 沒指定 size、外層 Container 又有
                  // alignment，會收縮成 0×0 置中顯示，所有筆畫座標都被
                  // 壓成同一個點——縮圖就只看到正中間一個黑點，字完全
                  // 看不出來（2026-09-21 使用者回報，bug 根源）。
                  : CustomPaint(
                      size: const Size(48, 48),
                      painter: InkPainter(
                        strokes: [
                          for (final stroke in entry.strokes)
                            [for (final p in stroke) Offset(p.$1, p.$2)],
                        ],
                        strokeWidth: inkStrokeWidth(48),
                      ),
                    ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.kana,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.romaji,
                        style: TextStyle(fontSize: 12, color: AppColors.ink3),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.jpAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entry.examType == 'kana' ? '50 音' : '詞彙',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.jpAccent,
                          ),
                        ),
                      ),
                      // 一筆都沒寫直接按「不會」——跟「有寫但自評寫錯」
                      // 是兩種不同狀態，光看紅色叉叉分不出來，直接標
                      // 「放棄」比開對話框才知道更明確（2026-09-21
                      // 使用者要求）。
                      if (entry.strokes.isEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.ink3.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '放棄',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(timeLabel, style: AppText.note),
                ],
              ),
            ),
            Icon(
              entry.isCorrect
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: entry.isCorrect ? AppColors.ok : AppColors.bad,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// 點單題跳出來的重播對話框：把這一題當下的筆畫過程照原始節奏播一次
/// ——跟練習頁的重播是同一顆 [ReplayInkPainter]，考試紀錄本來就存了
/// 完整的 `(x, y, t)`，沒道理另外做一套（2026-09-21 使用者要求）。
class _ExamReplayDialog extends StatefulWidget {
  const _ExamReplayDialog({required this.entry});

  final KanaExamEntry entry;

  @override
  State<_ExamReplayDialog> createState() => _ExamReplayDialogState();
}

class _ExamReplayDialogState extends State<_ExamReplayDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<List<TimedPoint>> _strokes;

  bool get _hasStrokes => _strokes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _strokes = [
      for (final stroke in widget.entry.strokes)
        [for (final p in stroke) (Offset(p.$1, p.$2), p.$3)],
    ];
    final totalMs = ReplayInkPainter.totalDurationMs(_strokes);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs <= 0 ? 1 : totalMs.round()),
    );
    if (_hasStrokes) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.kana}（${entry.romaji}）',
            style: const TextStyle(color: AppColors.ink),
          ),
          const SizedBox(width: 8),
          Icon(
            entry.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: entry.isCorrect ? AppColors.ok : AppColors.bad,
            size: 18,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: paperColor),
                  const CustomPaint(painter: PaperGridPainter()),
                  // 沒落筆就是空白紙——不能在這裡塞正確答案充版面，
                  // 使用者會誤以為「這格筆跡就是標準答案」，混淆到底是
                  // 自己寫的還是系統填的（2026-09-21 使用者回報：完全
                  // 沒寫的題目，預覽不應該顯示標準答案）。
                  if (_hasStrokes)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (_, _) => CustomPaint(
                        painter: ReplayInkPainter(
                          strokes: _strokes,
                          elapsedMs:
                              _controller.value *
                              _controller.duration!.inMilliseconds,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 按「不會」時如果根本沒落筆，就沒有筆畫可以重播——老實講清楚
          // 是「沒寫」，不要讓對話框看起來像壞掉或空白（2026-09-21
          // 使用者回報：答錯的不能看）。
          if (!_hasStrokes) ...[
            const SizedBox(height: Gap.sm),
            const Text(
              '這題按了「不會」沒有落筆，沒有筆畫紀錄可以重播',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (_hasStrokes)
          TextButton.icon(
            onPressed: () {
              _controller.reset();
              _controller.forward();
            },
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('重播'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.jpAccent,
            foregroundColor: AppColors.jpAccentInk,
          ),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(kanaExamRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final KanaExamRepository repo;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late final Future<({String text, int count})> _future = widget.repo
      .exportJson();

  @override
  Widget build(BuildContext context) {
    final filename = 'lume-kana-exam-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出考試紀錄',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: FutureBuilder<({String text, int count})>(
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
            backgroundColor: AppColors.jpAccent,
            foregroundColor: AppColors.jpAccentInk,
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
