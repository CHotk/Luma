import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/debt_schedule.dart';
import '../../domain/models/debt.dart';
import 'debt_ui.dart';

/// 負債的底部表單：新增／編輯債務、標記已繳、債務明細（攤還表、還款紀錄、
/// 提前還款、資料）、先還哪一筆、全部還款紀錄，還有月收入、還清慶祝兩個
/// 對話框。

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: child,
      ),
    );

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.glassEdge,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
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
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
            ),
            child: footer,
          ),
      ],
    ),
  );
}

Widget _label(String text, {String? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 6),
  child: Row(
    children: [
      Text(text, style: AppText.note),
      const Spacer(),
      if (trailing != null)
        Text(trailing, style: AppText.note.copyWith(color: AppColors.ink3)),
    ],
  ),
);

InputDecoration _input(String hint, {String? suffix}) => InputDecoration(
  hintText: hint,
  suffixText: suffix,
  isDense: true,
  filled: true,
  fillColor: const Color(0xFF161622),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFF2A2A3D)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFF2A2A3D)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: debtAccent),
  ),
);

final _digits = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];

Widget _calc(List<InlineSpan> spans, {Color? border}) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.03),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: border ?? const Color(0xFF2A2A3D)),
  ),
  child: Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.75),
      children: spans,
    ),
  ),
);

TextSpan _b(String s, {Color color = AppColors.ink, double? size}) => TextSpan(
  text: s,
  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size),
);

Widget _kv(String k, String v, {Color? color}) => Container(
  padding: const EdgeInsets.symmetric(vertical: 9),
  decoration: const BoxDecoration(
    border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
  ),
  child: Row(
    children: [
      Text(k, style: AppText.bodyDim),
      const Spacer(),
      Flexible(
        child: Text(
          v,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink,
          ),
        ),
      ),
    ],
  ),
);

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

// ── 標記已繳 ──────────────────────────────────────────────

Future<({double amount, DateTime date})?> showPaySheet(
  BuildContext context, {
  required DebtStats stats,
}) => _sheet(context, _PaySheet(stats: stats));

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.stats});

  final DebtStats stats;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final _ctrl = TextEditingController(
    text: fmtInt(widget.stats.next!.pay).replaceAll(',', ''),
  );
  DateTime _date = dayOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats, d = s.debt, r = s.next!;
    final amt = double.tryParse(_ctrl.text);
    final after = d.isBill
        ? 0.0
        : math.max(0.0, s.remaining - (d.flexible ? (amt ?? 0) : r.principal));
    return _Frame(
      title: '標記已繳',
      footer: FilledButton(
        onPressed: amt == null || amt <= 0
            ? null
            : () => Navigator.pop(context, (amount: amt, date: _date)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('確認已繳'),
      ),
      children: [
        Row(
          children: [
            DebtIcon(d.type),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '${d.lenderPrefix}'
                    '${d.isBill
                        ? '${r.date.month} 月帳單・'
                        : d.flexible
                        ? ''
                        : '第 ${r.k} / ${s.totalCount} 期・'}'
                    '${mdw(r.date)} 扣款',
                    style: AppText.note,
                  ),
                ],
              ),
            ),
            Text(
              money(r.pay),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        if (s.overdueDays > 0)
          _calc([
            TextSpan(
              text: '已經逾期 ${s.overdueDays} 天。銀行可能已經收違約金，記得確認一下帳單。',
              style: const TextStyle(color: debtBad),
            ),
          ], border: debtBad.withValues(alpha: 0.5)),
        _label('實繳金額', trailing: '跟應繳不一樣可以改'),
        TextField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _digits,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          decoration: _input('金額', suffix: '元'),
        ),
        _label('繳款日'),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await _pickDate(context, _date);
            if (p != null && mounted) setState(() => _date = p);
          },
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: Text(ymd(_date)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: Color(0xFF2A2A3D)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        if (d.isBill)
          _calc([const TextSpan(text: '信用卡帳單：照這期實際繳多少填，下個月一樣提醒你。')])
        else
          _calc([
            const TextSpan(text: '繳完剩餘本金 '),
            _b(money(after)),
            if (after <= 0.5) const TextSpan(text: ' 🎉 這筆就還清了'),
            if (!d.flexible)
              TextSpan(
                text: '\n本期本金 ${money(r.principal)}・利息 ${money(r.interest)}',
              ),
            if (amt != null && amt < r.pay && !d.flexible)
              TextSpan(
                text: '\n比應繳少 ${money(r.pay - amt)}，差額記得補',
                style: const TextStyle(color: AppColors.mid),
              ),
          ]),
      ],
    );
  }
}

// ── 新增／編輯債務 ────────────────────────────────────────

/// 回傳填好的債務（新增時 id 由 repository 給）；取消回傳 null。
/// [currentMonthly]、[income] 用來算「加上這筆後還款佔收入幾 %」。
Future<Debt?> showDebtFormSheet(
  BuildContext context, {
  Debt? edit,
  required double currentMonthly,
  double? income,
}) => _sheet(
  context,
  _DebtForm(edit: edit, currentMonthly: currentMonthly, income: income),
);

class _DebtForm extends StatefulWidget {
  const _DebtForm({this.edit, required this.currentMonthly, this.income});

  final Debt? edit;
  final double currentMonthly;
  final double? income;

  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  late DebtType _type = widget.edit?.type ?? DebtType.loan;
  late final bool _flex = widget.edit?.flexible ?? false;
  late DateTime _first = widget.edit == null
      ? DateTime(DateTime.now().year, DateTime.now().month + 1)
      : DateTime(widget.edit!.firstYear, widget.edit!.firstMonth);
  late final _name = TextEditingController(text: widget.edit?.name);
  late final _principal = TextEditingController(
    text: _n(widget.edit?.principal),
  );
  late final _rate = TextEditingController(text: _n(widget.edit?.rate));
  late final _term = TextEditingController(
    text: widget.edit == null || widget.edit!.term == 0
        ? ''
        : '${widget.edit!.term}',
  );
  late final _flexPay = TextEditingController(text: _n(widget.edit?.flexPay));
  late final _fee = TextEditingController(text: _n(widget.edit?.fee));
  late final _dueDay = TextEditingController(
    text: '${widget.edit?.dueDay ?? 10}',
  );

  static String _n(double? v) => v == null || v == 0
      ? ''
      : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  List<TextEditingController> get _all => [
    _name,
    _principal,
    _rate,
    _term,
    _flexPay,
    _fee,
    _dueDay,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  /// 信用卡：只記每月帳單大概多少，不填本金、利率、期數。
  bool get _bill => _type == DebtType.card;

  Debt? get _draft {
    final bill = _bill;
    final p = bill ? 0.0 : double.tryParse(_principal.text);
    final rate = _flex || bill ? 0.0 : (double.tryParse(_rate.text) ?? 0);
    final term = _flex || bill ? 0 : (int.tryParse(_term.text) ?? 0);
    final fp = _flex || bill ? (double.tryParse(_flexPay.text) ?? 0) : 0.0;
    final due = int.tryParse(_dueDay.text) ?? 0;
    if (_name.text.trim().isEmpty || p == null) return null;
    if (bill) {
      if (fp <= 0) return null;
    } else {
      if (p <= 0) return null;
      if (_flex ? fp <= 0 : term <= 0) return null;
    }
    if (due < 1 || due > 31) return null;
    final e = widget.edit;
    return Debt(
      id: e?.id ?? '',
      name: _name.text.trim(),
      lender: widget.edit?.lender ?? '',
      type: _type,
      principal: p,
      rate: rate,
      term: term,
      firstYear: _first.year,
      firstMonth: _first.month,
      dueDay: due,
      flexible: _flex && !bill,
      flexPay: fp,
      fee: bill ? 0 : (double.tryParse(_fee.text) ?? 0),
      payoffAt: e?.payoffAt,
      payoffAmount: e?.payoffAmount,
      updatedAt: e?.updatedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final calc = <InlineSpan>[];
    if (d == null) {
      calc.addAll([
        if (_bill)
          const TextSpan(text: '填名稱和這期帳單大概多少，每個月扣款日會提醒你繳')
        else ...[
          TextSpan(text: '填完名稱、本金和${_flex ? '每月預計還多少' : '利率、期數'}，這裡會算出'),
          _b('每月要繳'),
          const TextSpan(text: '、'),
          _b('總利息'),
          const TextSpan(text: '和'),
          _b('還清日'),
        ],
      ]);
    } else {
      final s = DebtStats.of(d, const []);
      final ratio = widget.income == null || widget.income! <= 0
          ? null
          : (widget.currentMonthly + (widget.edit == null ? s.monthly : 0)) /
                widget.income! *
                100;
      calc.addAll([
        TextSpan(text: _bill ? '每月大概要繳 ' : '每月要繳 '),
        _b(money(s.monthly), size: 15),
        if (_flex) const TextSpan(text: '（預計）'),
        if (_bill)
          const TextSpan(
            text:
                '\n信用卡只記每期帳單，不算本金、利息、還清日；'
                '帳單金額變了到「資料」改一下就好',
          ),
        if (!_flex && !_bill) ...[
          const TextSpan(text: '\n總利息 '),
          _b(money(s.interestTotal)),
          const TextSpan(text: '・總共要還 '),
          _b(money(d.principal + s.interestTotal)),
          if (d.fee > 0) ...[
            const TextSpan(text: '\n開辦費 '),
            _b(money(d.fee)),
            const TextSpan(text: '・總成本（利息＋開辦費）'),
            _b(money(s.totalCost), color: AppColors.mid),
          ],
        ],
        if (!_bill) ...[
          const TextSpan(text: '\n預計 '),
          _b(s.payoffDate == null ? '—' : ym(s.payoffDate!)),
          const TextSpan(text: ' 還清'),
        ],
        if (ratio != null && widget.edit == null) ...[
          const TextSpan(text: '\n加上這筆，每月還款佔收入 '),
          _b(
            '${ratio.toStringAsFixed(0)}%',
            color: ratio > 40 ? debtBad : AppColors.ink,
          ),
          if (ratio > 40) const TextSpan(text: '（超過 40%）'),
        ],
      ]);
    }
    return _Frame(
      title: widget.edit == null ? '新增債務' : '編輯債務',
      footer: FilledButton(
        onPressed: d == null ? null : () => Navigator.pop(context, d),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(widget.edit == null ? '新增' : '儲存'),
      ),
      children: [
        _label('類型'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in DebtType.values)
              ChoiceChip(
                label: Text('${t.emoji} ${t.label}'),
                selected: _type == t,
                showCheckmark: false,
                onSelected: (_) => setState(() => _type = t),
              ),
          ],
        ),
        // 只有一個名稱欄（2026-10-08 使用者：名稱跟銀行不用分兩欄）。
        _label('名稱'),
        TextField(controller: _name, decoration: _input('例如 國泰信貸')),
        // 親友借款拿掉了（2026-10-08），「自由還款」只留給舊資料編輯用。
        if (_bill) ...[
          _label('這期帳單大概多少'),
          TextField(
            controller: _flexPay,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _digits,
            decoration: _input('例如 8000', suffix: '元'),
          ),
        ] else ...[
          _label('借款本金'),
          TextField(
            controller: _principal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _digits,
            decoration: _input('例如 300000', suffix: '元'),
          ),
          if (_flex) ...[
            _label('預計每月還'),
            TextField(
              controller: _flexPay,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _digits,
              decoration: _input('例如 5000', suffix: '元'),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('年利率'),
                      TextField(
                        controller: _rate,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: _digits,
                        decoration: _input('例如 6.5', suffix: '%'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('期數'),
                      TextField(
                        controller: _term,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: _input('例如 24', suffix: '期'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          _label('開辦費', trailing: '沒有就留空'),
          TextField(
            controller: _fee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _digits,
            decoration: _input('例如 3000', suffix: '元'),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('每月扣款日'),
                  TextField(
                    controller: _dueDay,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _input('1–31', suffix: '號'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(_bill ? '從哪個月開始記' : '第一期月份'),
                  OutlinedButton(
                    onPressed: () async {
                      final p = await _pickDate(context, _first);
                      if (p != null && mounted) {
                        setState(() => _first = DateTime(p.year, p.month));
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: Color(0xFF2A2A3D)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(ym(_first)),
                  ),
                ],
              ),
            ),
          ],
        ),
        _calc(calc),
      ],
    );
  }
}

// ── 債務明細 ──────────────────────────────────────────────

enum DebtDetailView { schedule, records, prepay, info }

/// 明細裡按了會離開明細、交給外面處理的動作。
enum DebtAction { pay, cancelLatest, payoff, edit, delete }

Future<DebtAction?> showDebtDetailSheet(
  BuildContext context, {
  required DebtStats stats,
  DebtDetailView initial = DebtDetailView.schedule,
}) => _sheet(context, _DebtDetail(stats: stats, initial: initial));

class _DebtDetail extends StatefulWidget {
  const _DebtDetail({required this.stats, required this.initial});

  final DebtStats stats;
  final DebtDetailView initial;

  @override
  State<_DebtDetail> createState() => _DebtDetailState();
}

class _DebtDetailState extends State<_DebtDetail> {
  // 信用卡帳單沒有攤還表、提前還，打開時落在「紀錄」。
  late DebtDetailView _view =
      widget.stats.debt.isBill &&
          (widget.initial == DebtDetailView.schedule ||
              widget.initial == DebtDetailView.prepay)
      ? DebtDetailView.records
      : widget.initial;
  final _extra = TextEditingController(text: '2000');
  final _lump = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _extra.addListener(() => setState(() {}));
    _lump.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _extra.dispose();
    _lump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats, d = s.debt;
    final next = s.next;
    return _Frame(
      title: '債務明細',
      footer: next == null
          ? null
          : FilledButton(
              onPressed: () => Navigator.pop(context, DebtAction.pay),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                d.isBill
                    ? '標記 ${next.date.month} 月帳單已繳・約 ${money(next.pay)}'
                    : '標記${d.flexible ? '' : '第 ${next.k} 期'}已繳・${money(next.pay)}',
              ),
            ),
      children: [
        Row(
          children: [
            DebtIcon(d.type),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '${d.lenderPrefix}${d.type.label}・'
                    '${d.isBill
                        ? '每月帳單'
                        : d.flexible
                        ? '自由還款'
                        : '年利率 ${d.rate}%'}',
                    style: AppText.note,
                  ),
                ],
              ),
            ),
            if (s.closed)
              const DebtPill('已還清', color: AppColors.ok)
            else if (s.overdueDays > 0)
              DebtPill('逾期 ${s.overdueDays} 天', color: debtBad),
          ],
        ),
        if (d.isBill) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              DebtKpi(money(d.flexPay), '這期大概'),
              const SizedBox(width: 6),
              DebtKpi(next == null ? '—' : mdw(next.date), '下次扣款'),
              const SizedBox(width: 6),
              DebtKpi('${s.paidCount} 期', '已經繳過'),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          DebtBar(s.percent, color: d.type.color),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '已還 ${s.percent.toStringAsFixed(0)}%・${s.paidCount}'
                '${d.flexible ? '' : ' / ${s.totalCount}'} 期',
                style: AppText.note,
              ),
              const Spacer(),
              Text('剩 ', style: AppText.note),
              Text(
                money(s.remaining),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              DebtKpi(money(s.monthly), d.flexible ? '預計每月' : '每月'),
              const SizedBox(width: 6),
              DebtKpi(
                s.payoffDate == null ? '—' : ym(s.payoffDate!),
                s.closed ? '還清於' : '預計還清',
              ),
              const SizedBox(width: 6),
              DebtKpi(money(s.interestLeft), '還要付利息'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SegmentedButton<DebtDetailView>(
          segments: [
            if (!d.isBill)
              const ButtonSegment(
                value: DebtDetailView.schedule,
                label: Text('攤還表'),
              ),
            const ButtonSegment(
              value: DebtDetailView.records,
              label: Text('紀錄'),
            ),
            if (!d.isBill)
              const ButtonSegment(
                value: DebtDetailView.prepay,
                label: Text('提前還'),
              ),
            const ButtonSegment(value: DebtDetailView.info, label: Text('資料')),
          ],
          selected: {_view},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        const SizedBox(height: 10),
        ...switch (_view) {
          DebtDetailView.schedule => _schedule(s),
          DebtDetailView.records => _records(s),
          DebtDetailView.prepay => _prepay(s),
          DebtDetailView.info => _info(s),
        },
      ],
    );
  }

  List<Widget> _schedule(DebtStats s) {
    const head = TextStyle(fontSize: 10.5, color: AppColors.ink3);
    Widget cell(
      String t, {
      TextStyle? style,
      int flex = 3,
      bool left = false,
    }) => Expanded(
      flex: flex,
      child: Text(
        t,
        textAlign: left ? TextAlign.left : TextAlign.right,
        style: style,
      ),
    );
    return [
      Text(
        s.debt.flexible
            ? '自由還款：照每月 ${money(s.debt.flexPay)} 推算，有還就記'
            : '本息平均攤還：每期金額固定，前期利息多、後期本金多',
        style: AppText.note,
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          cell('期', style: head, flex: 2, left: true),
          cell('日期', style: head, flex: 3),
          cell('本金', style: head),
          cell('利息', style: head),
          cell('剩餘', style: head, flex: 4),
        ],
      ),
      for (final r in s.rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: s.next?.k == r.k ? debtAccent.withValues(alpha: 0.12) : null,
            border: const Border(top: BorderSide(color: Color(0xFF2A2A3D))),
          ),
          child: Builder(
            builder: (_) {
              final st = TextStyle(
                fontSize: 11.5,
                color: r.isPaid ? AppColors.ink3 : AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
              return Row(
                children: [
                  cell(
                    '${r.isPaid ? '✓ ' : ''}${r.k}',
                    style: st,
                    flex: 2,
                    left: true,
                  ),
                  cell(ym(r.date), style: st, flex: 3),
                  cell(fmtInt(r.principal), style: st),
                  cell(fmtInt(r.interest), style: st),
                  cell(fmtInt(r.balance), style: st, flex: 4),
                ],
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _records(DebtStats s) {
    final d = s.debt;
    final paid = s.paid.reversed.toList();
    return [
      if (d.payoffAt != null)
        _recordRow(
          '${ymd(d.payoffAt!)}・提前清償',
          money(d.payoffAmount ?? 0),
          canCancel: true,
        ),
      for (var i = 0; i < paid.length; i++)
        _recordRow(
          '${ymd(paid[i].payment!.date)}'
          '${d.flexible ? '' : '・第 ${paid[i].k} 期'}',
          money(paid[i].payment!.amount),
          canCancel: i == 0 && d.payoffAt == null,
        ),
      if (paid.isEmpty && d.payoffAt == null)
        Text('還沒有還款紀錄', style: AppText.bodyDim),
      const SizedBox(height: 8),
      Text(
        '紀錄一筆都不刪，最新的那筆可以取消（按錯時用）',
        style: AppText.note.copyWith(color: AppColors.ink3),
      ),
    ];
  }

  Widget _recordRow(String left, String amount, {required bool canCancel}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
        ),
        child: Row(
          children: [
            Expanded(child: Text(left, style: AppText.bodyDim)),
            Text(
              amount,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ok,
              ),
            ),
            if (canCancel)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, DebtAction.cancelLatest),
                child: const Text('取消'),
              ),
          ],
        ),
      );

  List<Widget> _prepay(DebtStats s) {
    if (s.closed) return [Text('已經還清了', style: AppText.bodyDim)];
    final extra = double.tryParse(_extra.text) ?? 0;
    final lump = double.tryParse(_lump.text) ?? 0;
    final r = simulatePrepay(s, extra: extra, lump: lump);
    return [
      _label('每月多還'),
      TextField(
        controller: _extra,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _input('0', suffix: '元 / 月'),
      ),
      _label('或現在一次多還'),
      TextField(
        controller: _lump,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _input('0', suffix: '元'),
      ),
      _calc(
        r == null
            ? [const TextSpan(text: '金額不夠付利息')]
            : [
                const TextSpan(text: '照原本：'),
                _b(s.payoffDate == null ? '—' : ym(s.payoffDate!)),
                const TextSpan(text: ' 還清、還要付利息 '),
                _b(money(s.interestLeft)),
                const TextSpan(text: '\n這樣還：'),
                _b(ym(r.payoff), color: AppColors.ok),
                const TextSpan(text: ' 還清（早 '),
                _b('${r.savedMonths}', color: AppColors.ok),
                const TextSpan(text: ' 個月）・利息 '),
                _b(money(r.interest)),
                const TextSpan(text: '\n省下利息 '),
                _b(money(r.savedInterest), color: AppColors.ok, size: 15),
                if (s.debt.rate == 0)
                  const TextSpan(
                    text: '\n這筆 0 利率，提前還省不到利息，先還有利息的比較划算',
                    style: TextStyle(color: AppColors.ink3),
                  ),
              ],
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.pop(context, DebtAction.payoff),
        style: OutlinedButton.styleFrom(
          foregroundColor: debtBad,
          side: BorderSide(color: debtBad.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text('一次還清剩下的 ${money(s.remaining)}'),
      ),
    ];
  }

  List<Widget> _info(DebtStats s) {
    final d = s.debt;
    return [
      if (d.isBill) ...[
        _kv('這期帳單大概', money(d.flexPay)),
        _kv('每月扣款日', '${d.dueDay} 號'),
        _kv('從哪個月開始記', ym(dueDateOf(d, 1))),
        _kv(
          '已經繳過',
          '${s.paidCount} 期・共 ${money(s.paid.fold(0.0, (a, r) => a + r.pay))}',
        ),
        const SizedBox(height: 6),
        Text(
          '帳單金額每個月不一樣，按「編輯」改這期大概多少就好',
          style: AppText.note.copyWith(color: AppColors.ink3),
        ),
      ] else ...[
        _kv('原始本金', money(d.principal)),
        _kv('年利率', '${d.rate}%'),
        _kv('期數', d.flexible ? '不固定' : '${d.term} 期'),
        _kv('每月扣款日', '${d.dueDay} 號'),
        _kv('第一期', ym(dueDateOf(d, 1))),
        _kv('利息總額', money(s.interestTotal)),
        _kv('已付利息', money(s.interestPaid)),
        _kv('開辦費', d.fee > 0 ? money(d.fee) : '沒有'),
        _kv('總成本（利息＋開辦費）', money(s.totalCost)),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, DebtAction.edit),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: Color(0xFF2A2A3D)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('編輯'),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, DebtAction.delete),
              style: OutlinedButton.styleFrom(
                foregroundColor: debtBad,
                side: BorderSide(color: debtBad.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('刪除'),
            ),
          ),
        ],
      ),
    ];
  }
}

// ── 先還哪一筆 ────────────────────────────────────────────

Future<void> showStrategySheet(BuildContext context, List<DebtStats> active) =>
    _sheet<void>(context, _Strategy(active: active));

class _Strategy extends StatefulWidget {
  const _Strategy({required this.active});

  final List<DebtStats> active;

  @override
  State<_Strategy> createState() => _StrategyState();
}

class _StrategyState extends State<_Strategy> {
  final _extra = TextEditingController(text: '3000');
  bool _avalanche = true;

  @override
  void initState() {
    super.initState();
    _extra.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extra = double.tryParse(_extra.text) ?? 0;
    final order = _avalanche
        ? avalancheOrder(widget.active)
        : snowballOrder(widget.active);
    final top = order.firstOrNull;
    final r = top == null ? null : simulatePrepay(top, extra: extra);
    return _Frame(
      title: '多的錢先還哪一筆',
      children: [
        _label('每月可以多還'),
        TextField(
          controller: _extra,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _input('0', suffix: '元'),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('雪崩法（利率高先還）')),
            ButtonSegment(value: false, label: Text('雪球法（金額小先還）')),
          ],
          selected: {_avalanche},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _avalanche = v.first),
        ),
        if (top == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('沒有還款中的債務', style: AppText.bodyDim),
          )
        else ...[
          _calc([
            _b(_avalanche ? '最省利息。' : '最快有成就感。'),
            TextSpan(
              text: _avalanche
                  ? '多出來的錢全部先丟利率最高的那筆，其他照常繳。'
                  : '先把剩最少的那筆還掉，少一筆要繳的帳，比較撐得下去。',
            ),
            const TextSpan(text: '\n先還 '),
            _b(top.debt.name),
            const TextSpan(text: '：'),
            if (r == null)
              const TextSpan(text: '—')
            else ...[
              const TextSpan(text: '早 '),
              _b('${r.savedMonths}', color: AppColors.ok),
              const TextSpan(text: ' 個月還清、省利息 '),
              _b(money(r.savedInterest), color: AppColors.ok),
            ],
          ]),
          _label('順序'),
          for (var i = 0; i < order.length; i++)
            _kv(
              '${i + 1}. ${order[i].debt.name}',
              '${order[i].debt.rate}%・剩 ${money(order[i].remaining)}',
            ),
          const SizedBox(height: 8),
          Text(
            '0 利率的（分期、親友）放最後，提前還省不到利息',
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ],
      ],
    );
  }
}

// ── 全部還款紀錄 ──────────────────────────────────────────

Future<void> showAllRecordsSheet(BuildContext context, List<DebtStats> all) {
  final items = <({DebtStats s, DateTime date, double amount, String note})>[
    for (final s in all) ...[
      for (final r in s.paid)
        (
          s: s,
          date: r.payment!.date,
          amount: r.payment!.amount,
          note: s.debt.flexible ? '' : '・第 ${r.k} 期',
        ),
      if (s.debt.payoffAt != null)
        (
          s: s,
          date: s.debt.payoffAt!,
          amount: s.debt.payoffAmount ?? 0,
          note: '・提前清償',
        ),
    ],
  ]..sort((a, b) => b.date.compareTo(a.date));
  final children = <Widget>[];
  String? month;
  for (final x in items) {
    final m = ym(x.date);
    if (m != month) {
      month = m;
      final sum = items
          .where((y) => ym(y.date) == m)
          .fold(0.0, (s, y) => s + y.amount);
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Row(
            children: [
              Text(
                m,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2,
                ),
              ),
              const Spacer(),
              Text(money(sum), style: AppText.note),
            ],
          ),
        ),
      );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            DebtIcon(x.s.debt.type, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.s.debt.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text('${mdw(x.date)}${x.note}', style: AppText.note),
                ],
              ),
            ),
            Text(
              money(x.amount),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.ok,
              ),
            ),
          ],
        ),
      ),
    );
  }
  return _sheet<void>(
    context,
    _Frame(
      title: '還款紀錄（${items.length} 筆）',
      children: [
        if (items.isEmpty) Text('還沒有還款紀錄', style: AppText.bodyDim),
        ...children,
        const SizedBox(height: 8),
        Text('紀錄一筆都不刪', style: AppText.note.copyWith(color: AppColors.ink3)),
      ],
    ),
  );
}

// ── 對話框 ────────────────────────────────────────────────

Future<double?> showIncomeDialog(BuildContext context, double? current) =>
    showDialog<double>(
      context: context,
      builder: (_) => _IncomeDialog(current: current),
    );

class _IncomeDialog extends StatefulWidget {
  const _IncomeDialog({this.current});

  final double? current;

  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  late final _ctrl = TextEditingController(
    text: widget.current == null ? '' : '${widget.current!.round()}',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_ctrl.text);
    if (v != null && v > 0) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('每月收入'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '算每月還款佔收入幾 %，一般建議不要超過 33–40%。',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: '元'),
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

/// 還清慶祝。
Future<void> showPaidOffDialog(BuildContext context, DebtStats s) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 8),
            Text(
              '${s.debt.name} 還清了！',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '總共還了 ${money(s.debt.principal)}'
              '${s.interestPaid > 0 ? '，付了利息 ${money(s.interestPaid)}' : ''}'
              '\n之後每月少繳 ${money(s.monthly)}',
              textAlign: TextAlign.center,
              style: AppText.bodyDim,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('太好了'),
          ),
        ],
      ),
    );
