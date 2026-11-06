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
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'ledger_data.dart';
import 'ledger_ui.dart';

/// 每月訂閱（2026-11-05 使用者：記錄每月幾號會被扣多少錢、是什麼服務，**單純紀錄用**）。
/// 不會自動記進交易、不影響本月消費；資料跟記帳一起多裝置同步，每個動作都進記帳的
/// 操作紀錄。
final ledgerSubsProvider = FutureProvider.autoDispose<List<LedgerSubscription>>(
  (ref) async {
    ref.watch(dataRevisionProvider);
    return ref.read(ledgerRepositoryProvider).loadSubscriptions();
  },
);

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
                  title: '每月訂閱',
                  titleIcon: Icons.autorenew_rounded,
                  titleIconColor: ledgerAccent,
                  actions: [
                    IconButton(
                      onPressed: subs == null
                          ? null
                          : () => _edit(context, ref, null),
                      icon: const Icon(Icons.add_rounded, size: 24),
                      color: AppColors.ink2,
                      tooltip: '新增訂閱',
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
    final active = subs.where((s) => s.active).toList();
    final stopped = subs.where((s) => !s.active).toList();
    final total = subsMonthlyTotal(subs);
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
            Text('每月扣款合計・訂閱中 ${active.length} 項', style: AppText.note),
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
              '一年約 ${lMoney(total * 12)}',
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
          ],
        ),
      ),
      const SizedBox(height: Gap.md),
      if (subs.isEmpty)
        InlineEmptyCard(
          title: '還沒有訂閱',
          message: '把每月自動扣款的服務記下來，例如 Netflix、Spotify、iCloud',
          actions: [EmptyAction('新增訂閱', () => _edit(context, ref, null))],
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
          '這裡單純記錄：不會自動記進帳、也不影響本月消費。'
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
    final sub = [
      if (s.active) '下次 ${_nextText(s, now)}' else '已停用',
      if (s.note.isNotEmpty) s.note,
    ].join('・');
    return Opacity(
      opacity: s.active ? 1 : 0.55,
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
                  color: ledgerAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${s.day}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ledgerAccent,
                      ),
                    ),
                    Text(
                      '號',
                      style: AppText.note.copyWith(
                        fontSize: 10,
                        color: ledgerAccent,
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
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
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
        message: '只是不再記錄這筆訂閱，不影響任何帳。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.deleteSubscription(edit.id);
    } else if (edit == null) {
      await repo.addSubscription(
        name: r.name,
        amount: r.amount,
        day: r.day,
        note: r.note,
        active: r.active,
      );
    } else {
      await repo.updateSubscription(
        edit.copyWith(
          name: r.name,
          amount: r.amount,
          day: r.day,
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
    this.note = '',
    this.active = true,
  });

  final bool delete;
  final String name;
  final int amount;
  final int day;
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
  late bool _active = widget.edit?.active ?? true;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _amount, _day]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _day, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _input(String hint, {String? prefix, String? suffix}) =>
      InputDecoration(hintText: hint, prefixText: prefix, suffixText: suffix);

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(t, style: AppText.note),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.edit;
    final amount = int.tryParse(_amount.text) ?? 0;
    final day = int.tryParse(_day.text) ?? 0;
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
                  e == null ? '新增訂閱' : '編輯訂閱',
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
          _label('服務名稱'),
          TextField(
            controller: _name,
            autofocus: e == null,
            inputFormatters: halfWidthFormatters,
            maxLength: 50,
            decoration: _input('例如 Netflix').copyWith(counterText: ''),
          ),
          _label('每月扣多少'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [const DigitsInputFormatter()],
            decoration: _input('例如 390', prefix: '\$ '),
          ),
          _label('每月幾號扣款'),
          TextField(
            controller: _day,
            keyboardType: TextInputType.number,
            inputFormatters: [const DigitsInputFormatter()],
            decoration: _input('1～31', suffix: '號'),
          ),
          if (day > 31)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '每月幾號要在 1～31 之間',
                style: AppText.note.copyWith(color: ledgerBad),
              ),
            ),
          _label('備註（選填）'),
          TextField(
            controller: _note,
            maxLength: ledgerNoteMax,
            inputFormatters: halfWidthFormatters,
            decoration: _input('例如 家庭方案、年繳').copyWith(counterText: ''),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('訂閱中'),
            subtitle: Text('關掉＝已取消或暫停，不算進每月合計', style: AppText.note),
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
