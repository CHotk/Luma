import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/trade_entry.dart';
import '../../domain/trade_stats.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'trade_data.dart';
import 'trade_ticket_widgets.dart';
import 'trade_ui.dart';

/// 交易&自律（2026-10-08 使用者要求把「看盤記錄」改成這個名字，整合看盤
/// 次數跟每一單的損益）。版面照 `design-history/已選擇完成/2026-10-08_投資與自律五種設計.html`
/// 使用者挑的組合：
/// - 最上面是**當月損益**卡片。原本是版本 3 的看盤卡片（距離上次看盤、
///   冷靜 10 分鐘、看了），2026-10-10 使用者要求整個移除看盤次數功能，
///   改成當月損益；
/// - 版本 2 的月曆：每格寫當天損益（綠賺紅賠）、開倉日／平倉日的「開」
///   「平」小標籤，點一天進「那天發生什麼」。‹ › 只停在有紀錄的月份＋當月（2026-10-10 使用者要求：6、9、
///   10 月有紀錄，往前看就是 10 → 9 → 6）；
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
                            _MonthPnlCard(data: data, month: _month),
                            const SizedBox(height: Gap.md),
                            _buildMonthCard(data),
                            if (_monthTrades(data).isNotEmpty) ...[
                              const SizedBox(height: Gap.md),
                              _buildGantt(data),
                            ],
                            if (data.openTrades.isNotEmpty) ...[
                              const SizedBox(height: Gap.lg),
                              _sectionTitle('持倉中', '點一下去平倉', live: true),
                              for (final t in data.openTrades)
                                OpenTradeCard(
                                  trade: t,
                                  highlighted: t.id == _ganttSel,
                                  onTap: () =>
                                      openTradeFlow(context, ref, t, data),
                                ),
                            ],
                            const SizedBox(height: Gap.md),
                            _AddTradeButton(
                              onPressed: () => addTradeFlow(context, ref),
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

  Widget _sectionTitle(String title, String hint, {bool live = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          children: [
            if (live) ...[const BreathingDot(), const SizedBox(width: 8)],
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: live ? AppColors.mid : AppColors.ink2,
              ),
            ),
            const Spacer(),
            Text(hint, style: AppText.note.copyWith(color: AppColors.ink3)),
          ],
        ),
      );

  // ── 月曆：每天損益（設計稿版本 2）──────────────────────────

  Widget _buildMonthCard(TradeData data) {
    final now = DateTime.now();
    final sum = data.month(_month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month).weekday % 7;
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    final months = data.navMonths;
    final prev = prevRecordMonth(months, _month);
    final next = nextRecordMonth(months, _month);
    final litDays = <DateTime>{};
    // 重疊的單用顏色分（2026-10-14 使用者選：1 單一條黃線、2～3 單每單一條
    // 細色條、4 單以上分段色塊＋×N）。顏色照這個月開倉先後輪流給。
    final monthTrades = _monthTrades(data);
    final heldOn = <DateTime, List<TradeEntry>>{};
    for (final t in monthTrades) {
      final days = _daysOf(t);
      for (final d in days) {
        (heldOn[d] ??= []).add(t);
      }
      if (t.id == _ganttSel) litDays.addAll(days);
    }
    final overlapped = [
      for (final t in monthTrades)
        if (_daysOf(t).any((d) => (heldOn[d]?.length ?? 0) > 1)) t,
    ];
    // 有跟別單重疊過的單才給顏色，而且從開到平每一天都用同一個顏色
    // （2026-10-14 使用者回報：5 號開 6 號平、6 號又開一單，5 號是黃線、6 號
    // 變藍，接不起來）。從沒重疊過的單照舊一條黃線。
    final colorOf = <String, Color>{
      for (var i = 0; i < overlapped.length; i++)
        overlapped[i].id: tradeOverlapColors[i % tradeOverlapColors.length],
    };
    // 每天的開／平事件（照真的時間排），重疊那天標籤換成那單的顏色。
    final events = <DateTime, List<(bool open, String id, DateTime at)>>{};
    for (final t in data.trades) {
      (events[dayOf(t.openedAt)] ??= []).add((true, t.id, t.openedAt));
      final c = t.closedAt;
      if (c != null) (events[dayOf(c)] ??= []).add((false, t.id, c));
    }
    for (final l in events.values) {
      l.sort((a, b) => a.$3.compareTo(b.$3));
    }
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: prev == null
                    ? null
                    : () => setState(() {
                        _month = prev;
                        _ganttSel = null;
                      }),
                icon: const Icon(Icons.chevron_left_rounded),
                color: AppColors.ink2,
                disabledColor: AppColors.ink3.withValues(alpha: 0.4),
                tooltip: '上一個有紀錄的月份',
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
                onPressed: next == null
                    ? null
                    : () => setState(() {
                        _month = next;
                        _ganttSel = null;
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
                color: AppColors.ink2,
                disabledColor: AppColors.ink3.withValues(alpha: 0.4),
                tooltip: '下一個有紀錄的月份',
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              if (!isThisMonth)
                TextButton(
                  onPressed: () => setState(() {
                    _month = DateTime(now.year, now.month);
                    _ganttSel = null;
                  }),
                  child: const Text('回本月'),
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
                  held:
                      heldOn[DateTime(_month.year, _month.month, d)] ??
                      const [],
                  colorOf: colorOf,
                  lit: litDays.contains(DateTime(_month.year, _month.month, d)),
                  events:
                      events[DateTime(_month.year, _month.month, d)] ??
                      const [],
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tag('開', open: true),
                  const SizedBox(width: 4),
                  Text('開倉日', style: AppText.note),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tag('平', open: false),
                  const SizedBox(width: 4),
                  Text('平倉日', style: AppText.note),
                ],
              ),
            ],
          ),
          if (overlapped.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in overlapped)
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0xFF2A2A3D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorOf[t.id],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${t.symbol}${t.isLong ? '多' : '空'} ${fmtLev(t.leverage)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          t.isOpen ? '抱著' : fmtPnl(t.pnl!),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.isOpen ? AppColors.mid : pnlColor(t.pnl),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '點某一天看那天發生什麼・損益記在平倉那天',
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(
    DateTime day, {
    required double? pnl,
    required List<TradeEntry> held,
    required Map<String, Color> colorOf,
    required bool lit,
    required List<(bool open, String id, DateTime at)> events,
  }) {
    final n = held.length;
    // 兩單以上重疊時，開／平標籤用那單的顏色。
    Widget eventTag((bool, String, DateTime) e) {
      final c = colorOf[e.$2];
      if (c == null) return _tag(e.$1 ? '開' : '平', open: e.$1);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        decoration: BoxDecoration(
          color: e.$1 ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: c, width: 1.1),
        ),
        child: Text(
          e.$1 ? '開' : '平',
          style: TextStyle(
            fontSize: 8.5,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: e.$1 ? const Color(0xFF111111) : c,
          ),
        ),
      );
    }

    final now = DateTime.now();
    final isToday = day == dayOf(now);
    final future = day.isAfter(dayOf(now));
    final strength = pnl == null ? 0.0 : (pnl.abs() / 250).clamp(0.0, 1.0);
    final bg = pnl == null || pnl == 0
        ? Colors.white.withValues(alpha: 0.035)
        : (pnl > 0 ? tradeUp : tradeDown).withValues(
            alpha: 0.12 + strength * 0.3,
          );
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
                      // 開倉日／平倉日的小標籤，放在損益上面（2026-10-10
                      // 使用者要求月曆上看得到哪天開、哪天平，照持倉期間
                      // 設計稿版本 2 的「開」黃底、「平」深底）。
                      if (events.isNotEmpty)
                        Align(
                          alignment: const Alignment(-1, 0.05),
                          // 一行排完，放不下就整排縮小（不換行）。
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 照那天真的先後排（先平再開就是平在左邊）。
                                for (final (i, e)
                                    in events.take(4).indexed) ...[
                                  if (i > 0) const SizedBox(width: 2),
                                  eventTag(e),
                                ],
                              ],
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
                // 只抱 1 單：跟原本一樣一條黃線。
                if (n == 1 && !colorOf.containsKey(held.single.id))
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
                // 2～3 單：每單一條細色條，由下往上疊（開倉、平倉那天兩端
                // 內縮一點，連續幾天看得出是同一條）。
                // 只抱 1 單但那單別天有跟人重疊：照樣畫它的顏色，接得起來。
                if ((n >= 2 && n <= 3) ||
                    (n == 1 && colorOf.containsKey(held.single.id)))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      verticalDirection: VerticalDirection.up,
                      children: [
                        for (final t in held)
                          Padding(
                            padding: EdgeInsets.only(
                              top: 1.5,
                              left: dayOf(t.openedAt) == day ? 4 : 0,
                              right:
                                  t.closedAt != null &&
                                      dayOf(t.closedAt!) == day
                                  ? 4
                                  : 0,
                            ),
                            child: Container(
                              height: 2.5,
                              decoration: BoxDecoration(
                                color: colorOf[t.id],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // 4 單以上：一條分段色塊＋右上角 ×N。
                if (n >= 4) ...[
                  Positioned(
                    left: 3,
                    right: 3,
                    bottom: 2,
                    height: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          for (var i = 0; i < n; i++) ...[
                            if (i > 0) const SizedBox(width: 1),
                            Expanded(
                              child: ColoredBox(color: colorOf[held[i].id]!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 3,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '×$n',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
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
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (t.isOpen)
                              const TextSpan(
                                text: '● ',
                                style: TextStyle(color: AppColors.mid),
                              ),
                            TextSpan(
                              text:
                                  '${t.symbol}${t.isLong ? '多' : '空'} ${fmtLev(t.leverage)}',
                            ),
                          ],
                        ),
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
                                // 持倉中：一直往右流的黃色斜紋（2026-10-14
                                // 使用者要第 4 版那個流動效果）。
                                child: t.isOpen
                                    ? const FlowingStripes()
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.mid.withValues(
                                            alpha: t.isOpen ? 0.3 : 0.45,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: t.isOpen
                                              ? Border.all(
                                                  color: AppColors.mid
                                                      .withValues(alpha: 0.6),
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
                                                        right: Radius.circular(
                                                          6,
                                                        ),
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
          // 點到的那一單：已平倉的是長在這裡面的票根；持倉中的指去下面
          // 「持倉中」那張亮卡（2026-10-14 設計稿第 3 版）。
          if (sel != null && !sel.isOpen) ...[
            const SizedBox(height: Gap.sm),
            TradeReceipt(
              trade: sel,
              onClose: () => setState(() => _ganttSel = null),
              onEdit: () => editTradeFlow(context, ref, sel),
              onDelete: () async {
                await deleteTradeFlow(context, ref, sel);
                if (mounted) setState(() => _ganttSel = null);
              },
            ),
          ],
          if (sel != null && sel.isOpen) ...[
            const SizedBox(height: Gap.sm),
            Center(
              child: Text(
                '這單還抱著 ↓ 在下面「持倉中」',
                style: AppText.note.copyWith(color: AppColors.mid),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, {required bool open}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 2.5),
    decoration: BoxDecoration(
      color: open ? AppColors.mid : const Color(0xFF2A2A3D),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 8.5,
        height: 1.3,
        fontWeight: FontWeight.w800,
        color: open ? const Color(0xFF1A1405) : AppColors.ink,
      ),
    ),
  );

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

/// 最上面的月損益卡（2026-10-10 取代原本的看盤卡片）：跟著下面月曆選的
/// 月份變（使用者回報：原本固定當月，切月曆它不會跟著變）。大字那個月的
/// 已實現損益，下面月報酬 %、月初資金（點了改），再一行已平倉幾單、勝率；
/// 看的是當月才多寫持倉中幾單。
class _MonthPnlCard extends ConsumerWidget {
  const _MonthPnlCard({required this.data, required this.month});

  final TradeData data;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final isThisMonth = month.year == now.year && month.month == now.month;
    final sum = data.month(month);
    final ret = sum.returnPercent;
    final cap = data.capitalOf(month);
    final open = isThisMonth ? data.openTrades.length : 0;
    final rate = ref.watch(usdtTwdRateProvider);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: AppColors.ink2,
              ),
              const SizedBox(width: 6),
              Text(
                '${month.year == now.year ? '' : '${month.year} 年 '}'
                '${month.month} 月已實現損益',
                style: AppText.note,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(
                  '/crypto-watch/report?m=${month.year}-${month.month}',
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('月報 ›'),
              ),
            ],
          ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: fmtPnl(sum.total),
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: pnlColor(sum.total),
                      ),
                    ),
                    const TextSpan(
                      text: ' USDT',
                      style: TextStyle(fontSize: 13, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            fmtTwd(sum.total, rate, signed: true),
            textAlign: TextAlign.center,
            style: AppText.note.copyWith(color: AppColors.ink2),
          ),
          // 起始資金自動算（這個月的單平均本金），不能點、不用填（2026-10-14）。
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (ret != null)
                      TextSpan(
                        text: '${fmtPct(ret)}・',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pnlColor(ret),
                        ),
                      ),
                    TextSpan(
                      text: cap == null
                          ? '這個月還沒有單'
                          : '起始資金 ${fmtAmount(cap)} USDT'
                                '（${fmtTwd(cap, rate)}・這個月的單平均本金）',
                      style: AppText.note.copyWith(color: AppColors.ink2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Text(
            '已平倉 ${sum.closed.length} 單'
            '${sum.winRate == null ? '' : '・勝率 ${sum.winRate!.round()}%'}'
            '${open == 0 ? '' : '・持倉中 $open 單'}',
            textAlign: TextAlign.center,
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }
}

/// 「記一筆交易」：形狀不變（膠囊），換成藍到紫的漸層、柔和光暈、上緣一條
/// 細反光（2026-10-14 使用者要求：好看一點，保持原本形狀）。
class _AddTradeButton extends StatelessWidget {
  const _AddTradeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(99));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B7BFF), Color(0xFF7C5CFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F6BFF).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add_rounded, size: 21),
          label: const Text(
            '記一筆交易',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            overlayColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }
}
