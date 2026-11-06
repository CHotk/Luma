import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/ledger_subscriptions.dart';
import '../../domain/models/ledger.dart';
import '../../shared/digits_input.dart';
import '../../shared/half_width_input.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/date_time_wheel.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'ledger_data.dart';
import 'ledger_ui.dart';

/// 每月扣款（2026-11-05 使用者：記錄每月幾號會被扣多少錢、是什麼服務，**單純紀錄用**；
/// 2026-11-06 改叫「每月扣款」，其中可以區分「訂閱」跟「欠款」兩種標示）。
/// 是一個獨立的小功能，只用來釐清每月該繳多少錢：不會自動記進交易、不影響本月消費、
/// 跟任何帳戶或信用卡餘額沒有關連；資料跟記帳一起多裝置同步，每個動作都進記帳的操作紀錄。
final ledgerSubsProvider = FutureProvider.autoDispose<List<LedgerSubscription>>(
  (ref) async {
    ref.watch(dataRevisionProvider);
    return ref.read(ledgerRepositoryProvider).loadSubscriptions();
  },
);

Color _kindColor(LedgerChargeKind k) =>
    k == LedgerChargeKind.subscription ? ledgerAccent : AppColors.mid;

class LedgerSubsPage extends ConsumerWidget {
  const LedgerSubsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(ledgerSubsProvider).valueOrNull;
    return Scaffold(
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
                  title: '每月扣款',
                  titleIcon: Icons.autorenew_rounded,
                  titleIconColor: ledgerAccent,
                  actions: [
                    IconButton(
                      onPressed: subs == null
                          ? null
                          : () => _edit(context, ref, null),
                      icon: const Icon(Icons.add_rounded, size: 24),
                      color: AppColors.ink2,
                      tooltip: '新增每月扣款',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: subs == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: _body(context, ref, subs),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    List<LedgerSubscription> subs,
  ) {
    final now = DateTime.now();
    // 扣款中＝開關開著、欠款的期數也還沒扣完（扣完＝已繳清，跟已停用一起放下面）。
    final active = subs.where((s) => isCharging(s, now)).toList();
    final stopped = subs.where((s) => !isCharging(s, now)).toList();
    final total = subsMonthlyTotal(subs, now: now);
    final subTotal = subsMonthlyTotal(
      subs,
      kind: LedgerChargeKind.subscription,
      now: now,
    );
    final debtTotal = subsMonthlyTotal(
      subs,
      kind: LedgerChargeKind.debt,
      now: now,
    );
    // 欠款還剩多少沒繳（只算填了總期數跟第一期、算得出來的）。
    final debtLeft = active
        .map((s) => remainingAmount(s, now))
        .whereType<int>()
        .fold<int>(0, (a, b) => a + b);
    final debtLeftCount = active
        .where((s) => remainingAmount(s, now) != null)
        .length;
    LedgerSubscription? next;
    for (final s in active) {
      if (next == null ||
          nextSubCharge(s, now).isBefore(nextSubCharge(next, now))) {
        next = s;
      }
    }
    return [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('每月扣款合計・扣款中 ${active.length} 項', style: AppText.note),
            const SizedBox(height: 4),
            Text(
              lMoney(total),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: ledgerAccent,
                fontFeatures: lTabular,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '訂閱 ${lMoney(subTotal)}・欠款 ${lMoney(debtTotal)}・一年約 ${lMoney(total * 12)}',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: Color(0x33FFFFFF)),
              const SizedBox(height: 10),
              Text(
                '下一筆：${_nextText(next, now)}　${next.name}　${lMoney(next.amount)}',
                style: AppText.note.copyWith(color: AppColors.ink2),
              ),
            ],
            if (debtLeftCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '欠款還剩 ${lMoney(debtLeft)} 沒繳（$debtLeftCount 筆，剩餘期數 × 每月扣款）',
                style: AppText.note.copyWith(color: AppColors.mid),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: Gap.md),
      if (subs.isEmpty)
        InlineEmptyCard(
          title: '還沒有每月扣款',
          message: '把每月會被扣的錢記下來：訂閱（Netflix、Spotify、iCloud）或欠款（分期、借款）',
          actions: [EmptyAction('新增每月扣款', () => _edit(context, ref, null))],
        )
      else ...[
        for (final s in active) _tile(context, ref, s, now),
        if (stopped.isNotEmpty) ...[
          ledgerSection('已停用（不算進合計）'),
          for (final s in stopped) _tile(context, ref, s, now),
        ],
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          '這裡單純記錄，只是用來釐清每月該繳多少：不會自動記進帳、不影響本月消費，'
          '也跟帳戶、信用卡餘額沒有關連。'
          '扣款日遇到沒有那天的月份（例如 31 號碰到 2 月）算那個月最後一天。',
          style: AppText.note.copyWith(color: AppColors.ink3, height: 1.5),
        ),
      ),
    ];
  }

  static String _nextText(LedgerSubscription s, DateTime now) {
    final d = daysUntilSubCharge(s, now);
    return '${lMd(nextSubCharge(s, now))}'
        '（${d == 0 ? '今天' : '還有 $d 天'}）';
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    LedgerSubscription s,
    DateTime now,
  ) {
    final charging = isCharging(s, now);
    final paid = paidPeriods(s, now);
    final left = remainingPeriods(s, now);
    final extra = extraPaid(s);
    final sub = [
      if (charging)
        '下次 ${_nextText(s, now)}'
      else if (isFinished(s, now))
        '已繳清'
      else
        '已停用',
      if (s.note.isNotEmpty) s.note,
    ].join('・');
    // 欠款的期數、貸款總額（2026-11-06 使用者）：共幾期、已繳幾期、還剩幾期、貸款總額、
    // 總共要繳多少（比貸款總額多的是利息之類）。
    final debtLine = s.kind != LedgerChargeKind.debt
        ? null
        : [
            if (s.periods != null)
              paid == null
                  ? '共 ${s.periods} 期'
                  : '已繳 $paid／${s.periods} 期・剩 $left 期（${lMoney(left! * s.amount)}）',
            if (s.loanTotal != null) '貸款總額 ${lMoney(s.loanTotal!)}',
            if (extra != null) '多繳 ${lMoney(extra)}',
          ].join('・');
    return Opacity(
      opacity: charging ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          onTap: () => _edit(context, ref, s),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _kindColor(s.kind).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${s.day}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _kindColor(s.kind),
                      ),
                    ),
                    Text(
                      '號',
                      style: AppText.note.copyWith(
                        fontSize: 10,
                        color: _kindColor(s.kind),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        LedgerPill(s.kind.label, color: _kindColor(s.kind)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.note.copyWith(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                      ),
                    ),
                    if (debtLine != null && debtLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        debtLine,
                        style: AppText.note.copyWith(
                          fontSize: 10.5,
                          color: AppColors.mid,
                        ),
                      ),
                    ],
                    // 期數進度條：已繳幾期／總期數。
                    if (paid != null && (s.periods ?? 0) > 0) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (paid / s.periods!).clamp(0, 1).toDouble(),
                          minHeight: 4,
                          backgroundColor: const Color(0xFF1E1E2E),
                          color: _kindColor(s.kind),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lMoney(s.amount),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  fontFeatures: lTabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LedgerSubscription? edit,
  ) async {
    final r = await showModalBottomSheet<_SubResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: _SubForm(edit: edit),
      ),
    );
    if (r == null) return;
    final repo = ref.read(ledgerRepositoryProvider);
    if (r.delete) {
      if (!context.mounted) return;
      final ok = await showAppConfirmDialog(
        context,
        title: '刪除「${edit!.name}」？',
        message: '只是不再記錄這筆每月扣款，不影響任何帳。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.deleteSubscription(edit.id);
    } else if (edit == null) {
      await repo.addSubscription(
        name: r.name,
        amount: r.amount,
        day: r.day,
        kind: r.kind,
        periods: r.periods,
        loanTotal: r.loanTotal,
        startMonth: r.startMonth,
        note: r.note,
        active: r.active,
      );
    } else {
      await repo.updateSubscription(
        edit.copyWith(
          name: r.name,
          amount: r.amount,
          day: r.day,
          kind: r.kind,
          periods: () => r.periods,
          loanTotal: () => r.loanTotal,
          startMonth: () => r.startMonth,
          note: r.note,
          active: r.active,
        ),
      );
    }
    ref.read(dataRevisionProvider.notifier).state++;
    if (context.mounted) {
      showAppNotice(
        context,
        r.delete
            ? '已刪除'
            : edit == null
            ? '已新增：${r.name}'
            : '已更新',
      );
    }
  }
}

class _SubResult {
  const _SubResult({
    this.delete = false,
    this.name = '',
    this.amount = 0,
    this.day = 1,
    this.kind = LedgerChargeKind.subscription,
    this.periods,
    this.loanTotal,
    this.startMonth,
    this.note = '',
    this.active = true,
  });

  final bool delete;
  final String name;
  final int amount;
  final int day;
  final LedgerChargeKind kind;
  final int? periods;
  final int? loanTotal;
  final String? startMonth;
  final String note;
  final bool active;
}

class _SubForm extends StatefulWidget {
  const _SubForm({required this.edit});

  final LedgerSubscription? edit;

  @override
  State<_SubForm> createState() => _SubFormState();
}

class _SubFormState extends State<_SubForm> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.edit == null ? '' : '${widget.edit!.amount}',
  );
  late final _day = TextEditingController(
    text: widget.edit == null ? '' : '${widget.edit!.day}',
  );
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late final _loan = TextEditingController(
    text: widget.edit?.loanTotal == null ? '' : '${widget.edit!.loanTotal}',
  );
  late final _periods = TextEditingController(
    text: widget.edit?.periods == null ? '' : '${widget.edit!.periods}',
  );

  /// 欠款第一期扣款的月份，`yyyy-MM`（選填；有了才算得出已繳幾期）。
  late String? _start = widget.edit?.startMonth;
  late bool _active = widget.edit?.active ?? true;
  late LedgerChargeKind _kind =
      widget.edit?.kind ?? LedgerChargeKind.subscription;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _amount, _day, _loan, _periods]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _day, _note, _loan, _periods]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _input(String hint, {String? prefix, String? suffix}) =>
      InputDecoration(hintText: hint, prefixText: prefix, suffixText: suffix);

  /// 標題跟輸入框同一行（2026-11-06 使用者）。
  Widget _row(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        SizedBox(width: 78, child: Text(label, style: AppText.note)),
        Expanded(child: field),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.edit;
    final amount = int.tryParse(_amount.text) ?? 0;
    final day = int.tryParse(_day.text) ?? 0;
    final isDebt = _kind == LedgerChargeKind.debt;
    final loan = int.tryParse(_loan.text);
    final periods = int.tryParse(_periods.text);
    final payable = isDebt && periods != null && periods > 0 && amount > 0
        ? periods * amount
        : null;
    final ok =
        _name.text.trim().isNotEmpty && amount > 0 && day >= 1 && day <= 31;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e == null ? '新增每月扣款' : '編輯每月扣款',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.ink2,
                tooltip: '關閉',
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 訂閱或欠款（只是標示，算法一樣）。
          SegmentedButton<LedgerChargeKind>(
            segments: [
              for (final k in LedgerChargeKind.values)
                ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          _row(
            _kind == LedgerChargeKind.subscription ? '服務名稱' : '欠款名稱',
            TextField(
              controller: _name,
              autofocus: e == null,
              maxLength: 50,
              inputFormatters: halfWidthFormatters,
              decoration: _input(
                _kind == LedgerChargeKind.subscription
                    ? '例如 Netflix'
                    : '例如 手機分期、朋友借款',
              ).copyWith(counterText: ''),
            ),
          ),
          _row(
            '每月扣多少',
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [const DigitsInputFormatter()],
              decoration: _input('例如 390', prefix: '\$ '),
            ),
          ),
          _row(
            '每月幾號',
            TextField(
              controller: _day,
              keyboardType: TextInputType.number,
              inputFormatters: [const DigitsInputFormatter()],
              decoration: _input('1～31', suffix: '號'),
            ),
          ),
          if (day > 31)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '每月幾號要在 1～31 之間',
                style: AppText.note.copyWith(color: ledgerBad),
              ),
            ),
          if (isDebt) ...[
            _row(
              '貸款總額',
              TextField(
                controller: _loan,
                keyboardType: TextInputType.number,
                inputFormatters: [const DigitsInputFormatter()],
                decoration: _input('實際借了多少（選填）', prefix: '\$ '),
              ),
            ),
            _row(
              '總期數',
              TextField(
                controller: _periods,
                keyboardType: TextInputType.number,
                inputFormatters: [const DigitsInputFormatter()],
                decoration: _input('例如 12（選填）', suffix: '期'),
              ),
            ),
            _row(
              '第一期',
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final start = _start?.split('-');
                  final init = start != null && start.length == 2
                      ? DateTime(
                          int.tryParse(start[0]) ?? now.year,
                          int.tryParse(start[1]) ?? now.month,
                          day >= 1 && day <= 28 ? day : 1,
                        )
                      : now;
                  final v = await showDateTimeWheel(context, init);
                  if (v != null && mounted) {
                    setState(() => _start = monthKeyOf(v));
                  }
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(
                  _start == null
                      ? '第一期扣款是哪個月（選填）'
                      : '${_start!.replaceFirst('-', '/')}（點一下改）',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 78),
              child: Text(
                payable == null
                    ? '填了總期數跟第一期，就會算已繳幾期、還剩多少'
                    : '總共要繳 \$$payable'
                          '${loan != null && loan > 0 && payable > loan ? '，比貸款總額多 \$${payable - loan}' : ''}',
                style: AppText.note.copyWith(color: AppColors.mid),
              ),
            ),
          ],
          _row(
            '備註',
            TextField(
              controller: _note,
              maxLength: ledgerNoteMax,
              inputFormatters: halfWidthFormatters,
              decoration: _input(
                '選填，例如 家庭方案、還到 12 月',
              ).copyWith(counterText: ''),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('扣款中'),
            subtitle: Text('關掉＝已取消、暫停或已還清，不算進每月合計', style: AppText.note),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (e != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, const _SubResult(delete: true)),
                    style: OutlinedButton.styleFrom(foregroundColor: ledgerBad),
                    child: const Text('刪除'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: !ok
                      ? null
                      : () => Navigator.pop(
                          context,
                          _SubResult(
                            name: _name.text.trim(),
                            amount: amount,
                            day: day,
                            kind: _kind,
                            periods: isDebt ? periods : null,
                            loanTotal: isDebt ? loan : null,
                            startMonth: isDebt ? _start : null,
                            note: _note.text.trim(),
                            active: _active,
                          ),
                        ),
                  child: Text(e == null ? '新增' : '儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
