import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/debt_schedule.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'debt_data.dart';
import 'debt_ui.dart';

/// 負債的月曆檢視（設計稿版本 2「月曆帳單式」，2026-10-08 使用者要求主畫面
/// 用版本 1，另外要有按鈕能進這個）。扣款日在月曆上標色點（每筆債務一個
/// 顏色，已繳變淡）跟當天金額，逾期那格變紅；點一天看那天要繳的，下面列
/// 這個月還沒繳的。
class DebtCalendarPage extends ConsumerStatefulWidget {
  const DebtCalendarPage({super.key});

  @override
  ConsumerState<DebtCalendarPage> createState() => _DebtCalendarPageState();
}

class _DebtCalendarPageState extends ConsumerState<DebtCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _sel = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(debtDataProvider).valueOrNull;
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
                const AppTopBar(title: '還款月曆'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: _body(data),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _due(DueItem x) => DueTile(
    item: x,
    today: DateTime.now(),
    onTap: () => openDebtFlow(context, ref, x.stats),
    onCheck: () => toggleDueFlow(context, ref, x),
  );

  List<Widget> _body(DebtData data) {
    final today = dayOnly(DateTime.now());
    final list = duesOfMonth(data.stats, _month);
    final due = list
        .where((x) => !x.isPayoff)
        .fold(0.0, (s, x) => s + x.amount);
    final paid = list
        .where((x) => x.isPaid && !x.isPayoff)
        .fold(0.0, (s, x) => s + x.amount);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month).weekday % 7;
    final selList = list.where((x) => dayOnly(x.row.date) == _sel).toList();
    final unpaid = list.where((x) => !x.isPaid).toList();

    return [
      GlassCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
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
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${_month.year} 年 ${_month.month} 月',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          style: AppText.note,
                          children: [
                            const TextSpan(text: '已繳 '),
                            TextSpan(
                              text: money(paid),
                              style: const TextStyle(color: AppColors.ok),
                            ),
                            TextSpan(text: ' / ${money(due)}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.ink2,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Center(child: Text(w, style: AppText.note)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.82,
              children: [
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _cell(
                    DateTime(_month.year, _month.month, d),
                    list
                        .where(
                          (x) =>
                              dayOnly(x.row.date) ==
                              DateTime(_month.year, _month.month, d),
                        )
                        .toList(),
                    today,
                  ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final s in data.totals.active)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: s.debt.type.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(s.debt.name, style: AppText.note),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(
          children: [
            Text(
              mdw(_sel),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
            const Spacer(),
            Text(
              selList.isEmpty ? '這天沒有要繳' : '${selList.length} 筆',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
          ],
        ),
      ),
      for (final x in selList) _due(x),
      if (unpaid.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              const Text(
                '這個月還沒繳',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2,
                ),
              ),
              const Spacer(),
              Text(
                money(unpaid.fold(0.0, (s, x) => s + x.amount)),
                style: AppText.note.copyWith(color: AppColors.ink3),
              ),
            ],
          ),
        ),
        for (final x in unpaid) _due(x),
      ] else if (list.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GlassCard(
            child: Center(
              child: Text(
                '這個月都繳完了 👍',
                style: AppText.body.copyWith(color: AppColors.ok),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _cell(DateTime day, List<DueItem> items, DateTime today) {
    final sum = items.fold(0.0, (s, x) => s + x.amount);
    final over = items.any((x) => x.isOverdue(today));
    final sel = day == _sel;
    return Material(
      color: over
          ? debtBad.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _sel = day),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: sel
                ? Border.all(color: debtAccent, width: 1.5)
                : day == today
                ? Border.all(color: AppColors.ink3)
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(4, 3, 3, 4),
          child: Stack(
            children: [
              Text(
                '${day.day}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.ink2),
              ),
              if (sum > 0)
                Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    sum >= 10000
                        ? '${(sum / 10000).toStringAsFixed(1)}萬'
                        : fmtInt(sum),
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (final x in items)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: x.debt.type.color.withValues(
                            alpha: x.isPaid ? 0.35 : 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
