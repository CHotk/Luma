import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 月曆點某一天 →「那天發生什麼」（設計稿版本 2 第二支手機）：當天損益、
/// 看盤次數、把看盤跟開倉／平倉排在同一條時間軸上，看得出「開倉之後一直
/// 盯盤」的過程；看太多又賠錢時多一句提醒。
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

/// 時間軸上的一列：一段連續的看盤、或一次開倉／平倉。
class _Event {
  _Event.watch(this.at, this.until, this.count) : trade = null, closing = false;
  _Event.trade(this.at, this.trade, {required this.closing})
    : until = null,
      count = 0;

  final DateTime at;
  final DateTime? until;
  final int count;
  final TradeEntry? trade;
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
    final watches =
        data.watches.where((w) => dayOf(w.at) == d).map((w) => w.at).toList()
          ..sort();

    // 交易事件
    final events = <_Event>[
      for (final t in opened) _Event.trade(t.openedAt, t, closing: false),
      for (final t in closed) _Event.trade(t.closedAt!, t, closing: true),
    ];
    // 兩次交易事件之間連續的看盤合成一列（「12:05–17:40 看盤 ×9」）。
    final tradeTimes = events.map((e) => e.at).toList()..sort();
    var run = <DateTime>[];
    void flush() {
      if (run.isEmpty) return;
      events.add(_Event.watch(run.first, run.last, run.length));
      run = [];
    }

    for (final w in watches) {
      if (run.isNotEmpty &&
          tradeTimes.any((t) => t.isAfter(run.last) && !t.isAfter(w))) {
        flush();
      }
      run.add(w);
    }
    flush();
    events.sort((a, b) => a.at.compareTo(b.at));

    // 開倉之後到平倉之前看了幾次（只看當天開、當天平的單）。
    int? watchedWhileHolding;
    final sameDay = closed.where((t) => dayOf(t.openedAt) == d).toList();
    if (sameDay.isNotEmpty) {
      watchedWhileHolding = watches
          .where(
            (w) => sameDay.any(
              (t) => !w.isBefore(t.openedAt) && !w.isAfter(t.closedAt!),
            ),
          )
          .length;
    }

    // 這個月看太多的日子成績，給提醒那句用。
    final month = data.month(day);
    final heavyDays = month.dayPnl.entries
        .where((e) => (data.watchCounts[e.key] ?? 0) > heavyWatchThreshold)
        .toList();
    final heavyLoss = heavyDays.where((e) => e.value < 0).length;

    final watchCount = watches.length;
    final heavy = watchCount > heavyWatchThreshold;

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('看盤', style: AppText.note),
                  const SizedBox(height: 4),
                  Text(
                    '$watchCount 次',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: heavy ? AppColors.mid : AppColors.ink,
                    ),
                  ),
                  Text(
                    heavy
                        ? '超過 $heavyWatchThreshold 次'
                        : '在 $heavyWatchThreshold 次以內',
                    style: AppText.note.copyWith(color: AppColors.ink3),
                  ),
                ],
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
                  child: Text('這天沒有看盤也沒有交易', style: AppText.bodyDim),
                )
              else
                for (final e in events) _eventRow(context, ref, e),
            ],
          ),
        ),
        if (heavy && closed.isNotEmpty && pnl < 0) ...[
          const SizedBox(height: Gap.md),
          GlassCard(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.ink2,
                  height: 1.6,
                ),
                children: [
                  if (watchedWhileHolding != null) ...[
                    const TextSpan(text: '持倉期間看了 '),
                    TextSpan(
                      text: '$watchedWhileHolding 次',
                      style: const TextStyle(
                        color: AppColors.mid,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '。'),
                  ],
                  TextSpan(
                    text:
                        '${day.month} 月看盤超過 $heavyWatchThreshold 次、'
                        '又有平倉的 ${heavyDays.length} 天裡，',
                  ),
                  TextSpan(
                    text: '$heavyLoss 天是賠的',
                    style: const TextStyle(
                      color: tradeDown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: '。'),
                ],
              ),
            ),
          ),
        ],
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
    final time = e.until != null && e.until != e.at
        ? '${fmtHm(e.at)}–${fmtHm(e.until!)}'
        : fmtHm(e.at);
    Widget content;
    if (e.trade == null) {
      final many = e.count > 3;
      content = Text(
        '👁 看盤 ×${e.count}',
        style: TextStyle(
          fontSize: 13,
          color: many ? AppColors.mid : AppColors.ink2,
          fontWeight: many ? FontWeight.w700 : FontWeight.w400,
        ),
      );
    } else {
      final t = e.trade!;
      // 兩行：上面幣種方向槓桿，下面開倉／平倉說明；平倉的損益靠右，
      // 金額很大時縮小，不擠爆。
      content = Row(
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
    }
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
