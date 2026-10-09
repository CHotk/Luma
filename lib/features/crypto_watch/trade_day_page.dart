import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'trade_ui.dart';

/// 月曆點某一天 →「那天發生什麼」（設計稿版本 2 第二支手機）：當天損益、
/// 開倉／平倉排成一條時間軸。原本還有看盤次數跟「看太多又賠錢」的提醒，
/// 2026-10-10 使用者要求移除看盤功能後一起拿掉。
class TradeDayPage extends ConsumerWidget {
  const TradeDayPage({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                AppTopBar(title: '${fmtDay(day)} 當天回顧'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : _Body(day: day, data: data),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 時間軸上的一列：一次開倉或平倉。
class _Event {
  _Event(this.at, this.trade, {required this.closing});

  final DateTime at;
  final TradeEntry trade;
  final bool closing;
}

class _Body extends ConsumerWidget {
  const _Body({required this.day, required this.data});

  final DateTime day;
  final TradeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dayOf(day);
    final closed = data.trades
        .where((t) => t.closedAt != null && dayOf(t.closedAt!) == d)
        .toList();
    final opened = data.trades.where((t) => dayOf(t.openedAt) == d).toList();
    final dayTrades = {...closed, ...opened}.toList()
      ..sort(
        (a, b) =>
            (a.closedAt ?? a.openedAt).compareTo(b.closedAt ?? b.openedAt),
      );
    final pnl = closed.fold(0.0, (s, t) => s + t.pnl!);
    final events = <_Event>[
      for (final t in opened) _Event(t.openedAt, t, closing: false),
      for (final t in closed) _Event(t.closedAt!, t, closing: true),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return ListView(
      children: [
        GlassCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('當天已實現損益', style: AppText.note),
                    const SizedBox(height: 4),
                    Text(
                      closed.isEmpty ? '—' : fmtPnl(pnl),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: pnlColor(closed.isEmpty ? null : pnl),
                      ),
                    ),
                    Text(
                      '平倉 ${closed.length} 單・開倉 ${opened.length} 單',
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('時間軸', style: AppText.note),
              const SizedBox(height: 4),
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('這天沒有交易', style: AppText.bodyDim),
                )
              else
                for (final e in events) _eventRow(context, ref, e),
            ],
          ),
        ),
        if (dayTrades.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              '這天的單',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
          ),
          for (final t in dayTrades)
            TradeCard(
              trade: t,
              onTap: () => openTradeFlow(context, ref, t, data),
            ),
        ],
        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          onPressed: () => addTradeFlow(context, ref, day: day),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('替這天補記一單'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.glassEdge),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }

  Widget _eventRow(BuildContext context, WidgetRef ref, _Event e) {
    final time = fmtHm(e.at);
    final t = e.trade;
    // 兩行：上面幣種方向槓桿，下面開倉／平倉說明；平倉的損益靠右，
    // 金額很大時縮小，不擠爆。
    final content = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      t.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  directionLabel(t.isLong),
                  const SizedBox(width: 5),
                  LeverageBadge(t.leverage),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                e.closing
                    ? (dayOf(t.openedAt) == dayOf(t.closedAt!)
                          ? '平倉'
                          : '平倉（${t.openedAt.month}/${t.openedAt.day} 開的）')
                    : '開倉・本金 ${fmtAmount(t.margin)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.note,
              ),
            ],
          ),
        ),
        if (e.closing)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtPnl(t.pnl!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: pnlColor(t.pnl),
                    ),
                  ),
                  Text(
                    fmtPct(t.pnlPercent!),
                    style: TextStyle(fontSize: 11, color: pnlColor(t.pnl)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              time,
              style: AppText.note.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}
