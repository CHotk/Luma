import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/crypto_watch_stats.dart';
import '../../domain/models/trade_entry.dart';
import '../../domain/trade_stats.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'trade_data.dart';
import 'trade_ui.dart';

const _cooldownLength = Duration(minutes: 10);

/// 交易&自律（2026-10-08 使用者要求把「看盤記錄」改成這個名字，整合看盤
/// 次數跟每一單的損益）。版面照 `design-history/已選擇完成/2026-10-08_投資與自律五種設計.html`
/// 使用者挑的組合：
/// - 版本 3 的看盤卡片放最上面（距離上次看盤、冷靜 10 分鐘、看了）——
///   使用者明講兩個功能都要，不能只剩損益；
/// - 版本 2 的月曆：每格寫當天損益（綠賺紅賠）＋右上角看盤次數，點一天
///   進「那天發生什麼」；
/// - 右上角「交易日誌」接版本 4 的卡片流，「月報」是版本 3 的自律成績單
///   ＋版本 4 的什麼樣的單在賺，每個月（含當月）都能看。
class CryptoWatchPage extends ConsumerStatefulWidget {
  const CryptoWatchPage({super.key});

  @override
  ConsumerState<CryptoWatchPage> createState() => _CryptoWatchPageState();
}

class _CryptoWatchPageState extends ConsumerState<CryptoWatchPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 甘特圖點選的那一單，月曆上那幾天跟著亮起來；再點一次取消。
  String? _ganttSel;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(tradeDataProvider).valueOrNull;
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
                  title: '交易&自律',
                  titleIcon: Icons.candlestick_chart_outlined,
                  showBack: false,
                  actions: [
                    _barIcon(
                      Icons.receipt_long_outlined,
                      '交易日誌',
                      () => context.push('/crypto-watch/journal'),
                    ),
                    _barIcon(
                      Icons.insert_chart_outlined_rounded,
                      '月報',
                      () => context.push(
                        '/crypto-watch/report?m=${_month.year}-${_month.month}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          children: [
                            _WatchCard(data: data),
                            const SizedBox(height: Gap.md),
                            _buildMonthCard(data),
                            if (_monthTrades(data).isNotEmpty) ...[
                              const SizedBox(height: Gap.md),
                              _buildGantt(data),
                            ],
                            if (data.openTrades.isNotEmpty) ...[
                              const SizedBox(height: Gap.lg),
                              _sectionTitle('持倉中', '點一下去平倉'),
                              for (final t in data.openTrades)
                                TradeCard(
                                  trade: t,
                                  onTap: () =>
                                      openTradeFlow(context, ref, t, data),
                                ),
                            ],
                            const SizedBox(height: Gap.md),
                            FilledButton.icon(
                              onPressed: () => addTradeFlow(context, ref),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('記一筆交易'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: Gap.sm),
                            Row(
                              children: [
                                Expanded(
                                  child: _linkButton(
                                    Icons.receipt_long_outlined,
                                    '交易日誌',
                                    () => context.push('/crypto-watch/journal'),
                                  ),
                                ),
                                const SizedBox(width: Gap.sm),
                                Expanded(
                                  child: _linkButton(
                                    Icons.insert_chart_outlined_rounded,
                                    '${_month.month} 月月報',
                                    () => context.push(
                                      '/crypto-watch/report'
                                      '?m=${_month.year}-${_month.month}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Gap.xl),
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

  Widget _barIcon(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        color: AppColors.ink2,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      );

  Widget _linkButton(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.glassEdge),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );

  Widget _sectionTitle(String title, String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink2,
          ),
        ),
        const Spacer(),
        Text(hint, style: AppText.note.copyWith(color: AppColors.ink3)),
      ],
    ),
  );

  // ── 月曆：損益＋看盤次數（設計稿版本 2）────────────────────

  Widget _buildMonthCard(TradeData data) {
    final now = DateTime.now();
    final sum = data.month(_month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month).weekday % 7;
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    final elapsed = isThisMonth ? now.day : daysInMonth;
    var watchTotal = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      watchTotal +=
          data.watchCounts[DateTime(_month.year, _month.month, d)] ?? 0;
    }
    final ret = sum.returnPercent;
    final holdDays = <DateTime>{};
    final litDays = <DateTime>{};
    for (final t in _monthTrades(data)) {
      final days = _daysOf(t);
      holdDays.addAll(days);
      if (t.id == _ganttSel) litDays.addAll(days);
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (!isThisMonth)
                TextButton(
                  onPressed: () =>
                      setState(() => _month = DateTime(now.year, now.month)),
                  child: const Text('回本月'),
                ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              _kpi(fmtPnl(sum.total), '本月損益', color: pnlColor(sum.total)),
              const SizedBox(width: 6),
              _kpi(
                ret == null ? '設定' : fmtPct(ret),
                // 月初資金的數字直接寫出來（2026-10-08 使用者回報：設定完
                // 只看到 0.0%，看不到剛填的金額，以為沒存到）。
                ret == null
                    ? '月初資金'
                    : '月初 ${fmtAmount(data.capitalOf(_month)!)}',
                color: ret == null ? AppColors.accent : pnlColor(ret),
                onTap: () => editCapitalFlow(
                  context,
                  ref,
                  _month,
                  data.capitalOf(_month),
                ),
              ),
              const SizedBox(width: 6),
              _kpi(
                elapsed == 0 ? '—' : (watchTotal / elapsed).toStringAsFixed(1),
                '日均看盤',
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
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
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.78,
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _dayCell(
                  DateTime(_month.year, _month.month, d),
                  pnl: sum.dayPnl[DateTime(_month.year, _month.month, d)],
                  watches:
                      data.watchCounts[DateTime(
                        _month.year,
                        _month.month,
                        d,
                      )] ??
                      0,
                  hold: holdDays.contains(
                    DateTime(_month.year, _month.month, d),
                  ),
                  lit: litDays.contains(DateTime(_month.year, _month.month, d)),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend(tradeUp.withValues(alpha: 0.4), '賺'),
              _legend(tradeDown.withValues(alpha: 0.4), '賠'),
              _legend(AppColors.mid.withValues(alpha: 0.45), '底部黃線＝有抱單'),
              Text('👁 看盤次數', style: AppText.note),
              Text(
                '👁 黃＝超過 $heavyWatchThreshold 次',
                style: AppText.note.copyWith(color: AppColors.mid),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '點某一天看那天發生什麼・損益記在平倉那天',
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  Widget _kpi(
    String value,
    String label, {
    Color color = AppColors.ink,
    VoidCallback? onTap,
  }) => Expanded(
    child: Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                onTap == null ? label : '$label ✎',
                style: AppText.note.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _dayCell(
    DateTime day, {
    required double? pnl,
    required int watches,
    required bool hold,
    required bool lit,
  }) {
    final now = DateTime.now();
    final isToday = day == dayOf(now);
    final future = day.isAfter(dayOf(now));
    final strength = pnl == null ? 0.0 : (pnl.abs() / 250).clamp(0.0, 1.0);
    final bg = pnl == null || pnl == 0
        ? Colors.white.withValues(alpha: 0.035)
        : (pnl > 0 ? tradeUp : tradeDown).withValues(
            alpha: 0.12 + strength * 0.3,
          );
    final heavy = watches > heavyWatchThreshold;
    return Opacity(
      opacity: future ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: future
              ? null
              : () => context.push(
                  '/crypto-watch/day/${day.year}-${day.month}-${day.day}',
                ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: isToday
                  ? Border.all(color: AppColors.ink2, width: 1)
                  : null,
            ),
            foregroundDecoration: lit
                ? BoxDecoration(
                    color: AppColors.mid.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  )
                : null,
            child: Stack(
              children: [
                Padding(
                  // 底部留位置給持倉黃線，損益數字不壓在線上。
                  padding: const EdgeInsets.fromLTRB(4, 3, 3, 7),
                  child: Stack(
                    children: [
                      Text(
                        '${day.day}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.ink3,
                        ),
                      ),
                      if (watches > 0)
                        Align(
                          alignment: Alignment.topRight,
                          child: Text(
                            '👁$watches',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: heavy
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                              color: heavy ? AppColors.mid : AppColors.ink2,
                            ),
                          ),
                        ),
                      if (pnl != null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              fmtPnl(pnl),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: pnlColor(pnl),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 持倉期間：格子最底部、在格子裡面的一條淡黃線（2026-10-08
                // 使用者挑設計稿版本 3，要求放格子底部、顏色淡一點）。
                if (hold)
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 2,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.mid.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 下方甘特圖（設計稿版本 3）────────────────────────────

  /// 持倉期間碰到這個月的單（含持倉中），依開倉時間排。
  List<TradeEntry> _monthTrades(TradeData data) {
    final start = DateTime(_month.year, _month.month);
    final end = DateTime(_month.year, _month.month + 1);
    final now = DateTime.now();
    return data.trades
        .where(
          (t) =>
              t.openedAt.isBefore(end) && !(t.closedAt ?? now).isBefore(start),
        )
        .toList()
      ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
  }

  /// 這一單在這個月裡抱著的每一天。
  List<DateTime> _daysOf(TradeEntry t) {
    final start = DateTime(_month.year, _month.month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    var d = dayOf(t.openedAt);
    final endDay = dayOf(t.closedAt ?? DateTime.now());
    if (d.isBefore(start)) d = start;
    final out = <DateTime>[];
    while (!d.isAfter(endDay) && !d.isAfter(last)) {
      out.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// 月曆下面的甘特圖：一單一條，長度精確到小時（半夜開、隔天中午平都
  /// 看得出來），右端小色塊綠賺紅賠，持倉中的條一路到藍色「今天」線。點一條，
  /// 月曆上那幾天亮起來、下面出那一單的卡片。
  Widget _buildGantt(TradeData data) {
    final list = _monthTrades(data);
    final start = DateTime(_month.year, _month.month);
    final end = DateTime(_month.year, _month.month + 1);
    final span = end.difference(start).inMinutes.toDouble();
    double frac(DateTime t) =>
        (t.difference(start).inMinutes / span).clamp(0.0, 1.0);
    final now = DateTime.now();
    final showToday = now.isAfter(start) && now.isBefore(end);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final ticks = [1, 8, 15, 22, 29].where((d) => d <= daysInMonth).toList();
    const labelW = 68.0;
    final sel = list.where((t) => t.id == _ganttSel).firstOrNull;

    Widget grid(double w, {bool labels = false}) => Stack(
      clipBehavior: Clip.none,
      children: [
        for (final d in ticks)
          Positioned(
            left: frac(DateTime(_month.year, _month.month, d)) * w,
            top: 0,
            bottom: 0,
            child: labels
                ? FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: Text(
                      '${_month.month}/$d',
                      style: AppText.note.copyWith(
                        fontSize: 9,
                        color: AppColors.ink3,
                      ),
                    ),
                  )
                : Container(width: 1, color: const Color(0xFF2A2A3D)),
          ),
        if (showToday && !labels)
          Positioned(
            left: frac(now) * w,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.5,
              color: AppColors.accent.withValues(alpha: 0.7),
            ),
          ),
      ],
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${_month.month} 月持倉期間', style: AppText.note),
              const Spacer(),
              Text(
                '${list.length} 單・點一條在月曆上標出',
                style: AppText.note.copyWith(color: AppColors.ink3),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              const SizedBox(width: labelW),
              Expanded(
                child: SizedBox(
                  height: 14,
                  child: LayoutBuilder(
                    builder: (_, c) => grid(c.maxWidth, labels: true),
                  ),
                ),
              ),
            ],
          ),
          for (final t in list)
            InkWell(
              onTap: () =>
                  setState(() => _ganttSel = _ganttSel == t.id ? null : t.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: t.id == _ganttSel
                      ? AppColors.mid.withValues(alpha: 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Text(
                        '${t.symbol}${t.isLong ? '多' : '空'} ${fmtLev(t.leverage)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.note.copyWith(fontSize: 10.5),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final w = c.maxWidth;
                          final l = frac(t.openedAt) * w;
                          final r = frac(t.closedAt ?? now) * w;
                          return Stack(
                            children: [
                              grid(w),
                              Positioned(
                                left: l,
                                width: (r - l).clamp(4.0, w),
                                top: 6,
                                height: 12,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.mid.withValues(
                                      alpha: t.isOpen ? 0.3 : 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    border: t.isOpen
                                        ? Border.all(
                                            color: AppColors.mid.withValues(
                                              alpha: 0.6,
                                            ),
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: t.isOpen
                                      ? null
                                      : Container(
                                          width: 5,
                                          decoration: BoxDecoration(
                                            color: pnlColor(t.pnl),
                                            borderRadius:
                                                const BorderRadius.horizontal(
                                                  right: Radius.circular(6),
                                                ),
                                          ),
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
          if (sel != null) ...[
            const SizedBox(height: Gap.sm),
            TradeCard(
              trade: sel,
              onTap: () => openTradeFlow(context, ref, sel, data),
            ),
          ],
        ],
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
}

/// 看盤卡片（設計稿版本 3）：距離上次看盤、今天幾次、先冷靜 10 分鐘、
/// 看了（重新計時）。每秒重畫只重畫這張卡，不拖著整頁月曆一起重算。
class _WatchCard extends ConsumerStatefulWidget {
  const _WatchCard({required this.data});

  final TradeData data;

  @override
  ConsumerState<_WatchCard> createState() => _WatchCardState();
}

class _WatchCardState extends ConsumerState<_WatchCard> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  /// 冷靜倒數結束的時間，null 代表沒在冷靜。只存在這個畫面，離開就重來。
  DateTime? _cooldownEnd;

  @override
  void initState() {
    super.initState();
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

  Future<void> _looked() async {
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
              const Text(
                '為什麼想看？（選填）',
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
                  for (final r in const ['焦慮', '無聊', '例行', '有持倉', '睡前', '其他'])
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
        .read(cryptoWatchRepositoryProvider)
        .add(reason: reason.isEmpty ? null : reason);
    ref.read(dataRevisionProvider.notifier).state++;
    if (mounted) setState(() => _cooldownEnd = null);
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final watches = widget.data.watches;
    final last = watches.isEmpty ? null : watches.first.at;
    final since = last == null ? null : _now.difference(last);
    final today = widget.data.watchCounts[dayOf(_now)] ?? 0;
    final longest = longestGapOnDay(watches, _now, _now);
    final cooling = _cooldownEnd?.difference(_now);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.ink2,
              ),
              const SizedBox(width: 6),
              Text(cooling == null ? '距離上次看盤' : '冷靜中', style: AppText.note),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/crypto-watch/stats'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('看盤統計 ›'),
              ),
            ],
          ),
          Center(
            child: Text(
              cooling != null
                  ? _clock(cooling).substring(2)
                  : since == null
                  ? '--:--:--'
                  : _clock(since),
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cooling != null
                    ? AppColors.accent
                    : since == null
                    ? AppColors.ink3
                    : AppColors.ok,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              cooling != null
                  ? '倒數完還想看再看，真的有好機會它還會在'
                  : since == null
                  ? '還沒有紀錄，看完價格按「看了」記一筆'
                  : '今天看了 $today 次'
                        '${longest == null ? '' : '・今天最長撐過 ${formatDuration(longest)}'}',
              style: AppText.note.copyWith(
                color: today > heavyWatchThreshold && cooling == null
                    ? AppColors.mid
                    : AppColors.ink2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _cooldownEnd = cooling == null
                        ? DateTime.now().add(_cooldownLength)
                        : null;
                  }),
                  icon: Icon(
                    cooling == null
                        ? Icons.hourglass_bottom_rounded
                        : Icons.close_rounded,
                    size: 18,
                  ),
                  label: Text(cooling == null ? '先冷靜 10 分' : '取消冷靜'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.glassEdge),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _looked,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('看了（重新計時）'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tradeDown,
                    backgroundColor: tradeDown.withValues(alpha: 0.08),
                    side: BorderSide(color: tradeDown.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
