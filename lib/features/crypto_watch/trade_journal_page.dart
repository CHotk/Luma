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
import '../../shared/widgets/inline_empty_card.dart';
import 'trade_data.dart';
import 'trade_ui.dart';

/// 交易日誌（設計稿版本 4 的卡片流，從主畫面右上角／下方「交易日誌」進來）：
/// 持倉中的放最上面，已平倉的依平倉日分組，每組標題寫當天損益，
/// 每張卡寫清楚槓桿、本金、倉位、損益、%。
class TradeJournalPage extends ConsumerWidget {
  const TradeJournalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(tradeDataProvider).valueOrNull;
    return Scaffold(
      drawer: const AppSideDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => addTradeFlow(context, ref),
        tooltip: '記一筆交易',
        child: const Icon(Icons.add_rounded),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                const AppTopBar(title: '交易日誌'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : _list(context, ref, data),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, TradeData data) {
    if (data.trades.isEmpty) {
      return const Align(
        alignment: Alignment.topCenter,
        child: InlineEmptyCard(title: '還沒有交易紀錄', message: '按右下角 ＋ 記第一筆'),
      );
    }
    final open = data.openTrades;
    final closed = data.trades.where((t) => !t.isOpen).toList()
      ..sort((a, b) => b.closedAt!.compareTo(a.closedAt!));
    final byDay = <DateTime, List<TradeEntry>>{};
    for (final t in closed) {
      byDay.putIfAbsent(dayOf(t.closedAt!), () => []).add(t);
    }
    final now = DateTime.now();
    final children = <Widget>[];
    if (open.isNotEmpty) {
      children
        ..add(_header('持倉中', '${open.length} 單'))
        ..addAll([
          for (final t in open)
            TradeCard(
              trade: t,
              onTap: () => openTradeFlow(context, ref, t, data),
            ),
        ]);
    }
    int? lastMonth;
    for (final entry in byDay.entries) {
      final d = entry.key;
      final monthKey = d.year * 12 + d.month;
      if (monthKey != lastMonth) {
        lastMonth = monthKey;
        final m = data.month(d);
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 2),
            child: Row(
              children: [
                Text(
                  d.year == now.year
                      ? '${d.month} 月'
                      : '${d.year} 年 ${d.month} 月',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${fmtPnl(m.total)} USDT'
                        '${m.returnPercent == null ? '' : '・${fmtPct(m.returnPercent!)}'}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: pnlColor(m.total),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final sum = entry.value.fold(0.0, (s, t) => s + t.pnl!);
      children
        ..add(_header(fmtDay(d), fmtPnl(sum), color: pnlColor(sum)))
        ..addAll([
          for (final t in entry.value)
            TradeCard(
              trade: t,
              onTap: () => openTradeFlow(context, ref, t, data),
            ),
        ]);
    }
    children.add(const SizedBox(height: 90));
    return ListView(children: children);
  }

  Widget _header(String left, String right, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Row(
      children: [
        Text(left, style: AppText.note),
        const Spacer(),
        Text(
          right,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink2,
          ),
        ),
      ],
    ),
  );
}
