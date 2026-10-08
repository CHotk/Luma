import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/crypto_watch_stats.dart';
import '../../domain/models/crypto_watch_entry.dart';
import '../../domain/models/trade_entry.dart';
import '../../domain/trade_stats.dart';
import '../../shared/widgets/app_notice.dart';
import 'trade_ui.dart';

/// 交易與自律各頁共用的一包資料：看盤紀錄＋每一單＋每月月初資金。
class TradeData {
  TradeData({
    required this.watches,
    required this.trades,
    required this.capitals,
  }) : watchCounts = countsByDay(watches);

  final List<CryptoWatchEntry> watches;

  /// 新開的在前面。
  final List<TradeEntry> trades;

  /// `yyyy-MM` → 月初資金。
  final Map<String, double> capitals;

  final Map<DateTime, int> watchCounts;

  double? capitalOf(DateTime month) => capitals[TradeMonthCapital.idOf(month)];

  MonthTradeSummary month(DateTime month) =>
      summarizeMonth(trades, month, capital: capitalOf(month));

  List<TradeEntry> get openTrades => trades.where((t) => t.isOpen).toList();
}

/// 看 [dataRevisionProvider]：任何一頁記一筆、平倉、刪除、看了、改月初
/// 資金後 bump 一下，主畫面、日誌、月報、某一天都會一起重算；雲端同步
/// 帶回資料時同步那邊也會 bump。
final tradeDataProvider = FutureProvider.autoDispose<TradeData>((ref) async {
  ref.watch(dataRevisionProvider);
  final watches = await ref.read(cryptoWatchRepositoryProvider).loadAll();
  final repo = ref.read(tradeRepositoryProvider);
  return TradeData(
    watches: watches,
    trades: await repo.loadAll(),
    capitals: await repo.loadCapitals(),
  );
});

void _bump(WidgetRef ref) => ref.read(dataRevisionProvider.notifier).state++;

/// 記一筆（右下角／主畫面按鈕，或月曆某一天「替這天補記」）。
Future<void> addTradeFlow(
  BuildContext context,
  WidgetRef ref, {
  DateTime? day,
}) async {
  final draft = await showNewTradeSheet(context, day: day);
  if (draft == null) return;
  await ref
      .read(tradeRepositoryProvider)
      .add(
        symbol: draft.symbol,
        isLong: draft.isLong,
        leverage: draft.leverage,
        margin: draft.margin,
        openedAt: draft.openedAt,
        closedAt: draft.closedAt,
        pnl: draft.pnl,
        note: draft.note,
      );
  _bump(ref);
  if (!context.mounted) return;
  if (draft.pnl == null) {
    showAppNotice(
      context,
      '已記錄開倉：${draft.symbol} ${draft.isLong ? '多' : '空'} ${fmtLev(draft.leverage)}',
      detail: '平倉時點「持倉中」那一單結算',
    );
  } else {
    showAppNotice(
      context,
      '已記錄：${draft.symbol} ${fmtPnl(draft.pnl!)} USDT',
      detail: '本金報酬率 ${fmtPct(draft.pnl! / draft.margin * 100)}',
      isError: draft.pnl! < 0,
    );
  }
}

/// 點一單：持倉中的去平倉，已平倉的看明細（可刪除）。
Future<void> openTradeFlow(
  BuildContext context,
  WidgetRef ref,
  TradeEntry trade,
  TradeData data,
) async {
  final repo = ref.read(tradeRepositoryProvider);
  if (trade.isOpen) {
    final now = DateTime.now();
    final pnl = await showCloseTradeSheet(
      context,
      trade: trade,
      monthTotal: data.month(now).total,
      capital: data.capitalOf(now),
    );
    if (pnl == null) return;
    await repo.close(trade.id, pnl: pnl);
    _bump(ref);
    if (!context.mounted) return;
    showAppNotice(
      context,
      '結算完成：${trade.symbol} ${fmtPnl(pnl)} USDT',
      detail: '本金報酬率 ${fmtPct(pnl / trade.margin * 100)}・記在今天',
      isError: pnl < 0,
    );
    return;
  }
  final deleted = await showTradeDetailSheet(
    context,
    trade: trade,
    watchCountThatDay: data.watchCounts[dayOf(trade.closedAt!)] ?? 0,
  );
  if (!deleted) return;
  await repo.delete(trade.id);
  _bump(ref);
  if (context.mounted) showAppNotice(context, '已刪除這一單');
}

/// 改某個月的月初資金。
Future<void> editCapitalFlow(
  BuildContext context,
  WidgetRef ref,
  DateTime month,
  double? current,
) async {
  // 輸入框的 controller 交給對話框自己的 State 管，對話框完全關閉
  // （收合動畫跑完）才釋放，不在這裡 pop 完馬上 dispose。
  final value = await showDialog<double>(
    context: context,
    builder: (_) => _CapitalDialog(month: month, current: current),
  );
  if (value == null) return;
  await ref.read(tradeRepositoryProvider).setCapital(month, value);
  _bump(ref);
}

class _CapitalDialog extends StatefulWidget {
  const _CapitalDialog({required this.month, this.current});

  final DateTime month;
  final double? current;

  @override
  State<_CapitalDialog> createState() => _CapitalDialogState();
}

class _CapitalDialogState extends State<_CapitalDialog> {
  late final _ctrl = TextEditingController(
    text: widget.current == null
        ? ''
        : fmtAmount(widget.current!).replaceAll(',', ''),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_ctrl.text.replaceAll(',', ''));
    if (v != null && v > 0) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.month.month} 月初的資金'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('月報酬 %＝本月損益 ÷ 這個數字', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'USDT'),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}
