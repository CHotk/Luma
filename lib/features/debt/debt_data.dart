import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/debt_schedule.dart';
import '../../domain/models/debt.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import 'debt_sheets.dart';
import 'debt_ui.dart';

/// 負債各頁共用的一包資料。
class DebtData {
  DebtData({
    required List<Debt> debts,
    required this.payments,
    required this.income,
  }) {
    final byDebt = <String, List<DebtPayment>>{};
    for (final p in payments) {
      byDebt.putIfAbsent(p.debtId, () => []).add(p);
    }
    stats = [for (final d in debts) DebtStats.of(d, byDebt[d.id] ?? const [])];
    totals = DebtTotals(stats, income: income);
  }

  final List<DebtPayment> payments;
  final double? income;
  late final List<DebtStats> stats;
  late final DebtTotals totals;

  DebtStats? statsOf(String id) =>
      stats.where((s) => s.debt.id == id).firstOrNull;
}

/// 看 [dataRevisionProvider]：任何一頁新增、繳款、取消、刪除後 bump，
/// 總覽、本月、債務、試算、月曆都會一起重算；雲端同步帶回資料也會 bump。
final debtDataProvider = FutureProvider.autoDispose<DebtData>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.read(debtRepositoryProvider);
  return DebtData(
    debts: await repo.loadDebts(),
    payments: await repo.loadPayments(),
    income: await repo.loadIncome(),
  );
});

void _bump(WidgetRef ref) => ref.read(dataRevisionProvider.notifier).state++;

Future<DebtData> _fresh(WidgetRef ref) async {
  final repo = ref.read(debtRepositoryProvider);
  return DebtData(
    debts: await repo.loadDebts(),
    payments: await repo.loadPayments(),
    income: await repo.loadIncome(),
  );
}

/// 新增或編輯債務。
Future<void> debtFormFlow(
  BuildContext context,
  WidgetRef ref,
  DebtData data, {
  Debt? edit,
}) async {
  final draft = await showDebtFormSheet(
    context,
    edit: edit,
    currentMonthly: data.totals.monthly,
    income: data.income,
  );
  if (draft == null) return;
  final repo = ref.read(debtRepositoryProvider);
  if (edit == null) {
    await repo.addDebt(draft);
  } else {
    await repo.updateDebt(draft);
  }
  _bump(ref);
  if (context.mounted) {
    showAppNotice(
      context,
      edit == null ? '已新增債務：${draft.name}' : '已儲存：${draft.name}',
      detail: '每月 ${money(monthlyPayment(draft))}',
    );
  }
}

/// 點圓圈：沒繳就去標記已繳（可以改金額、日期），已繳就問要不要取消。
Future<void> toggleDueFlow(
  BuildContext context,
  WidgetRef ref,
  DueItem item,
) async {
  if (item.isPaid) {
    await cancelLatestFlow(context, ref, item.stats, period: item.row.k);
  } else {
    await payFlow(context, ref, item.stats);
  }
}

/// 標記下一期已繳。
Future<void> payFlow(BuildContext context, WidgetRef ref, DebtStats s) async {
  final next = s.next;
  if (next == null) return;
  final result = await showPaySheet(context, stats: s);
  if (result == null) return;
  await ref
      .read(debtRepositoryProvider)
      .addPayment(
        debtId: s.debt.id,
        date: result.date,
        amount: result.amount,
        period: s.debt.flexible ? null : next.k,
      );
  _bump(ref);
  final after = (await _fresh(ref)).statsOf(s.debt.id);
  if (!context.mounted) return;
  if (after != null && after.closed) {
    await showPaidOffDialog(context, after);
  } else {
    showAppNotice(
      context,
      '${s.debt.name} 已繳 ${money(result.amount)}',
      detail:
          '${s.debt.flexible ? '' : '第 ${next.k} 期・'}剩 ${money(after?.remaining ?? 0)}',
    );
  }
}

/// 取消最新的那一筆已繳（按錯時用）；提前清償過的是取消清償。只能取消
/// 最新那一期，不然後面的期數會對不上。
Future<void> cancelLatestFlow(
  BuildContext context,
  WidgetRef ref,
  DebtStats s, {
  int? period,
}) async {
  final repo = ref.read(debtRepositoryProvider);
  final d = s.debt;
  if (d.payoffAt != null) {
    final ok = await showAppConfirmDialog(
      context,
      title: '取消提前清償？',
      message: '${d.name} 會回到還款中。',
      confirmLabel: '取消清償',
    );
    if (!ok) return;
    await repo.updateDebt(
      d.copyWith(payoffAt: () => null, payoffAmount: () => null),
    );
    _bump(ref);
    return;
  }
  if (s.paid.isEmpty) return;
  final last = s.paid.last;
  if (!d.flexible && period != null && period != last.k) {
    if (context.mounted) {
      showAppNotice(
        context,
        '只能取消最新的那一期',
        detail: '${d.name} 最新是第 ${last.k} 期',
        isError: true,
      );
    }
    return;
  }
  if (!context.mounted) return;
  final ok = await showAppConfirmDialog(
    context,
    title: '取消這筆已繳？',
    message:
        '${d.name} ${md(last.payment!.date)} ${money(last.payment!.amount)}，會變回未繳。',
    confirmLabel: '取消已繳',
  );
  if (!ok) return;
  await repo.cancelPayment(last.payment!.id);
  _bump(ref);
  if (context.mounted) showAppNotice(context, '已取消，變回未繳');
}

/// 一次還清剩下的。
Future<void> payoffFlow(
  BuildContext context,
  WidgetRef ref,
  DebtStats s,
) async {
  final ok = await showAppConfirmDialog(
    context,
    title: '一次還清？',
    message: '${s.debt.name} 剩下 ${money(s.remaining)} 一次付清，之後不用再繳。',
    confirmLabel: '還清',
    destructive: false,
  );
  if (!ok) return;
  await ref
      .read(debtRepositoryProvider)
      .updateDebt(
        s.debt.copyWith(
          payoffAt: () => DateTime.now(),
          payoffAmount: () => s.remaining,
        ),
      );
  _bump(ref);
  final after = (await _fresh(ref)).statsOf(s.debt.id);
  if (context.mounted && after != null) await showPaidOffDialog(context, after);
}

Future<void> deleteDebtFlow(
  BuildContext context,
  WidgetRef ref,
  DebtStats s,
) async {
  final ok = await showAppConfirmDialog(
    context,
    title: '刪除這筆債務？',
    message: '${s.debt.name}，連同 ${s.paidCount} 筆還款紀錄都會刪掉。',
    confirmLabel: '刪除',
  );
  if (!ok) return;
  await ref.read(debtRepositoryProvider).deleteDebt(s.debt.id);
  _bump(ref);
  if (context.mounted) showAppNotice(context, '已刪除：${s.debt.name}');
}

Future<void> editIncomeFlow(
  BuildContext context,
  WidgetRef ref,
  double? current,
) async {
  final v = await showIncomeDialog(context, current);
  if (v == null) return;
  await ref.read(debtRepositoryProvider).setIncome(v);
  _bump(ref);
}

/// 打開債務明細（攤還表／還款紀錄／提前還款／資料）。
Future<void> openDebtFlow(
  BuildContext context,
  WidgetRef ref,
  DebtStats s, {
  DebtDetailView view = DebtDetailView.schedule,
}) async {
  final action = await showDebtDetailSheet(context, stats: s, initial: view);
  if (action == null || !context.mounted) return;
  final data = await _fresh(ref);
  final cur = data.statsOf(s.debt.id) ?? s;
  if (!context.mounted) return;
  switch (action) {
    case DebtAction.pay:
      await payFlow(context, ref, cur);
    case DebtAction.cancelLatest:
      await cancelLatestFlow(context, ref, cur);
    case DebtAction.payoff:
      await payoffFlow(context, ref, cur);
    case DebtAction.edit:
      await debtFormFlow(context, ref, data, edit: cur.debt);
    case DebtAction.delete:
      await deleteDebtFlow(context, ref, cur);
  }
}
