import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_exam.dart';
import '../../domain/models/kana_practice.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../kana_practice/kana_paper.dart';

/// 日文首頁右上角的「練習紀錄」（2026-10-16 使用者要求）：手寫練習、普通
/// 考試、點亮考試寫的每一個字都在這裡，一個字一筆、新的在上面、照日期分
/// 段。上面篩選「全部／手寫／考試／點亮」，點一筆重播筆畫。
///
/// 原本分開的兩頁還在：手寫紀錄（匯入匯出）、考試紀錄（按輪次、可改對錯），
/// 上面各一顆按鈕過去。
class JpLogPage extends ConsumerStatefulWidget {
  const JpLogPage({super.key, this.lightOnly = false});

  /// 從櫻花樹頁右上角進來：只看點亮考試的紀錄、不顯示篩選。
  final bool lightOnly;

  @override
  ConsumerState<JpLogPage> createState() => _JpLogPageState();
}

enum _Kind {
  practice('手寫'),
  exam('考試'),
  light('點亮');

  const _Kind(this.label);
  final String label;
}

/// 一筆紀錄（手寫或考試的一個字）。
class _Item {
  const _Item({
    required this.kind,
    required this.kana,
    required this.romaji,
    required this.at,
    required this.strokes,
    required this.tag,
    this.correct,
  });

  final _Kind kind;
  final String kana;
  final String romaji;
  final DateTime at;
  final List<List<(double, double, double)>> strokes;

  /// 右邊的小標：純手寫／輔助描摹、50 音／詞彙、點亮 X行。
  final String tag;

  /// 考試對錯；手寫是 null。
  final bool? correct;
}

final _jpLogProvider = FutureProvider.autoDispose<List<_Item>>((ref) async {
  ref.watch(dataRevisionProvider);
  final practice = await ref.read(kanaPracticeRepositoryProvider).loadAll();
  final exams = await ref.read(kanaExamRepositoryProvider).loadAll();
  return [
    for (final KanaPracticeEntry p in practice)
      if (p.deletedAt == null)
        _Item(
          kind: _Kind.practice,
          kana: p.kana,
          romaji: p.romaji,
          at: p.savedAt,
          strokes: p.strokes,
          tag: p.assisted ? '輔助描摹' : '純手寫',
        ),
    for (final KanaExamEntry e in exams)
      if (e.deletedAt == null)
        _Item(
          kind: e.lightRow != null ? _Kind.light : _Kind.exam,
          kana: e.kana,
          romaji: e.romaji,
          at: e.savedAt,
          strokes: e.strokes,
          tag: e.lightRow != null
              ? '點亮 ${e.lightRow}行'
              : e.examType == 'kana'
              ? '50 音'
              : '詞彙',
          correct: e.isCorrect,
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
});

class _JpLogPageState extends ConsumerState<JpLogPage> {
  /// null 是「全部」。
  late _Kind? _filter = widget.lightOnly ? _Kind.light : null;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_jpLogProvider);
    return Scaffold(
      drawer: const AppSideDrawer(),
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
                AppTopBar(title: widget.lightOnly ? '點亮紀錄' : '練習紀錄'),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: switch (async) {
                    AsyncData(:final value) => _body(value),
                    AsyncError(:final error) => Center(
                      child: Text('讀不到紀錄：$error', style: AppText.bodyDim),
                    ),
                    _ => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<_Item> all) {
    final shown = _filter == null
        ? all
        : all.where((i) => i.kind == _filter).toList();
    int count(_Kind k) => all.where((i) => i.kind == k).length;
    // 照日期分段：每天一個標題，後面是那天的紀錄。
    final rows = <Object>[];
    DateTime? day;
    for (final i in shown) {
      final d = DateTime(i.at.year, i.at.month, i.at.day);
      if (d != day) {
        rows.add(d);
        day = d;
      }
      rows.add(i);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.lightOnly) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip(
                  label: '全部',
                  count: all.length,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final k in _Kind.values) ...[
                  const SizedBox(width: 6),
                  _Chip(
                    label: k.label,
                    count: count(k),
                    selected: _filter == k,
                    onTap: () => setState(() => _filter = k),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => context.push('/kana-practice/history'),
                child: const Text('手寫紀錄（匯入匯出）'),
              ),
              TextButton(
                onPressed: () => context.push('/kana-exam/history'),
                child: const Text('考試紀錄（按輪次）'),
              ),
            ],
          ),
        ],
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('還沒有紀錄', style: AppText.bodyDim))
              : ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: FloatingNavInset.of(context) + Gap.lg,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, n) {
                    final r = rows[n];
                    if (r is DateTime) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Text(
                          '${r.year}/${r.month}/${r.day}',
                          style: AppText.note,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _Row(item: r as _Item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.jpAccent.withValues(alpha: 0.2)
            : AppColors.glassFill,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected
              ? AppColors.jpAccent.withValues(alpha: 0.7)
              : AppColors.glassEdge,
        ),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.jpAccent : AppColors.ink2,
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final i = item;
    String two(int n) => n.toString().padLeft(2, '0');
    final color = switch (i.kind) {
      _Kind.practice => AppColors.ink2,
      _Kind.exam => AppColors.accent,
      _Kind.light => AppColors.jpAccent,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _ReplayDialog(item: i),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassEdge),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: paperColor),
                    CustomPaint(
                      painter: InkPainter(
                        strokes: [
                          for (final s in i.strokes)
                            [for (final p in s) Offset(p.$1, p.$2)],
                        ],
                        strokeWidth: inkStrokeWidth(44),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              i.kana,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              i.romaji,
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
            const SizedBox(width: 8),
            Text('${two(i.at.hour)}:${two(i.at.minute)}', style: AppText.note),
            const Spacer(),
            if (i.correct != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  i.correct! ? Icons.check_rounded : Icons.close_rounded,
                  size: 18,
                  color: i.correct!
                      ? const Color(0xFF6EE7A0)
                      : const Color(0xFFFF8A8A),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                i.tag,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 點一筆重播筆畫（照原本的時間一筆一筆畫出來）。
class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog({required this.item});

  final _Item item;

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog>
    with SingleTickerProviderStateMixin {
  late final List<List<TimedPoint>> _strokes = [
    for (final s in widget.item.strokes)
      [for (final p in s) (Offset(p.$1, p.$2), p.$3)],
  ];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: math.max(
        1,
        ReplayInkPainter.totalDurationMs(_strokes).round(),
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (_strokes.isNotEmpty) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final has = _strokes.isNotEmpty;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: Text(
        '${i.kana}（${i.romaji}）・${i.tag}',
        style: const TextStyle(color: AppColors.ink, fontSize: 17),
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
                  if (has)
                    AnimatedBuilder(
                      animation: _c,
                      builder: (_, _) => CustomPaint(
                        painter: ReplayInkPainter(
                          strokes: _strokes,
                          elapsedMs: _c.value * _c.duration!.inMilliseconds,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!has) ...[
            const SizedBox(height: Gap.sm),
            const Text(
              '這一筆沒有落筆（例如考試直接按「不會」），沒有筆畫可以重播',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (has)
          TextButton.icon(
            onPressed: () => _c
              ..reset()
              ..forward(),
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('重播'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
