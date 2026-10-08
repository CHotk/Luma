import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/debt_schedule.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'debt_data.dart';
import 'debt_sheets.dart';
import 'debt_ui.dart';

/// 負債每月還款表（2026-10-08 使用者從
/// `design-history/2026-10-08_負債每月還款表五種設計.html` 挑了版本 1「記帳 App 式」，
/// 並要求有按鈕能進版本 2 的月曆）。下方四個分頁：總覽／本月／債務／試算，
/// 右下角 ＋ 新增債務；右上角月曆圖示進月曆檢視（`/debt/calendar`）。
class DebtPage extends ConsumerStatefulWidget {
  const DebtPage({super.key});

  @override
  ConsumerState<DebtPage> createState() => _DebtPageState();
}

enum _Tab { home, month, debts, plan }

class _DebtPageState extends ConsumerState<DebtPage> {
  _Tab _tab = _Tab.home;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _filter = 0; // 0 全部、1 還款中、2 已還清

  static const _titles = {
    _Tab.home: '負債總覽',
    _Tab.month: '每月要繳',
    _Tab.debts: '我的債務',
    _Tab.plan: '還款試算',
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(debtDataProvider).valueOrNull;
    final over = data?.totals.overdueCount ?? 0;
    return Scaffold(
      drawer: const AppSideDrawer(),
      floatingActionButton: data == null
          ? null
          : FloatingActionButton(
              onPressed: () => debtFormFlow(context, ref, data),
              tooltip: '新增債務',
              child: const Icon(Icons.add_rounded),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => setState(() => _tab = _Tab.values[i]),
        height: 64,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: '總覽',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: over > 0,
              label: Text('$over'),
              child: const Icon(Icons.event_note_outlined),
            ),
            selectedIcon: const Icon(Icons.event_note_rounded),
            label: '本月',
          ),
          const NavigationDestination(
            icon: Icon(Icons.list_alt_rounded),
            label: '債務',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '試算',
          ),
        ],
      ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: _titles[_tab]!,
                  titleIcon: Icons.account_balance_wallet_outlined,
                  showBack: false,
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/debt/calendar'),
                      icon: const Icon(Icons.calendar_month_rounded, size: 22),
                      color: AppColors.ink2,
                      tooltip: '月曆檢視',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
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
                          padding: const EdgeInsets.only(bottom: 96),
                          children: switch (_tab) {
                            _Tab.home => _home(data),
                            _Tab.month => _monthTab(data),
                            _Tab.debts => _debtsTab(data),
                            _Tab.plan => _planTab(data),
                          },
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

  Widget _section(String title, {String? action, VoidCallback? onAction}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
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
            if (action != null)
              InkWell(
                onTap: onAction,
                child: Text(
                  action,
                  style: AppText.note.copyWith(color: AppColors.ink3),
                ),
              ),
          ],
        ),
      );

  Widget _links(DebtData data) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => showStrategySheet(context, data.totals.active),
          icon: const Icon(Icons.explore_outlined, size: 18),
          label: const Text('先還哪一筆'),
          style: _outline,
        ),
      ),
      const SizedBox(width: Gap.sm),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => showAllRecordsSheet(context, data.stats),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('還款紀錄'),
          style: _outline,
        ),
      ),
    ],
  );

  static final _outline = OutlinedButton.styleFrom(
    foregroundColor: AppColors.ink,
    side: const BorderSide(color: AppColors.glassEdge),
    padding: const EdgeInsets.symmetric(vertical: 12),
  );

  List<Widget> _empty(DebtData data) => [
    InlineEmptyCard(
      title: '還沒有債務',
      message: '按右下角 ＋ 新增第一筆：信貸、車貸、學貸、信用卡分期、跟家人借的都可以',
      actions: [EmptyAction('新增債務', () => debtFormFlow(context, ref, data))],
    ),
  ];

  // ── 總覽 ─────────────────────────────────────────────────

  List<Widget> _home(DebtData data) {
    if (data.stats.isEmpty) return _empty(data);
    final t = data.totals;
    final up = t.thisMonth.where((x) => !x.isPaid).toList();
    final now = DateTime.now();
    return [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('剩餘負債總額', style: AppText.note),
                const Spacer(),
                Text(
                  '${t.active.length} 筆',
                  style: AppText.note.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              money(t.remaining),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 10),
            DebtBar(t.paidPercent),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '已還 ${t.paidPercent.toStringAsFixed(0)}%',
                  style: AppText.note,
                ),
                const Spacer(),
                Text('全部還清 ', style: AppText.note),
                Text(
                  t.freeDate == null ? '—' : ym(t.freeDate!),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
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
            Row(
              children: [
                Text('${now.month} 月還款', style: AppText.note),
                const Spacer(),
                incomeRatioLabel(
                  t.incomeRatio,
                  () => editIncomeFlow(context, ref, data.income),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(t.paidThisMonth),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ok,
                  ),
                ),
                Text(' / ${money(t.dueThisMonth)}', style: AppText.note),
                const Spacer(),
                t.overdueCount > 0
                    ? DebtPill('逾期 ${t.overdueCount} 筆', color: debtBad)
                    : DebtPill('還有 ${up.length} 筆', color: debtAccent),
              ],
            ),
            const SizedBox(height: 8),
            DebtBar(
              t.dueThisMonth <= 0 ? 0 : t.paidThisMonth / t.dueThisMonth * 100,
              color: AppColors.ok,
            ),
          ],
        ),
      ),
      _section(
        '接下來要繳',
        action: '本月全部 ›',
        onAction: () => setState(() {
          _tab = _Tab.month;
          _month = DateTime(now.year, now.month);
        }),
      ),
      if (up.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('這個月都繳完了 👍', style: AppText.bodyDim),
        )
      else
        for (final x in up.take(3)) _due(x),
      const SizedBox(height: Gap.md),
      Row(
        children: [
          DebtKpi(money(t.monthly), '每月固定'),
          const SizedBox(width: 6),
          DebtKpi(money(t.interestLeft), '還要付利息'),
          const SizedBox(width: 6),
          DebtKpi(money(t.interestPaid), '已付利息'),
        ],
      ),
      const SizedBox(height: Gap.md),
      _links(data),
      const SizedBox(height: Gap.sm),
      OutlinedButton.icon(
        onPressed: () => context.push('/debt/calendar'),
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: const Text('月曆檢視（扣款日一眼看）'),
        style: _outline,
      ),
    ];
  }

  // ── 本月 ─────────────────────────────────────────────────

  List<Widget> _monthTab(DebtData data) {
    final list = duesOfMonth(data.stats, _month);
    final due = list
        .where((x) => !x.isPayoff)
        .fold(0.0, (s, x) => s + x.amount);
    final paid = list
        .where((x) => x.isPaid && !x.isPayoff)
        .fold(0.0, (s, x) => s + x.amount);
    return [
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
            child: Text(
              '${_month.year} 年 ${_month.month} 月',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
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
      const SizedBox(height: Gap.sm),
      Row(
        children: [
          DebtKpi(money(due), '應繳'),
          const SizedBox(width: 6),
          DebtKpi(money(paid), '已繳', color: AppColors.ok),
          const SizedBox(width: 6),
          DebtKpi(
            money(due - paid),
            '未繳',
            color: due - paid > 0 ? AppColors.mid : null,
          ),
        ],
      ),
      const SizedBox(height: Gap.md),
      if (list.isEmpty)
        Text('這個月沒有要繳的', style: AppText.bodyDim)
      else
        for (final x in list) _due(x),
      const SizedBox(height: 6),
      Text(
        '點左邊圓圈標記已繳・點整列看明細',
        style: AppText.note.copyWith(color: AppColors.ink3),
      ),
    ];
  }

  // ── 債務 ─────────────────────────────────────────────────

  List<Widget> _debtsTab(DebtData data) {
    if (data.stats.isEmpty) return _empty(data);
    final shown = data.stats.where(
      (s) => switch (_filter) {
        1 => !s.closed,
        2 => s.closed,
        _ => true,
      },
    );
    return [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('全部')),
          ButtonSegment(value: 1, label: Text('還款中')),
          ButtonSegment(value: 2, label: Text('已還清')),
        ],
        selected: {_filter},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _filter = v.first),
      ),
      const SizedBox(height: Gap.md),
      if (shown.isEmpty) Text('沒有', style: AppText.bodyDim),
      for (final s in shown)
        DebtCard(stats: s, onTap: () => openDebtFlow(context, ref, s)),
    ];
  }

  // ── 試算 ─────────────────────────────────────────────────

  List<Widget> _planTab(DebtData data) {
    final t = data.totals;
    final ratio = t.incomeRatio;
    return [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('如果每月多還一點', style: AppText.note),
            const SizedBox(height: 4),
            Text('每一筆的「提前還」可以分開試算；這裡看整體該先還哪一筆。', style: AppText.bodyDim),
            const SizedBox(height: Gap.md),
            FilledButton.icon(
              onPressed: () => showStrategySheet(context, t.active),
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text('多的錢先還哪一筆'),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.md),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('還款佔收入', style: AppText.note),
                const Spacer(),
                incomeRatioLabel(
                  ratio,
                  () => editIncomeFlow(context, ref, data.income),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '每月固定還款 ${money(t.monthly)}'
              '${data.income == null ? '' : '，月收入 ${money(data.income!)}'}。'
              '一般建議不要超過 33–40%。',
              style: AppText.bodyDim,
            ),
            const SizedBox(height: 8),
            DebtBar(
              (ratio ?? 0).clamp(0, 100),
              color: (ratio ?? 0) > 40 ? debtBad : AppColors.ok,
            ),
          ],
        ),
      ),
      _section('每筆提前還款試算'),
      if (t.active.isEmpty) Text('沒有還款中的債務', style: AppText.bodyDim),
      for (final s in t.active)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              onTap: () =>
                  openDebtFlow(context, ref, s, view: DebtDetailView.prepay),
              leading: DebtIcon(s.debt.type),
              title: Text(
                s.debt.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                '${s.debt.rate}%・還要付利息 ${money(s.interestLeft)}',
                style: AppText.note,
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink3,
              ),
            ),
          ),
        ),
      const SizedBox(height: Gap.sm),
      _links(data),
    ];
  }
}
