import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/drinking_stats.dart';
import '../../domain/models/drinking_entry.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

const _cooldownLength = Duration(minutes: 10);

/// 喝酒記錄（2026-09-24 使用者要求：記錄多久一次，督促自己不要太頻繁；
/// 看盤／抽菸／喝酒各自獨立一份，不共用程式）。版面取自設計稿
/// `design-history/看盤頻率記錄設計/`：03 的「距離上次」計時器＋冷靜按鈕、
/// 01 的最近紀錄清單、02 的月曆日期格子；05 的統計放在右上角統計按鈕進去的子頁。
class DrinkingPage extends ConsumerStatefulWidget {
  const DrinkingPage({super.key});

  @override
  ConsumerState<DrinkingPage> createState() => _DrinkingPageState();
}

class _DrinkingPageState extends ConsumerState<DrinkingPage> {
  List<DrinkingEntry> _entries = const [];
  bool _loaded = false;
  Timer? _tick;
  DateTime _now = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = dayOf(DateTime.now());

  /// 冷靜倒數結束的時間，null 代表沒在冷靜。只存在這個畫面，離開就重來。
  DateTime? _cooldownEnd;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_cooldownEnd != null && !_now.isBefore(_cooldownEnd!)) {
          _cooldownEnd = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await ref.read(drinkingRepositoryProvider).loadAll();
    if (mounted) {
      setState(() {
        _entries = all;
        _loaded = true;
      });
    }
  }

  Future<void> _record() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '為什麼想喝？（選填）',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in const ['社交', '壓力', '無聊', '慶祝', '睡前', '其他'])
                    ActionChip(
                      label: Text(r),
                      onPressed: () => Navigator.pop(sheetContext, r),
                    ),
                ],
              ),
              const SizedBox(height: Gap.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, ''),
                  child: const Text('直接記錄'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // null＝點空白處關掉，不記錄；空字串＝直接記錄、沒選原因。
    if (reason == null) return;
    await ref
        .read(drinkingRepositoryProvider)
        .add(reason: reason.isEmpty ? null : reason);
    setState(() {
      _cooldownEnd = null;
      _now = DateTime.now();
      _selectedDay = dayOf(_now);
      _month = DateTime(_now.year, _now.month);
    });
    await _load();
  }

  Future<void> _confirmDelete(DrinkingEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('刪除這筆紀錄？', style: TextStyle(color: AppColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(drinkingRepositoryProvider).delete(e.id);
    await _load();
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
                  title: '喝酒記錄',
                  showBack: false,
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/drinking-log/stats'),
                      icon: const Icon(Icons.bar_chart_rounded, size: 22),
                      color: AppColors.ink2,
                      tooltip: '統計',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: !_loaded
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          children: [
                            _buildTimerCard(),
                            const SizedBox(height: Gap.md),
                            _buildCooldownCard(),
                            const SizedBox(height: Gap.md),
                            _buildRecordButton(),
                            const SizedBox(height: Gap.lg),
                            _buildCalendarCard(),
                            const SizedBox(height: Gap.lg),
                            _buildRecentList(),
                            const SizedBox(height: Gap.lg),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 距離上次計時器（設計稿 03）──────────────────────────────

  Widget _buildTimerCard() {
    final last = _entries.isEmpty ? null : _entries.first.at;
    final since = last == null ? null : _now.difference(last);
    final todayCount = _entries.where((e) => dayOf(e.at) == dayOf(_now)).length;
    final longest = longestGapOnDay(_entries, _now, _now);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 15),
      child: Column(
        children: [
          Text('距離上次喝酒', style: AppText.note),
          const SizedBox(height: Gap.sm),
          Text(
            since == null ? '--:--:--' : _clock(since),
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: since == null ? AppColors.ink3 : AppColors.ok,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            since == null
                ? '還沒有紀錄，喝完按下面的按鈕記一筆'
                : '今天已喝 $todayCount 杯'
                      '${longest == null ? '' : '・今天最長撐過 ${formatDuration(longest)}'}',
            style: AppText.note,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  // ── 冷靜按鈕（設計稿 03）────────────────────────────────────

  Widget _buildCooldownCard() {
    final end = _cooldownEnd;
    final remaining = end?.difference(_now);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '想喝了嗎？',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            remaining == null
                ? '先喝杯水，10 分鐘後還想喝再喝。'
                : '冷靜中… 還剩 ${_clock(remaining).substring(3)}，撐住。',
            style: AppText.bodyDim,
          ),
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _cooldownEnd = remaining == null
                    ? DateTime.now().add(_cooldownLength)
                    : null;
              }),
              icon: Icon(
                remaining == null
                    ? Icons.hourglass_bottom_rounded
                    : Icons.close_rounded,
                size: 18,
              ),
              label: Text(remaining == null ? '先忍 10 分鐘' : '取消'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _record,
        icon: const Icon(Icons.visibility_outlined, size: 20),
        label: Text('我剛喝了一杯（重新計時）'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  // ── 月曆日期格子（設計稿 02）────────────────────────────────

  Widget _buildCalendarCard() {
    final counts = countsByDay(_entries);
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7; // 週日 = 0
    final isThisMonth = _month.year == _now.year && _month.month == _now.month;
    final elapsedDays = isThisMonth ? _now.day : daysInMonth;
    var monthTotal = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      monthTotal += counts[DateTime(_month.year, _month.month, d)] ?? 0;
    }
    final avg = elapsedDays == 0 ? 0.0 : monthTotal / elapsedDays;
    final selectedEntries =
        _entries.where((e) => dayOf(e.at) == _selectedDay).toList()
          ..sort((a, b) => a.at.compareTo(b.at));

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
                color: AppColors.ink2,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '${_month.year} 年 ${_month.month} 月',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
                color: AppColors.ink2,
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text('平均每天 ${avg.toStringAsFixed(1)} 次', style: AppText.note),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(child: Text(w, style: AppText.note)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _dayCell(DateTime(_month.year, _month.month, d), counts),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _legend(const Color(0xFF3B5B3C), '1–2 次'),
              const SizedBox(width: 12),
              _legend(const Color(0xFFB8902F), '3–4 次'),
              const SizedBox(width: 12),
              _legend(const Color(0xFFC65A52), '5+ 次'),
            ],
          ),
          const Divider(height: 22, color: AppColors.glassEdge),
          Text(
            '${_selectedDay.month}/${_selectedDay.day}・'
            '${selectedEntries.length} 次',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Gap.xs),
          if (selectedEntries.isEmpty)
            Text('這天沒有紀錄', style: AppText.note)
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in selectedEntries)
                  Text(_hm(e.at), style: AppText.bodyDim),
              ],
            ),
        ],
      ),
    );
  }

  Color _cellColor(int n) {
    if (n == 0) return const Color(0xFF1E1E2E);
    if (n <= 2) return const Color(0xFF3B5B3C);
    if (n <= 4) return const Color(0xFFB8902F);
    return const Color(0xFFC65A52);
  }

  Widget _dayCell(DateTime day, Map<DateTime, int> counts) {
    final n = counts[day] ?? 0;
    final selected = day == _selectedDay;
    final isToday = day == dayOf(_now);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedDay = day),
      child: Container(
        decoration: BoxDecoration(
          color: _cellColor(n),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : isToday
                ? AppColors.ink2
                : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          n > 0 ? '$n' : '${day.day}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w400,
            color: n > 0 ? Colors.white : AppColors.ink3,
          ),
        ),
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppText.note),
    ],
  );

  // ── 最近紀錄（設計稿 01）────────────────────────────────────

  Widget _buildRecentList() {
    final recent = _entries.take(10).toList();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近紀錄',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Gap.xs),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('還沒有紀錄', style: AppText.bodyDim),
            )
          else
            for (final e in recent)
              InkWell(
                onLongPress: () => _confirmDelete(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        _when(e.at),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_relative(e.at), style: AppText.note),
                      const Spacer(),
                      if (e.reason != null)
                        Text(e.reason!, style: AppText.note),
                    ],
                  ),
                ),
              ),
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('長按一筆可刪除', style: AppText.note),
            ),
        ],
      ),
    );
  }

  String _hm(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _when(DateTime t) {
    if (dayOf(t) == dayOf(_now)) return _hm(t);
    if (dayOf(t) == dayOf(_now).subtract(const Duration(days: 1))) {
      return '昨天 ${_hm(t)}';
    }
    return '${t.month}/${t.day} ${_hm(t)}';
  }

  String _relative(DateTime t) {
    final diff = _now.difference(t);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }
}
