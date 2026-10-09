import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/trade_stats.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'trade_data.dart';
import 'trade_ui.dart';

/// 月報（使用者要求：每個月、包括當月都要能看）。上方 ‹ › 換月份，只停在
/// 有紀錄的月份＋當月（2026-10-10），兩個分頁：
/// - 自律成績單（設計稿版本 3）：本月損益與報酬、低槓桿 vs 高槓桿、本月
///   自律數字（看盤相關的比較 2026-10-10 隨看盤功能一起移除）；
/// - 什麼樣的單在賺（設計稿版本 4）：勝率、盈虧比、最大單日賺賠，
///   依槓桿／方向／幣種分組。
class TradeReportPage extends ConsumerStatefulWidget {
  const TradeReportPage({super.key, this.initialMonth});

  final DateTime? initialMonth;

  @override
  ConsumerState<TradeReportPage> createState() => _TradeReportPageState();
}

class _TradeReportPageState extends ConsumerState<TradeReportPage> {
  late DateTime _month =
      widget.initialMonth ??
      DateTime(DateTime.now().year, DateTime.now().month);
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(tradeDataProvider).valueOrNull;
    final now = DateTime.now();
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    final months = data?.navMonths ?? const <DateTime>[];
    final prev = prevRecordMonth(months, _month);
    final next = nextRecordMonth(months, _month);
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
                const AppTopBar(title: '月報'),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: prev == null
                          ? null
                          : () => setState(() => _month = prev),
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: AppColors.ink2,
                      disabledColor: AppColors.ink3.withValues(alpha: 0.4),
                    ),
                    Expanded(
                      child: Text(
                        '${_month.year} 年 ${_month.month} 月'
                        '${isThisMonth ? '（本月，還在進行）' : ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: next == null
                          ? null
                          : () => setState(() => _month = next),
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: AppColors.ink2,
                      disabledColor: AppColors.ink3.withValues(alpha: 0.4),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('自律成績單')),
                    ButtonSegment(value: 1, label: Text('什麼樣的單在賺')),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          children: [
                            _heroCard(data),
                            const SizedBox(height: Gap.md),
                            ...(_tab == 0
                                ? _disciplineTab(data)
                                : _profitTab(data)),
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

  Widget _heroCard(TradeData data) {
    final sum = data.month(_month);
    final ret = sum.returnPercent;
    final cap = data.capitalOf(_month);
    final rate = ref.watch(usdtTwdRateProvider);
    return GlassCard(
      child: Column(
        children: [
          Text('本月已實現損益', style: AppText.note),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: fmtPnl(sum.total),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
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
          Text(
            fmtTwd(sum.total, rate, signed: true),
            style: AppText.note.copyWith(color: AppColors.ink2),
          ),
          if (ret != null)
            Text(
              fmtPct(ret),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: pnlColor(ret),
              ),
            ),
          TextButton(
            onPressed: () => editCapitalFlow(context, ref, _month, cap),
            child: Text(
              cap == null
                  ? '設定月初資金，算月報酬 % ✎'
                  : '月初資金 ${fmtAmount(cap)} USDT（${fmtTwd(cap, rate)}）✎',
            ),
          ),
        ],
      ),
    );
  }

  // ── 自律成績單（版本 3）──────────────────────────────────

  List<Widget> _disciplineTab(TradeData data) {
    final sum = data.month(_month);
    final lev = lowVsHighLeverage(sum.closed);
    final streak = longestLosingStreak(sum.closed);

    return [
      _card(
        '槓桿 ≤ 10x vs > 10x',
        child: Row(
          children: [
            _cmp(
              '${lev.low.count} 單・勝 ${lev.low.wins}',
              lev.low.count == 0 ? null : lev.low.total,
            ),
            const SizedBox(width: 6),
            _cmp(
              '${lev.high.count} 單・勝 ${lev.high.wins}',
              lev.high.count == 0 ? null : lev.high.total,
            ),
          ],
        ),
      ),
      _card(
        '本月自律',
        child: Column(
          children: [
            _row('開倉次數', '${openedInMonth(data.trades, _month)} 單'),
            _row(
              '平均槓桿',
              sum.avgLeverage == null ? '—' : fmtLev(sum.avgLeverage!),
              color: (sum.avgLeverage ?? 0) > 10 ? tradeDown : null,
            ),
            _row(
              '最長連續虧損',
              streak == null
                  ? '沒有'
                  : '連 ${streak.count} 單・${fmtPnl(streak.total)}',
              color: streak == null ? null : tradeDown,
            ),
          ],
        ),
      ),
    ];
  }

  // ── 什麼樣的單在賺（版本 4）──────────────────────────────

  List<Widget> _profitTab(TradeData data) {
    final sum = data.month(_month);
    if (sum.closed.isEmpty) {
      return [
        _card(
          '這個月還沒有平倉的單',
          child: Text('平倉之後這裡會依槓桿、方向、幣種分析', style: AppText.bodyDim),
        ),
      ];
    }
    final best = sum.bestDay, worst = sum.worstDay;
    return [
      Row(
        children: [
          _box('已平倉', '${sum.closed.length} 單'),
          const SizedBox(width: 6),
          _box('勝率', '${sum.winRate!.round()}%', sub: '${sum.wins} 勝'),
          const SizedBox(width: 6),
          _box(
            '盈虧比',
            sum.profitRatio == null ? '—' : sum.profitRatio!.toStringAsFixed(1),
            sub:
                '賺 ${sum.avgWin == null ? '—' : fmtAmount(sum.avgWin!.roundToDouble())}'
                ' ÷ 賠 ${sum.avgLoss == null ? '—' : fmtAmount(sum.avgLoss!.roundToDouble())}',
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          _box('賺 / 賠天數', '${sum.winDays} / ${sum.lossDays}'),
          const SizedBox(width: 6),
          _box(
            '最大單日賺',
            best == null ? '—' : fmtPnl(best.value),
            sub: best == null ? null : fmtDay(best.key),
            color: best == null ? null : tradeUp,
          ),
          const SizedBox(width: 6),
          _box(
            '最大單日賠',
            worst == null ? '—' : fmtPnl(worst.value),
            sub: worst == null ? null : fmtDay(worst.key),
            color: worst == null ? null : tradeDown,
          ),
        ],
      ),
      const SizedBox(height: Gap.md),
      _groupCard('依槓桿', byLeverage(sum.closed), badge: true),
      _groupCard('依方向', byDirection(sum.closed)),
      _groupCard('依幣種', bySymbol(sum.closed)),
    ];
  }

  // ── 小元件 ───────────────────────────────────────────────

  Widget _card(String title, {String? hint, required Widget child}) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.note)),
              if (hint != null)
                Text(hint, style: AppText.note.copyWith(color: AppColors.ink3)),
            ],
          ),
          const SizedBox(height: Gap.sm),
          child,
        ],
      ),
    ),
  );

  Widget _cmp(String label, double? avg) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppText.note.copyWith(fontSize: 10.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            avg == null ? '—' : fmtPnl(avg),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: pnlColor(avg),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(String k, String v, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
    ),
    child: Row(
      children: [
        Text(k, style: AppText.bodyDim),
        const Spacer(),
        Text(
          v,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink,
          ),
        ),
      ],
    ),
  );

  Widget _box(String label, String value, {String? sub, Color? color}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.note.copyWith(fontSize: 10.5)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color ?? AppColors.ink,
                  ),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.note.copyWith(
                    fontSize: 10,
                    color: AppColors.ink3,
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _groupCard(
    String title,
    List<TradeGroup> groups, {
    bool badge = false,
  }) {
    final maxAbs = groups.fold<double>(
      1,
      (m, g) => g.total.abs() > m ? g.total.abs() : m,
    );
    return _card(
      title,
      child: Column(
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      g.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: badge && g.label == '> 10x'
                            ? tradeDown
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${g.count} 單・勝 ${g.wins}',
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LinearProgressIndicator(
                        value: g.count == 0 ? 0 : g.total.abs() / maxAbs,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF1E1E2E),
                        color: g.total >= 0 ? tradeUp : tradeDown,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      g.count == 0 ? '—' : fmtPnl(g.total),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: g.count == 0
                            ? AppColors.ink3
                            : pnlColor(g.total),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
