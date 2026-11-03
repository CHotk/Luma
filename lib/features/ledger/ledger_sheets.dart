import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import 'ledger_ui.dart';

/// 記帳的底部表單：開始記帳（起始日＋期初值）、新增／編輯帳戶、記一筆、
/// 交易明細、對帳、對帳結果、帳戶明細、預算、貼上匯入、起始日、別人還欠你、
/// 交易清單（🚩／分類）。
///
/// 表單本身不碰儲存：回傳使用者填好的東西或按了哪個動作，由
/// `ledger_data.dart` 的 flow 去存、去開下一張。

/// 表單裡按了某個動作（[kind]），[id] 是哪一筆交易／對帳點。
class LAction {
  const LAction(this.kind, [this.id]);

  final String kind;
  final String? id;
}

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
      maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                tooltip: '關閉',
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
      Expanded(child: Text(text, style: AppText.note)),
      if (trailing != null)
        Flexible(
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ),
    ],
  ),
);

InputDecoration _input(String hint, {String? prefix, String? suffix}) =>
    InputDecoration(
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      isDense: true,
      filled: true,
      fillColor: ledgerTileBg,
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
        borderSide: const BorderSide(color: ledgerAccent),
      ),
    );

final _digits = [FilteringTextInputFormatter.digitsOnly];

int? _int(TextEditingController c) => int.tryParse(c.text.trim());

/// 虛線框說明（文字可以有粗體）。
Widget _note(List<InlineSpan> spans, {Color? color}) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: (color ?? Colors.white).withValues(
      alpha: color == null ? 0.03 : 0.07,
    ),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: color?.withValues(alpha: 0.45) ?? const Color(0xFF2A2A3D),
    ),
  ),
  child: Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.7),
      children: spans,
    ),
  ),
);

TextSpan _b(String s, {Color color = AppColors.ink}) => TextSpan(
  text: s,
  style: TextStyle(color: color, fontWeight: FontWeight.w700),
);

Widget _kv(String k, String v, {Color? color, String? sub}) => Container(
  padding: const EdgeInsets.symmetric(vertical: 9),
  decoration: const BoxDecoration(
    border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: AppText.bodyDim.copyWith(fontSize: 13)),
            if (sub != null)
              Text(
                sub,
                style: AppText.note.copyWith(
                  fontSize: 10.5,
                  color: AppColors.ink3,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          v,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink,
            fontFeatures: lTabular,
          ),
        ),
      ),
    ],
  ),
);

Widget _box(List<Widget> children) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.03),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFF2A2A3D)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 第一列不要上框線：用負邊距蓋掉太麻煩，直接讓 _kv 的框線在容器裡。
      ...children,
    ],
  ),
);

/// 一個大選項（補記／調整／先放著）。
Widget _option(
  BuildContext context,
  String emoji,
  String title,
  String sub,
  VoidCallback onTap,
) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Material(
    color: ledgerTileBg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFF2A2A3D)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: AppText.note.copyWith(
                      fontSize: 11,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.ink3),
          ],
        ),
      ),
    ),
  ),
);

ButtonStyle get _outline => OutlinedButton.styleFrom(
  foregroundColor: AppColors.ink,
  side: const BorderSide(color: Color(0xFF2A2A3D)),
  padding: const EdgeInsets.symmetric(vertical: 12),
);

Widget _filled(String text, VoidCallback? onPressed) => FilledButton(
  onPressed: onPressed,
  style: FilledButton.styleFrom(
    backgroundColor: ledgerAccent,
    foregroundColor: const Color(0xFF08130E),
    padding: const EdgeInsets.symmetric(vertical: 14),
  ),
  child: Text(text),
);

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  return DateTime(
    d.year,
    d.month,
    d.day,
    t?.hour ?? initial.hour,
    t?.minute ?? initial.minute,
  );
}

Widget _accountChips(
  LedgerBook book,
  String? selected,
  ValueChanged<String> onPick, {
  bool Function(LedgerAccount)? only,
  String? disabled,
}) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final a in book.accounts)
      if (only == null || only(a))
        ChoiceChip(
          label: Text('${a.type.emoji} ${a.name}'),
          selected: selected == a.id,
          showCheckmark: false,
          onSelected: a.id == disabled ? null : (_) => onPick(a.id),
        ),
  ],
);

// ── 開始記帳：起始日＋期初值 ─────────────────────────────

class SetupAccount {
  const SetupAccount(this.name, this.type, this.opening, this.limit);

  final String name;
  final LedgerAccountType type;

  /// 銀行／現金是餘額；信用卡是當天的可用額度。
  final int opening;
  final int? limit;
}

Future<({DateTime start, List<SetupAccount> accounts})?> showSetupSheet(
  BuildContext context,
) => _sheet(context, const _Setup());

class _Setup extends StatefulWidget {
  const _Setup();

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final _bankName = TextEditingController(text: '中信活存');
  final _bank = TextEditingController();
  final _cardName = TextEditingController(text: '中信信用卡');
  final _limit = TextEditingController();
  final _avail = TextEditingController();
  final _cashName = TextEditingController(text: '現金');
  final _cash = TextEditingController();

  List<TextEditingController> get _all => [
    _bankName,
    _bank,
    _cardName,
    _limit,
    _avail,
    _cashName,
    _cash,
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

  List<SetupAccount>? get _draft {
    final out = <SetupAccount>[];
    if (_bankName.text.trim().isNotEmpty) {
      final v = _int(_bank);
      if (v == null) return null;
      out.add(
        SetupAccount(_bankName.text.trim(), LedgerAccountType.bank, v, null),
      );
    }
    if (_cardName.text.trim().isNotEmpty) {
      final l = _int(_limit), a = _int(_avail);
      if (l == null || l <= 0 || a == null) return null;
      out.add(
        SetupAccount(_cardName.text.trim(), LedgerAccountType.creditCard, a, l),
      );
    }
    if (_cashName.text.trim().isNotEmpty) {
      final v = _int(_cash);
      if (v == null) return null;
      out.add(
        SetupAccount(_cashName.text.trim(), LedgerAccountType.cash, v, null),
      );
    }
    return out.isEmpty ? null : out;
  }

  Widget _pair(TextEditingController name, String nameHint, Widget value) =>
      Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(controller: name, decoration: _input(nameHint)),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(flex: 6, child: value),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return _Frame(
      title: '開始記帳',
      footer: _filled(
        '開始',
        d == null
            ? null
            : () => Navigator.pop(context, (start: _start, accounts: d)),
      ),
      children: [
        _note([
          const TextSpan(text: '選一天當'),
          _b('起始日'),
          const TextSpan(text: '，填當天每個帳戶有多少，對帳從這天開始算。'),
          _b('不用補以前的紀錄'),
          const TextSpan(text: '；以前的刷卡紀錄之後可以用「貼上匯入」，只拿來看過去消費，不影響對帳。'),
        ]),
        _label('起始日'),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: _start,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (p != null && mounted) setState(() => _start = p);
          },
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: Text(lYmd(_start)),
          style: _outline,
        ),
        _label('🏦 銀行帳戶', trailing: '名稱清空＝不用這個帳戶'),
        _pair(
          _bankName,
          '名稱',
          TextField(
            controller: _bank,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('當天餘額', prefix: '\$'),
          ),
        ),
        _label('💳 信用卡'),
        TextField(controller: _cardName, decoration: _input('名稱')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _limit,
                keyboardType: TextInputType.number,
                inputFormatters: _digits,
                decoration: _input('總額度', prefix: '\$'),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: TextField(
                controller: _avail,
                keyboardType: TextInputType.number,
                inputFormatters: _digits,
                decoration: _input('當天可用額度', prefix: '\$'),
              ),
            ),
          ],
        ),
        _label('👛 現金'),
        _pair(
          _cashName,
          '名稱',
          TextField(
            controller: _cash,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('錢包有多少', prefix: '\$'),
          ),
        ),
        _note([
          const TextSpan(text: '信用卡填'),
          _b('可用額度'),
          const TextSpan(
            text:
                '（銀行 App 上的「可刷卡額度」），App 會自己算已占用＝額度 − 可用，'
                '還沒繳的帳單、分期都算在裡面。之後帳戶還可以再新增、改名。',
          ),
        ]),
      ],
    );
  }
}

// ── 新增／編輯帳戶 ────────────────────────────────────────

Future<({String name, LedgerAccountType type, int opening, int? limit})?>
showAccountFormSheet(BuildContext context, {LedgerAccount? edit}) =>
    _sheet(context, _AccountForm(edit: edit));

class _AccountForm extends StatefulWidget {
  const _AccountForm({this.edit});

  final LedgerAccount? edit;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late LedgerAccountType _type = widget.edit?.type ?? LedgerAccountType.bank;
  late final _name = TextEditingController(text: widget.edit?.name);
  final _opening = TextEditingController();
  late final _limit = TextEditingController(
    text: widget.edit?.creditLimit?.toString(),
  );

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _opening, _limit]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _limit.dispose();
    super.dispose();
  }

  bool get _card => _type == LedgerAccountType.creditCard;

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    final ok =
        _name.text.trim().isNotEmpty &&
        (edit != null || _int(_opening) != null) &&
        (!_card || (_int(_limit) ?? 0) > 0);
    return _Frame(
      title: edit == null ? '新增帳戶' : '編輯帳戶',
      footer: _filled(
        edit == null ? '新增' : '儲存',
        ok
            ? () => Navigator.pop(context, (
                name: _name.text.trim(),
                type: _type,
                opening: _int(_opening) ?? 0,
                limit: _card ? _int(_limit) : null,
              ))
            : null,
      ),
      children: [
        if (edit == null) ...[
          _label('種類'),
          Wrap(
            spacing: 6,
            children: [
              for (final t in LedgerAccountType.values)
                ChoiceChip(
                  label: Text('${t.emoji} ${t.label}'),
                  selected: _type == t,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
        ],
        _label('名稱'),
        TextField(
          controller: _name,
          decoration: _input(_card ? '例如 國泰信用卡' : '例如 郵局'),
        ),
        if (_card) ...[
          _label('總額度'),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('例如 100000', prefix: '\$'),
          ),
        ],
        if (edit == null) ...[
          _label(_card ? '現在的可用額度' : '現在有多少'),
          TextField(
            controller: _opening,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input(_card ? '看銀行 App' : '餘額', prefix: '\$'),
          ),
          _note([
            const TextSpan(text: '這個數字是這個帳戶的期初值，對帳從'),
            _b('現在'),
            const TextSpan(text: '開始算。'),
          ]),
        ],
      ],
    );
  }
}

// ── 記一筆／編輯 ─────────────────────────────────────────

/// 打開記一筆時先填好的東西（補記對帳差額、從某筆記退款／還款⋯）。
class TxPrefill {
  const TxPrefill({
    this.type = LedgerTxType.expense,
    this.amount,
    this.accountId,
    this.toAccountId,
    this.category,
    this.at,
    this.cpId,
    this.linkedId,
    this.paidFor = false,
  });

  final LedgerTxType type;
  final int? amount;
  final String? accountId;
  final String? toAccountId;
  final String? category;
  final DateTime? at;

  /// 補記哪一次對帳的差額（有的話不能換類型，時間預設在對帳之前）。
  final String? cpId;
  final String? linkedId;
  final bool paidFor;
}

Future<({LedgerTx tx, bool settleLinked})?> showTxFormSheet(
  BuildContext context,
  LedgerBook book, {
  LedgerTx? edit,
  TxPrefill prefill = const TxPrefill(),
}) => _sheet(context, _TxForm(book: book, edit: edit, prefill: prefill));

class _TxForm extends StatefulWidget {
  const _TxForm({required this.book, this.edit, required this.prefill});

  final LedgerBook book;
  final LedgerTx? edit;
  final TxPrefill prefill;

  @override
  State<_TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<_TxForm> {
  LedgerBook get book => widget.book;
  late LedgerTxType _type;
  late final TextEditingController _amount;
  late String? _account;
  late String? _to;
  late String _category;
  late final TextEditingController _merchant;
  late final TextEditingController _memo;
  late DateTime _at;
  late bool _flagged;
  late bool _pf;
  late final TextEditingController _pfAmount;
  late final TextEditingController _pfPeople;
  String? _linked;
  bool _settle = false;

  @override
  void initState() {
    super.initState();
    final e = widget.edit, p = widget.prefill;
    _type = e?.type ?? p.type;
    _amount = TextEditingController(
      text: (e?.amount ?? p.amount)?.toString() ?? '',
    );
    _account = e?.accountId ?? p.accountId;
    _to = e?.toAccountId ?? p.toAccountId;
    _category = e?.category ?? p.category ?? '';
    _merchant = TextEditingController(text: e?.merchant ?? '');
    _memo = TextEditingController(text: e?.note ?? '');
    _at = e?.occurredAt ?? p.at ?? DateTime.now();
    _flagged = e?.flagged ?? false;
    _pf = e?.paidFor != null || p.paidFor;
    _pfAmount = TextEditingController(
      text: e?.paidFor?.amount.toString() ?? '',
    );
    _pfPeople = TextEditingController(text: e?.paidFor?.people ?? '');
    _linked = e?.linkedId ?? p.linkedId;
    _applyDefaults(fillAmount: e == null && p.amount == null);
    for (final c in [_amount, _merchant, _memo, _pfAmount, _pfPeople]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _merchant, _memo, _pfAmount, _pfPeople]) {
      c.dispose();
    }
    super.dispose();
  }

  LedgerAccount? _firstOf(LedgerAccountType t) =>
      book.accounts.where((a) => a.type == t).firstOrNull;

  /// 換類型或選了連到哪一筆之後，把帳戶、分類、金額補成合理的預設。
  void _applyDefaults({bool fillAmount = false}) {
    final accounts = book.accounts;
    String? pick(bool Function(LedgerAccount) ok) =>
        accounts.where(ok).firstOrNull?.id;
    bool valid(String? id, [bool Function(LedgerAccount)? ok]) {
      final a = book.account(id);
      return a != null && (ok == null || ok(a));
    }

    switch (_type) {
      case LedgerTxType.expense:
        if (!valid(_account)) {
          _account =
              (_firstOf(LedgerAccountType.creditCard) ?? accounts.firstOrNull)
                  ?.id;
        }
        if (!ledgerExpenseCats.containsKey(_category)) _category = '餐飲';
      case LedgerTxType.income:
        if (!valid(_account, (a) => !a.isCard)) {
          _account =
              pick((a) => a.type == LedgerAccountType.bank) ??
              pick((a) => !a.isCard);
        }
        if (!ledgerIncomeCats.containsKey(_category)) _category = '薪資';
      case LedgerTxType.transfer:
        if (!valid(_account)) {
          _account =
              (_firstOf(LedgerAccountType.bank) ?? accounts.firstOrNull)?.id;
        }
        if (!valid(_to) || _to == _account) {
          _to =
              pick(
                (a) => a.type == LedgerAccountType.cash && a.id != _account,
              ) ??
              pick((a) => a.id != _account);
        }
      case LedgerTxType.refund:
        final list = book.refundable;
        if (!list.any((t) => t.id == _linked)) _linked = list.firstOrNull?.id;
        final o = book.tx(_linked);
        if (o != null) {
          _account = o.accountId;
          if (fillAmount) {
            _amount.text = '${o.amount - book.refundedOf(o.id)}';
          }
        }
      case LedgerTxType.repayment:
        final owes = book.owes;
        if (!owes.any((o) => o.tx.id == _linked)) {
          _linked = owes.firstOrNull?.tx.id;
        }
        if (!valid(_account, (a) => !a.isCard)) {
          _account =
              pick((a) => a.type == LedgerAccountType.bank) ??
              pick((a) => !a.isCard);
        }
        final o = owes.where((x) => x.tx.id == _linked).firstOrNull;
        if (o != null && fillAmount) {
          _amount.text = '${o.left}';
          _settle = true;
        }
      case LedgerTxType.adjustment:
        break;
    }
  }

  void _setType(LedgerTxType t) => setState(() {
    _type = t;
    _applyDefaults(fillAmount: true);
  });

  String? get _error {
    final amt = _int(_amount) ?? 0;
    if (amt <= 0) return '金額要填';
    if (book.account(_account) == null) return '要選帳戶';
    if (_type == LedgerTxType.transfer) {
      if (book.account(_to) == null) return '要選轉到哪個帳戶';
      if (_to == _account) return '轉出跟轉入不能是同一個帳戶';
    }
    if (_type == LedgerTxType.refund && book.tx(_linked) == null) {
      return '要選退哪一筆';
    }
    if (_type == LedgerTxType.repayment && book.tx(_linked) == null) {
      return '要選還哪一筆';
    }
    if (_type == LedgerTxType.expense && _pf) {
      final p = _int(_pfAmount) ?? 0;
      if (p <= 0) return '幫別人付多少要填';
      if (p > amt) return '幫別人付的不能超過整筆金額';
    }
    return null;
  }

  LedgerTx _build() {
    final e = widget.edit;
    final amt = _int(_amount)!;
    var merchant = _merchant.text.trim();
    if (merchant.isEmpty && _type == LedgerTxType.refund) {
      final o = book.tx(_linked);
      merchant =
          '${o?.merchant.isNotEmpty == true ? o!.merchant : o?.category ?? ''} 退款';
    }
    if (merchant.isEmpty && _type == LedgerTxType.repayment) {
      merchant = '${book.tx(_linked)?.paidFor?.people ?? ''} 還錢';
    }
    final pf = _type == LedgerTxType.expense && _pf
        ? PaidFor(
            amount: _int(_pfAmount)!,
            people: _pfPeople.text.trim().isEmpty
                ? '朋友'
                : _pfPeople.text.trim(),
            settled: e?.paidFor?.settled ?? false,
          )
        : null;
    final hasCat =
        _type == LedgerTxType.expense || _type == LedgerTxType.income;
    final linked =
        _type == LedgerTxType.refund || _type == LedgerTxType.repayment;
    if (e != null) {
      return e.copyWith(
        type: _type,
        occurredAt: _at,
        amount: amt,
        accountId: _account,
        toAccountId: () => _type == LedgerTxType.transfer ? _to : null,
        category: () => hasCat
            ? _category
            : _type == LedgerTxType.adjustment
            ? ledgerUncategorized
            : null,
        merchant: merchant,
        note: _memo.text.trim(),
        linkedId: () => linked ? _linked : null,
        flagged: _flagged,
        paidFor: () => pf,
      );
    }
    return LedgerTx(
      id: ledgerId(),
      type: _type,
      occurredAt: _at,
      amount: amt,
      accountId: _account!,
      toAccountId: _type == LedgerTxType.transfer ? _to : null,
      category: hasCat ? _category : null,
      merchant: merchant,
      note: _memo.text.trim(),
      linkedId: linked ? _linked : null,
      flagged: _flagged,
      paidFor: pf,
      cpId: widget.prefill.cpId,
    );
  }

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> on) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          color: ledgerTileBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF2A2A3D)),
          ),
          child: SwitchListTile(
            value: v,
            onChanged: on,
            dense: true,
            activeThumbColor: ledgerAccent,
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            subtitle: Text(sub, style: AppText.note.copyWith(fontSize: 10.5)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.edit, p = widget.prefill;
    final cp = p.cpId == null
        ? null
        : book.checkpoints.where((c) => c.id == p.cpId).firstOrNull;
    final err = _error;
    final amt = _int(_amount) ?? 0;
    final pfAmt = _int(_pfAmount) ?? 0;
    final t = _type;
    final children = <Widget>[
      if (e == null && p.cpId == null)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final x in [
              LedgerTxType.expense,
              LedgerTxType.income,
              LedgerTxType.transfer,
              LedgerTxType.refund,
              LedgerTxType.repayment,
            ])
              ChoiceChip(
                label: Text(x.label),
                selected: t == x,
                showCheckmark: false,
                onSelected: (_) => _setType(x),
              ),
          ],
        ),
      if (cp != null)
        _note([
          const TextSpan(text: '補記對帳差額：時間先設在 '),
          _b('${lMd(cp.at)} ${lHm(cp.at)} 對帳之前'),
          const TextSpan(text: '，選好分類、填商家就好，記完差額會自動消失。'),
        ], color: AppColors.mid),
      const SizedBox(height: 12),
      TextField(
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: _digits,
        autofocus: e == null && p.amount == null,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontFeatures: lTabular,
        ),
        decoration: _input('0', prefix: '\$ '),
      ),
    ];

    switch (t) {
      case LedgerTxType.transfer:
        children.addAll([
          _label('從哪個帳戶'),
          _accountChips(
            book,
            _account,
            (v) => setState(() {
              _account = v;
              if (_to == v) _to = null;
              _applyDefaults();
            }),
          ),
          _label('轉到'),
          _accountChips(
            book,
            _to,
            (v) => setState(() => _to = v),
            disabled: _account,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              if (_firstOf(LedgerAccountType.bank) case final bank?)
                if (_firstOf(LedgerAccountType.cash) case final cash?)
                  ActionChip(
                    label: const Text('🏧 ATM 提款'),
                    onPressed: () => setState(() {
                      _account = bank.id;
                      _to = cash.id;
                      if (_merchant.text.isEmpty) _merchant.text = 'ATM提款';
                    }),
                  ),
              if (_firstOf(LedgerAccountType.bank) case final bank?)
                if (_firstOf(LedgerAccountType.creditCard) case final card?)
                  ActionChip(
                    label: const Text('💳 繳卡費'),
                    onPressed: () => setState(() {
                      _account = bank.id;
                      _to = card.id;
                      if (_merchant.text.isEmpty) _merchant.text = '繳卡費';
                    }),
                  ),
            ],
          ),
          _note([
            const TextSpan(text: '轉帳只是把錢換個地方放，'),
            _b('不算支出'),
            const TextSpan(text: '。繳卡費也是：刷卡那時已經算過一次了，再算會重複。'),
          ]),
        ]);
      case LedgerTxType.refund:
        final list = book.refundable;
        children.addAll(
          list.isEmpty && e == null
              ? [
                  _note([const TextSpan(text: '沒有可以退款的支出')]),
                ]
              : [
                  _label('退哪一筆'),
                  DropdownButtonFormField<String>(
                    initialValue: _linked,
                    isExpanded: true,
                    decoration: _input(''),
                    items: [
                      for (final x in {
                        ...list,
                        if (book.tx(_linked) case final l?) l,
                      })
                        DropdownMenuItem(
                          value: x.id,
                          child: Text(
                            '${lMd(x.occurredAt)} ${x.merchant.isEmpty ? x.category : x.merchant} ${lMoney(x.amount)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _linked = v;
                      _applyDefaults(fillAmount: true);
                    }),
                  ),
                  _label('退回哪個帳戶'),
                  _accountChips(
                    book,
                    _account,
                    (v) => setState(() => _account = v),
                  ),
                  _note([
                    const TextSpan(text: '退款會從原本那筆的分類扣回來；退回信用卡的話，已占用額度也會跟著回復。'),
                  ]),
                ],
        );
      case LedgerTxType.repayment:
        final owes = book.owes;
        final current = book.tx(_linked);
        children.addAll(
          owes.isEmpty && current == null
              ? [
                  _note([const TextSpan(text: '目前沒有人欠你錢 🎉')]),
                ]
              : [
                  _label('還的是哪一筆幫付'),
                  DropdownButtonFormField<String>(
                    initialValue: _linked,
                    isExpanded: true,
                    decoration: _input(''),
                    items: [
                      for (final o in owes)
                        DropdownMenuItem(
                          value: o.tx.id,
                          child: Text(
                            '${lMd(o.tx.occurredAt)} ${o.tx.merchant}・${o.tx.paidFor!.people} 還欠 ${lMoney(o.left)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (current != null &&
                          !owes.any((o) => o.tx.id == current.id))
                        DropdownMenuItem(
                          value: current.id,
                          child: Text(
                            '${lMd(current.occurredAt)} ${current.merchant}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _linked = v;
                      _applyDefaults(fillAmount: true);
                    }),
                  ),
                  _label('錢進哪個帳戶'),
                  _accountChips(
                    book,
                    _account,
                    (v) => setState(() => _account = v),
                    only: (a) => !a.isCard,
                  ),
                  if (e == null)
                    _toggle(
                      '這次還完就標記已還清',
                      '打開的話「別人還欠你」就不再算這筆',
                      _settle,
                      (v) => setState(() => _settle = v),
                    ),
                  _note([
                    const TextSpan(text: '別人還你錢'),
                    _b('不算收入'),
                    const TextSpan(text: '：那是你的錢回來，不是賺的。帳戶照算，對帳才會平。'),
                  ]),
                ],
        );
      case LedgerTxType.adjustment:
        children.add(
          _note([
            TextSpan(text: '對帳調整：${book.accountName(_account)}，算在「未分類」。'),
          ]),
        );
      case LedgerTxType.expense:
      case LedgerTxType.income:
        final cats = t == LedgerTxType.income
            ? ledgerIncomeCats
            : ledgerExpenseCats;
        children.addAll([
          _label(t == LedgerTxType.income ? '進哪個帳戶' : '用哪個付'),
          _accountChips(
            book,
            _account,
            (v) => setState(() => _account = v),
            only: t == LedgerTxType.income ? (a) => !a.isCard : null,
          ),
          _label('分類'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cats.entries)
                ChoiceChip(
                  label: Text('${c.value.$1} ${c.key}'),
                  selected: _category == c.key,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _category = c.key),
                ),
            ],
          ),
        ]);
    }

    if (t != LedgerTxType.adjustment) {
      children.addAll([
        _label(
          t == LedgerTxType.income
              ? '來源'
              : t == LedgerTxType.transfer
              ? '名稱'
              : '商家／名稱',
          trailing: '選填',
        ),
        TextField(
          controller: _merchant,
          decoration: _input(
            t == LedgerTxType.income ? '例如 公司薪水' : '例如 foodpanda',
          ),
        ),
      ]);
    }
    children.addAll([
      _label('時間'),
      OutlinedButton.icon(
        onPressed: () async {
          final v = await _pickDateTime(context, _at);
          if (v != null && mounted) setState(() => _at = v);
        },
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Text('${lYmd(_at)} ${lHm(_at)}'),
        style: _outline,
      ),
      _label('備註', trailing: '選填'),
      TextField(controller: _memo, decoration: _input('要注意的原因也可以寫這裡')),
      _toggle(
        '🚩 標記要注意',
        '單純標註，不影響任何計算；列表上會有小旗子',
        _flagged,
        (v) => setState(() => _flagged = v),
      ),
    ]);
    if (t == LedgerTxType.expense) {
      children.add(
        _toggle(
          '🤝 有幫別人付',
          '例如聚餐先幫朋友一起刷，之後他再還你',
          _pf,
          (v) => setState(() => _pf = v),
        ),
      );
      if (_pf) {
        children.addAll([
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('幫別人付多少'),
                    TextField(
                      controller: _pfAmount,
                      keyboardType: TextInputType.number,
                      inputFormatters: _digits,
                      decoration: _input('600', prefix: '\$'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('幫誰付'),
                    TextField(
                      controller: _pfPeople,
                      decoration: _input('阿明、小華'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _note(
            amt > 0 && pfAmt > 0 && pfAmt <= amt
                ? [
                    TextSpan(text: '帳戶照整筆 ${lMoney(amt)} 算（對帳才準）；本月消費只算你自己的 '),
                    _b(lMoney(amt - pfAmt)),
                    const TextSpan(text: '。之後對方還錢記「別人還錢」，不算收入。'),
                  ]
                : [const TextSpan(text: '帳戶照整筆算（對帳才準）；本月消費只算你自己的那份。')],
            color: ledgerPaidFor,
          ),
        ]);
      }
    }

    return _Frame(
      title: e != null
          ? '編輯${t.label}'
          : p.cpId != null
          ? '補記一筆'
          : '記一筆',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null && amt > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                err,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: ledgerBad),
              ),
            ),
          _filled(
            e == null ? '記下來' : '儲存',
            err == null
                ? () => Navigator.pop(context, (
                    tx: _build(),
                    settleLinked: _type == LedgerTxType.repayment && _settle,
                  ))
                : null,
          ),
        ],
      ),
      children: children,
    );
  }
}

// ── 交易明細 ─────────────────────────────────────────────

/// 動作：flag／edit／refund／delete／repay／settle／unsettle／open（看另一筆）。
Future<LAction?> showTxDetailSheet(
  BuildContext context,
  LedgerBook book,
  LedgerTx t,
) => _sheet(context, _TxDetail(book: book, tx: t));

class _TxDetail extends StatelessWidget {
  const _TxDetail({required this.book, required this.tx});

  final LedgerBook book;
  final LedgerTx tx;

  @override
  Widget build(BuildContext context) {
    final t = tx;
    final (emoji, color) = txLook(t);
    final effects = [
      for (final a in book.accounts)
        if (LedgerBook.delta(t, a) case final d when d != 0)
          a.isCard
              ? '${a.name}已占用 ${d > 0 ? '+' : '−'}${lInt(d.abs())}'
              : '${a.name} ${d > 0 ? '+' : '−'}${lInt(d.abs())}',
    ].join('\n');
    final counts = switch (t.type) {
      LedgerTxType.expense => '算進本月消費 ${lMoney(t.ownSpend)}（${t.category}）',
      LedgerTxType.income => '算進本月收入',
      LedgerTxType.transfer => '不算支出，只是換個地方放',
      LedgerTxType.refund =>
        '從「${book.tx(t.linkedId)?.category ?? ledgerUncategorized}」扣回 ${lMoney(t.amount)}',
      LedgerTxType.repayment => '不算收入（你的錢回來）',
      LedgerTxType.adjustment => t.isAdjustOut ? '算進本月消費（未分類）' : '對帳多出來的錢，不算收入',
    };
    final sign = t.isOut
        ? '−'
        : t.type == LedgerTxType.transfer
        ? ''
        : '+';
    final pf = t.paidFor;
    final linked = book.linkedTo(t.id);
    final origin = book.tx(t.linkedId);
    final cp = t.cpId == null
        ? null
        : book.checkpoints.where((c) => c.id == t.cpId).firstOrNull;
    void pop(String kind, [String? id]) =>
        Navigator.pop(context, LAction(kind, id ?? t.id));

    return _Frame(
      title: '${t.type.label}明細',
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => pop('flag'),
              style: _outline,
              child: Text(t.flagged ? '取消🚩' : '🚩 標記'),
            ),
          ),
          if (t.type == LedgerTxType.expense) ...[
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => pop('refund'),
                style: _outline,
                child: const Text('退款'),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              onPressed: () => pop('edit'),
              style: _outline,
              child: const Text('編輯'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FilledButton(
              onPressed: () => pop('delete'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5484D),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('刪除'),
            ),
          ),
        ],
      ),
      children: [
        Center(child: LedgerIcon(emoji, color, size: 52)),
        const SizedBox(height: 8),
        Text(
          '$sign${lMoney(t.amount)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            fontFeatures: lTabular,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            LedgerPill(t.type.label, color: ledgerAccent),
            if (t.flagged) const LedgerPill('🚩 要注意', color: ledgerBad),
          ],
        ),
        _box([
          _kv('時間', '${lYmd(t.occurredAt)} ${lHm(t.occurredAt)}'),
          _kv(
            '帳戶',
            t.type == LedgerTxType.transfer
                ? '${book.accountName(t.accountId)} → ${book.accountName(t.toAccountId)}'
                : book.accountName(t.accountId),
          ),
          if (t.category != null && t.type != LedgerTxType.transfer)
            _kv('分類', t.category!),
          _kv('名稱', t.merchant.isEmpty ? '—' : t.merchant),
          if (t.note.isNotEmpty) _kv('備註', t.note),
          _kv('帳戶變化', effects.isEmpty ? '—' : effects),
          _kv('怎麼算', counts),
          _kv('來源', switch (t.source) {
            'paste' => '貼上匯入',
            'adjust' => '對帳產生',
            _ => '手動記',
          }),
          if (t.raw != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  t.raw!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.ink2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ]),
        if (pf != null) ...[
          ledgerSection('🤝 幫別人付'),
          _box([
            _kv('幫 ${pf.people} 付', lMoney(pf.amount)),
            _kv('已經還', lMoney(book.repaidOf(t.id)), color: AppColors.ok),
            _kv(
              '還欠',
              pf.settled ? '已還清' : lMoney(pf.amount - book.repaidOf(t.id)),
              color: pf.settled ? AppColors.ok : null,
            ),
            _kv('算進你的消費', lMoney(t.ownSpend)),
          ]),
          const SizedBox(height: 8),
          if (pf.settled)
            OutlinedButton(
              onPressed: () => pop('unsettle'),
              style: _outline,
              child: const Text('改回還沒還清'),
            )
          else
            Row(
              children: [
                Expanded(child: _filled('記一筆還款', () => pop('repay'))),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pop('settle'),
                    style: _outline,
                    child: const Text('標記已還清'),
                  ),
                ),
              ],
            ),
        ],
        if (origin != null) ...[
          ledgerSection(t.type == LedgerTxType.refund ? '退的是' : '還的是'),
          TxTile(
            book: book,
            tx: origin,
            showDate: true,
            onTap: () => pop('open', origin.id),
          ),
        ],
        if (linked.isNotEmpty) ...[
          ledgerSection('連到這筆的'),
          for (final x in linked)
            TxTile(
              book: book,
              tx: x,
              showDate: true,
              onTap: () => pop('open', x.id),
            ),
        ],
        if (cp != null)
          _note([
            TextSpan(
              text: '這筆是 ${lMd(cp.at)} ${book.accountName(cp.accountId)}對帳時補的。',
            ),
          ], color: AppColors.mid),
      ],
    );
  }
}

// ── 對帳 ─────────────────────────────────────────────────

/// 輸入實際值，回傳要存的對帳點。[step]＝一次對帳的第幾個／共幾個。
Future<LedgerCheckpoint?> showReconSheet(
  BuildContext context,
  LedgerBook book,
  LedgerAccount account, {
  (int, int)? step,
}) => _sheet(context, _Recon(book: book, account: account, step: step));

class _Recon extends StatefulWidget {
  const _Recon({required this.book, required this.account, this.step});

  final LedgerBook book;
  final LedgerAccount account;
  final (int, int)? step;

  @override
  State<_Recon> createState() => _ReconState();
}

class _ReconState extends State<_Recon> {
  late final AccountState _s = widget.book.stateOf(widget.account)!;
  final _value = TextEditingController();
  late final _limit = TextEditingController(text: '${_s.limit}');

  @override
  void initState() {
    super.initState();
    _value.addListener(() => setState(() {}));
    _limit.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _value.dispose();
    _limit.dispose();
    super.dispose();
  }

  bool get _card => widget.account.isCard;

  int? get _actual {
    final v = _int(_value);
    if (v == null) return null;
    if (!_card) return v;
    final l = _int(_limit);
    return l == null ? null : l - v;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account, s = _s, book = widget.book;
    final since = book.txs
        .where((t) => t.occurredAt.isAfter(s.last.at))
        .map((t) => LedgerBook.delta(t, a))
        .where((d) => d != 0)
        .toList();
    final plus = since.where((d) => d > 0).fold(0, (x, d) => x + d);
    final minus = since.where((d) => d < 0).fold(0, (x, d) => x - d);
    final actual = _actual;
    final miss = actual == null ? null : LedgerBook.missOf(a, actual, s.now);
    final step = widget.step;
    return _Frame(
      title: '對帳：${a.name}',
      footer: _filled(
        '確認對帳',
        actual == null
            ? null
            : () => Navigator.pop(
                context,
                LedgerCheckpoint(
                  id: ledgerId(),
                  accountId: a.id,
                  at: DateTime.now(),
                  balance: _card ? null : _int(_value),
                  creditLimit: _card ? _int(_limit) : null,
                  available: _card ? _int(_value) : null,
                ),
              ),
      ),
      children: [
        if (step != null) ...[
          Row(
            children: [
              for (var i = 1; i <= step.$2; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= step.$1
                          ? ledgerAccent
                          : const Color(0xFF26263A),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('一次對帳 ${step.$1}／${step.$2}', style: AppText.note),
        ],
        _note([
          if (_card) ...[
            const TextSpan(text: '打開銀行 App 看'),
            _b('「可刷卡額度」'),
            const TextSpan(text: '（刷完會馬上變），填進來就好，不用看帳單。'),
          ] else if (a.type == LedgerAccountType.cash) ...[
            const TextSpan(text: '數一下錢包裡'),
            _b('現在'),
            const TextSpan(text: '有多少。'),
          ] else ...[
            const TextSpan(text: '打開網銀，看'),
            _b('現在'),
            const TextSpan(text: '的實際餘額。'),
          ],
        ]),
        _box([
          _kv(
            '上次確認',
            lMoney(LedgerBook.checkpointValue(a, s.last)),
            sub: s.checked
                ? '${lMd(s.last.at)} ${lHm(s.last.at)}'
                : '起始日 ${lYmd(s.last.at)}',
          ),
          _kv(
            '之後記到的（${since.length} 筆）',
            _card
                ? '+${lInt(plus)} 刷卡／−${lInt(minus)} 繳款退款'
                : '+${lInt(plus)}／−${lInt(minus)}',
          ),
          _kv(_card ? 'App 推算已占用' : 'App 推算現在', lMoney(s.now)),
        ]),
        if (_card)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('總額度'),
                    TextField(
                      controller: _limit,
                      keyboardType: TextInputType.number,
                      inputFormatters: _digits,
                      decoration: _input('', prefix: '\$'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('現在可用額度'),
                    TextField(
                      controller: _value,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: _digits,
                      decoration: _input('看銀行 App', prefix: '\$'),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _label(a.type == LedgerAccountType.cash ? '錢包實際有多少' : '實際餘額'),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('輸入數字', prefix: '\$'),
          ),
        ],
        if (actual == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '填完馬上算出差額',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
          )
        else
          _box([
            if (_card)
              _kv('實際已占用＝額度 − 可用', lMoney(actual))
            else
              _kv('實際', lMoney(actual)),
            _kv('App 推算', lMoney(s.now)),
            _kv(
              '這次差額',
              miss == 0
                  ? '✓ 對上了'
                  : '${miss! > 0 ? '少了' : '多了'} ${lMoney(miss.abs())}',
              color: miss == 0 ? AppColors.ok : AppColors.mid,
            ),
            if (s.miss != 0)
              _kv(
                '加上之前沒處理的',
                s.miss + miss! == 0
                    ? '✓ 剛好抵掉'
                    : '總差 ${lMoney((s.miss + miss).abs())}',
                color: s.miss + miss == 0 ? AppColors.ok : AppColors.mid,
              ),
          ]),
        if (s.miss != 0)
          _note([
            TextSpan(text: '之前 ${lMd(s.last.at)} 對帳還有 '),
            _b(lMoney(s.miss.abs())),
            const TextSpan(text: ' 沒處理，這次會一起算進總差額。'),
          ], color: AppColors.mid),
        if (_card && (miss ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '占用比算的多：可能有刷卡沒記，或是預授權（飯店、加油站）先占了額度。',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
          ),
      ],
    );
  }
}

/// 對帳結果：對上了，或差多少＋怎麼處理。動作：fixAdd／fixAdjust／leave／
/// next／done。
Future<LAction?> showReconResultSheet(
  BuildContext context,
  LedgerBook book,
  LedgerAccount account, {
  int? thisMiss,
  LedgerAccount? next,
}) => _sheet(
  context,
  _ReconResult(book: book, account: account, thisMiss: thisMiss, next: next),
);

class _ReconResult extends StatelessWidget {
  const _ReconResult({
    required this.book,
    required this.account,
    this.thisMiss,
    this.next,
  });

  final LedgerBook book;
  final LedgerAccount account;
  final int? thisMiss;
  final LedgerAccount? next;

  @override
  Widget build(BuildContext context) {
    final s = book.stateOf(account)!;
    void pop(String k) => Navigator.pop(context, LAction(k, account.id));
    return _Frame(
      title: '對帳結果：${account.name}',
      footer: next != null
          ? _filled('下一個：${next!.name} ›', () => pop('next'))
          : OutlinedButton(
              onPressed: () => pop('done'),
              style: _outline,
              child: const Text('完成'),
            ),
      children: [
        _resultBanner(s, thisMiss: thisMiss),
        if (s.miss != 0) ...[
          const SizedBox(height: 10),
          Text('要怎麼處理？', style: AppText.note),
          const SizedBox(height: 8),
          ...fixOptions(context, s, (k) => pop(k)),
        ],
      ],
    );
  }
}

Widget _resultBanner(AccountState s, {int? thisMiss}) {
  final ok = s.miss == 0;
  final a = s.account;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: (ok ? AppColors.ok : AppColors.mid).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (ok ? AppColors.ok : AppColors.mid).withValues(alpha: 0.35),
      ),
    ),
    child: Column(
      children: [
        Text(ok ? '✅' : '⚠️', style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 2),
        Text(
          ok ? '對上了！' : '總共差 ${lMoney(s.miss.abs())}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ok
              ? '${a.name}從起始日到現在都沒有漏記'
              : '${thisMiss != null && thisMiss != 0 ? '這次差 ${lMoney(thisMiss.abs())}・' : ''}'
                    '${s.miss > 0 ? (a.isCard ? '實際占用比 App 算的多，可能有刷卡沒記到' : '實際比 App 算的少，可能有支出沒記到') : '實際比 App 算的多，可能有收入或退款沒記到'}',
          textAlign: TextAlign.center,
          style: AppText.note,
        ),
      ],
    ),
  );
}

/// 差額的三種處理（帳戶明細、對帳結果共用）。
List<Widget> fixOptions(
  BuildContext context,
  AccountState s,
  void Function(String kind) onPick,
) {
  final m = s.miss.abs();
  final a = s.account;
  return [
    _option(
      context,
      '✏️',
      '補記一筆',
      '知道是哪一筆就補上，時間會設在對帳之前，記完差額自動消失',
      () => onPick('fixAdd'),
    ),
    _option(
      context,
      '⚖️',
      s.miss > 0 ? '直接調成一筆未分類支出 ${lMoney(m)}' : '直接調成一筆未分類 +${lMoney(m)}',
      a.type == LedgerAccountType.cash
          ? '現金最容易漏，想不起來就調掉，不用為一杯飲料想破頭'
          : '想不起來是什麼就直接調掉，之後在明細看得到這筆調整',
      () => onPick('fixAdjust'),
    ),
    if (a.isCard)
      _option(
        context,
        '⏳',
        '先放著（可能是預授權）',
        '飯店、加油、租車會先占額度；等真的請款再記實際金額，差額會自己消失',
        () => onPick('leave'),
      ),
  ];
}

// ── 帳戶明細 ─────────────────────────────────────────────

/// 動作：recon／fixAdd／fixAdjust／leave／edit／delete／open（交易 id）／
/// deleteCp（對帳點 id）。
Future<LAction?> showAccountSheet(
  BuildContext context,
  LedgerBook book,
  LedgerAccount account,
) => _sheet(context, _AccountDetail(book: book, account: account));

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({required this.book, required this.account});

  final LedgerBook book;
  final LedgerAccount account;

  @override
  Widget build(BuildContext context) {
    final a = account, s = book.stateOf(a)!;
    void pop(String k, [String? id]) =>
        Navigator.pop(context, LAction(k, id ?? a.id));
    final cps = book.checkpointsOf(a.id).reversed.toList();
    final txs = book.txs
        .where((t) => t.accountId == a.id || t.toAccountId == a.id)
        .take(15)
        .toList();
    return _Frame(
      title: a.name,
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => pop('edit'),
              style: _outline,
              child: const Text('改名稱'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => pop('delete'),
              style: _outline.copyWith(
                foregroundColor: const WidgetStatePropertyAll(ledgerBad),
              ),
              child: const Text('刪除帳戶'),
            ),
          ),
        ],
      ),
      children: [
        Row(
          children: [
            LedgerIcon(a.type.emoji, accountColor(a.type)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                a.type.label,
                style: AppText.note.copyWith(color: AppColors.ink3),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(a.isCard ? 'App 推算已占用' : 'App 推算餘額', style: AppText.note),
                Text(
                  lMoney(s.now),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontFeatures: lTabular,
                  ),
                ),
                if (a.isCard)
                  Text(
                    '可用 ${lMoney(s.available)} / 額度 ${lMoney(s.limit)}',
                    style: AppText.note.copyWith(color: AppColors.ink3),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.checked || s.miss != 0) _resultBanner(s),
        if (s.miss != 0) ...[
          const SizedBox(height: 10),
          ...fixOptions(context, s, (k) => pop(k)),
        ],
        const SizedBox(height: 8),
        _filled('⚖️ 現在對帳', () => pop('recon')),
        ledgerSection('對帳紀錄'),
        _box([
          for (final c in cps)
            Builder(
              builder: (context) {
                final d = book.checkpointDiff(a, c);
                final fixes = book.txs.where((t) => t.cpId == c.id).toList();
                final start = d == null;
                return InkWell(
                  onLongPress: start ? null : () => pop('deleteCp', c.id),
                  child: _kv(
                    start ? '📅 起始日期初' : '⚖️ ${lMd(c.at)} ${lHm(c.at)}',
                    '${lMoney(LedgerBook.checkpointValue(a, c))}\n'
                    '${start
                        ? '起點'
                        : d.miss == 0
                        ? '✓ 對上'
                        : '當時差 ${lMoney(d.miss.abs())}'}',
                    color: start || d.miss == 0 ? null : AppColors.mid,
                    sub:
                        '${a.isCard
                            ? '額度 ${lInt(c.creditLimit ?? 0)} − 可用 ${lInt(c.available ?? 0)}'
                            : start
                            ? lYmd(c.at)
                            : '實際餘額'}'
                        '${fixes.isEmpty ? '' : '・已${fixes.first.type == LedgerTxType.adjustment ? '調整' : '補記'} ${lMoney(fixes.fold(0, (x, t) => x + t.amount))}'}',
                  ),
                );
              },
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '對帳輸入錯了：長按那一列可以刪掉（起始日那筆要到「起始日與期初值」改）。',
            style: AppText.note.copyWith(fontSize: 10.5, color: AppColors.ink3),
          ),
        ),
        ledgerSection('最近的交易'),
        if (txs.isEmpty)
          Text('還沒有交易', style: AppText.bodyDim)
        else
          for (final t in txs)
            TxTile(
              book: book,
              tx: t,
              showDate: true,
              onTap: () => pop('open', t.id),
            ),
      ],
    );
  }
}

// ── 預算 ─────────────────────────────────────────────────

Future<({int total, Map<String, int> byCategory})?> showBudgetSheet(
  BuildContext context,
  LedgerBook book,
  int year,
  int month,
) => _sheet(context, _Budget(book: book, year: year, month: month));

class _Budget extends StatefulWidget {
  const _Budget({required this.book, required this.year, required this.month});

  final LedgerBook book;
  final int year;
  final int month;

  @override
  State<_Budget> createState() => _BudgetState();
}

class _BudgetState extends State<_Budget> {
  late final MonthBudget _b = widget.book.budgetOf(widget.year, widget.month);
  late final _total = TextEditingController(
    text: _b.total > 0 ? '${_b.total}' : '',
  );
  late final _cats = {
    for (final c in ledgerExpenseCats.keys)
      if (c != ledgerUncategorized)
        c: TextEditingController(text: _b.byCategory[c]?.toString() ?? ''),
  };

  @override
  void initState() {
    super.initState();
    for (final c in [_total, ..._cats.values]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_total, ..._cats.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sum = _cats.values.fold(0, (s, c) => s + (_int(c) ?? 0));
    return _Frame(
      title: '${widget.month} 月預算',
      footer: _filled(
        '儲存預算',
        () => Navigator.pop(context, (
          total: _int(_total) ?? 0,
          byCategory: {
            for (final e in _cats.entries) e.key: _int(e.value) ?? 0,
          },
        )),
      ),
      children: [
        _note([
          TextSpan(
            text: _b.carriedFrom == null
                ? '分類預算可以只填在意的幾個，沒填的分類就不限制。下個月沒設定會自動沿用這個月的。'
                : '這個月還沒設，目前沿用 ${_b.carriedFrom} 的預算；存了就變成這個月自己的。',
          ),
        ]),
        _label('整個月總預算'),
        TextField(
          controller: _total,
          keyboardType: TextInputType.number,
          inputFormatters: _digits,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          decoration: _input('例如 30000', prefix: '\$ '),
        ),
        _label('各分類（選填）', trailing: '分類加起來 ${lMoney(sum)}'),
        for (final e in _cats.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    '${ledgerExpenseCats[e.key]!.$1} ${e.key}',
                    style: AppText.body,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: e.value,
                    keyboardType: TextInputType.number,
                    inputFormatters: _digits,
                    decoration: _input('不限制', prefix: '\$'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── 貼上匯入 ─────────────────────────────────────────────

Future<List<LedgerTx>?> showImportSheet(
  BuildContext context,
  LedgerBook book,
) => _sheet(context, _Import(book: book));

class _Import extends StatefulWidget {
  const _Import({required this.book});

  final LedgerBook book;

  @override
  State<_Import> createState() => _ImportState();
}

class _ImportState extends State<_Import> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.book.parseImport(_text.text);
    final n = lines.where((l) => l.willImport).length;
    return _Frame(
      title: '貼上文字匯入',
      footer: _filled(
        n == 0 ? '沒有可以匯入的' : '匯入 $n 筆',
        n == 0
            ? null
            : () => Navigator.pop(context, [
                for (final l in lines)
                  if (l.willImport) l.tx!,
              ]),
      ),
      children: [
        _note([
          const TextSpan(text: '一行一筆：'),
          _b('銀行｜日期時間｜分類｜商家｜金額'),
          const TextSpan(text: '。刷卡記在第一張信用卡；分類是「提款」的會自動變成'),
          _b('轉帳（銀行 → 現金）'),
          const TextSpan(
            text: '、不算支出；一樣的紀錄會跳過；起始日之前的只拿來看過去消費，不影響對帳。原始那行會留在明細裡。',
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          minLines: 5,
          maxLines: 10,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: _input('中信銀行｜2026/10/22 12:05｜餐飲｜foodpanda｜NT\$295'),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            ActionChip(
              label: const Text('📋 從剪貼簿貼上'),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null && mounted) _text.text = d!.text!;
              },
            ),
            const SizedBox(width: 6),
            if (_text.text.isNotEmpty)
              ActionChip(
                label: const Text('清空'),
                onPressed: () => _text.clear(),
              ),
          ],
        ),
        ledgerSection('預覽'),
        if (lines.isEmpty)
          Text('貼上之後這裡會列出每一行會變成什麼', style: AppText.bodyDim)
        else
          for (final l in lines) _importRow(l),
      ],
    );
  }

  Widget _importRow(ImportLine l) {
    final t = l.tx;
    if (t == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
            style: AppText.note,
            children: [
              const TextSpan(
                text: '✕ ',
                style: TextStyle(color: ledgerBad),
              ),
              TextSpan(text: '${l.line}\n'),
              TextSpan(
                text: l.error,
                style: const TextStyle(color: ledgerBad),
              ),
            ],
          ),
        ),
      );
    }
    final (emoji, color) = txLook(t);
    final book = widget.book;
    return Opacity(
      opacity: l.duplicate ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            LedgerIcon(emoji, color, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.merchant}・${lMd(t.occurredAt)} ${lHm(t.occurredAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    t.type == LedgerTxType.transfer
                        ? '轉帳 ${book.accountName(t.accountId)} → ${book.accountName(t.toAccountId)}（不算支出）'
                        : '支出・${book.accountName(t.accountId)}・${t.category}'
                              '${l.unknownCategory == null ? '' : '（沒有「${l.unknownCategory}」分類，先放未分類）'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.note.copyWith(
                      fontSize: 10.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lMoney(t.amount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                l.duplicate
                    ? const LedgerPill('重複・跳過')
                    : l.beforeStart
                    ? const LedgerPill('起始日前・只看消費')
                    : const LedgerPill('會匯入', color: AppColors.ok),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 起始日與期初值 ───────────────────────────────────────

/// 回傳改好的起始日跟每個帳戶的期初對帳點。
Future<({DateTime start, List<LedgerCheckpoint> openings})?> showStartSheet(
  BuildContext context,
  LedgerBook book,
) => _sheet(context, _Start(book: book));

class _Start extends StatefulWidget {
  const _Start({required this.book});

  final LedgerBook book;

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  late DateTime _date = widget.book.startDate ?? DateTime.now();
  late final List<(LedgerAccount, LedgerCheckpoint)> _rows = [
    for (final a in widget.book.accounts)
      if (widget.book.checkpointsOf(a.id).firstOrNull case final c?) (a, c),
  ];
  late final Map<String, TextEditingController> _value = {
    for (final (a, c) in _rows)
      a.id: TextEditingController(
        text: '${a.isCard ? c.available ?? 0 : c.balance ?? 0}',
      ),
  };
  late final Map<String, TextEditingController> _limit = {
    for (final (a, c) in _rows)
      if (a.isCard)
        a.id: TextEditingController(
          text: '${c.creditLimit ?? a.creditLimit ?? 0}',
        ),
  };

  @override
  void dispose() {
    for (final c in [..._value.values, ..._limit.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime(_date.year, _date.month, _date.day);
    return _Frame(
      title: '起始日與期初值',
      footer: _filled(
        '儲存',
        () => Navigator.pop(context, (
          start: start,
          openings: [
            for (final (a, c) in _rows)
              c.copyWith(
                at: start,
                balance: a.isCard ? null : _int(_value[a.id]!) ?? 0,
                available: a.isCard ? _int(_value[a.id]!) ?? 0 : null,
                creditLimit: a.isCard ? _int(_limit[a.id]!) ?? 0 : null,
              ),
          ],
        )),
      ),
      children: [
        _note([
          const TextSpan(text: '對帳從起始日開始算。'),
          _b('不用補完以前的紀錄'),
          const TextSpan(text: '；以前的刷卡紀錄能匯入就匯入，只拿來看過去消費，不影響對帳。'),
        ]),
        _label('起始日'),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (p != null && mounted) setState(() => _date = p);
          },
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: Text(lYmd(_date)),
          style: _outline,
        ),
        for (final (a, _) in _rows) ...[
          _label(
            '${a.type.emoji} ${a.name}${a.isCard ? '（總額度／當天可用額度）' : '（當天有多少）'}',
          ),
          if (a.isCard)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _limit[a.id],
                    keyboardType: TextInputType.number,
                    inputFormatters: _digits,
                    decoration: _input('總額度', prefix: '\$'),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: TextField(
                    controller: _value[a.id],
                    keyboardType: TextInputType.number,
                    inputFormatters: _digits,
                    decoration: _input('可用額度', prefix: '\$'),
                  ),
                ),
              ],
            )
          else
            TextField(
              controller: _value[a.id],
              keyboardType: TextInputType.number,
              inputFormatters: _digits,
              decoration: _input('餘額', prefix: '\$'),
            ),
        ],
      ],
    );
  }
}

// ── 別人還欠你 ───────────────────────────────────────────

/// 動作：repay／settle／open（交易 id）／addPaidFor。
Future<LAction?> showOweSheet(BuildContext context, LedgerBook book) =>
    _sheet(context, _Owe(book: book));

class _Owe extends StatelessWidget {
  const _Owe({required this.book});

  final LedgerBook book;

  @override
  Widget build(BuildContext context) {
    final owes = book.owes;
    final done = book.txs
        .where(
          (t) =>
              t.paidFor != null &&
              (t.paidFor!.settled || book.repaidOf(t.id) >= t.paidFor!.amount),
        )
        .toList();
    void pop(String k, [String? id]) => Navigator.pop(context, LAction(k, id));
    return _Frame(
      title: '別人還欠你',
      footer: OutlinedButton(
        onPressed: () => pop('addPaidFor'),
        style: _outline,
        child: const Text('＋ 記一筆有幫別人付的支出'),
      ),
      children: [
        Center(child: Text('別人還欠你', style: AppText.note)),
        Text(
          lMoney(book.oweTotal),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: ledgerPaidFor,
            fontFeatures: lTabular,
          ),
        ),
        Center(
          child: Text(
            '${owes.length} 筆幫付還沒還清',
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ),
        const SizedBox(height: 12),
        if (owes.isEmpty)
          Center(child: Text('沒有人欠你錢 🎉', style: AppText.bodyDim)),
        for (final o in owes)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ledgerTileBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A3D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => pop('open', o.tx.id),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.tx.merchant.isEmpty
                                  ? o.tx.category ?? ''
                                  : o.tx.merchant,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              '${lMd(o.tx.occurredAt)}・幫 ${o.tx.paidFor!.people} 付 ${lMoney(o.tx.paidFor!.amount)}',
                              style: AppText.note.copyWith(
                                color: AppColors.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            lMoney(o.left),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            '已還 ${lMoney(o.repaid)}',
                            style: AppText.note.copyWith(color: AppColors.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                LedgerBar(
                  o.repaid / o.tx.paidFor!.amount,
                  color: ledgerPaidFor,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _filled('記一筆還款', () => pop('repay', o.tx.id)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pop('settle', o.tx.id),
                        style: _outline,
                        child: const Text('標記已還清'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (done.isNotEmpty) ...[
          ledgerSection('已經還清'),
          for (final t in done)
            TxTile(
              book: book,
              tx: t,
              showDate: true,
              onTap: () => pop('open', t.id),
            ),
        ],
        _note([
          const TextSpan(text: '記幫付：記支出時打開「🤝 有幫別人付」。別人還錢記成「別人還錢」，'),
          _b('不算收入'),
          const TextSpan(text: '。'),
        ]),
      ],
    );
  }
}

// ── 交易清單（🚩、某個分類） ──────────────────────────────

/// 回傳點了哪一筆（`open`），或按了底下的按鈕（`footer`）。
Future<LAction?> showTxListSheet(
  BuildContext context,
  LedgerBook book, {
  required String title,
  required List<LedgerTx> txs,
  Widget? header,
  String? footerLabel,
  String emptyText = '這裡沒有紀錄',
}) => _sheet(
  context,
  _TxList(
    book: book,
    title: title,
    txs: txs,
    header: header,
    footerLabel: footerLabel,
    emptyText: emptyText,
  ),
);

class _TxList extends StatelessWidget {
  const _TxList({
    required this.book,
    required this.title,
    required this.txs,
    this.header,
    this.footerLabel,
    required this.emptyText,
  });

  final LedgerBook book;
  final String title;
  final List<LedgerTx> txs;
  final Widget? header;
  final String? footerLabel;
  final String emptyText;

  @override
  Widget build(BuildContext context) => _Frame(
    title: title,
    footer: footerLabel == null
        ? null
        : OutlinedButton(
            onPressed: () => Navigator.pop(context, const LAction('footer')),
            style: _outline,
            child: Text(footerLabel!),
          ),
    children: [
      ?header,
      if (txs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text(emptyText, style: AppText.bodyDim)),
        )
      else
        ...groupedTxList(
          book,
          txs,
          (t) => Navigator.pop(context, LAction('open', t.id)),
        ),
    ],
  );
}

/// 給清單抽屜上方用的小卡（分類：花多少／預算）。
Widget budgetHeader(int spent, int? budget) => Container(
  margin: const EdgeInsets.only(bottom: 6),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: ledgerTileBg,
    borderRadius: BorderRadius.circular(14),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('花了', style: AppText.note),
                Text(
                  lMoney(spent),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('預算', style: AppText.note),
              Text(
                budget == null ? '不限制' : lMoney(budget),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (budget != null)
                Text(
                  spent > budget
                      ? '超支 ${lMoney(spent - budget)}'
                      : '還剩 ${lMoney(budget - spent)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: spent > budget ? ledgerBad : AppColors.ok,
                  ),
                ),
            ],
          ),
        ],
      ),
      if (budget != null) ...[
        const SizedBox(height: 8),
        LedgerBar(
          spent / budget,
          color: spent > budget ? ledgerBad : ledgerAccent,
        ),
      ],
    ],
  ),
);
