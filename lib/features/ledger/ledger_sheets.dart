import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/digits_input.dart';
import '../../shared/half_width_input.dart';
import '../../shared/widgets/date_time_wheel.dart';
import '../../shared/widgets/glass_menu.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import 'ledger_ui.dart';

/// 記帳的底部表單：開始記帳（建帳戶）、新增／編輯帳戶、記一筆、
/// 交易明細、對帳／填餘額、對帳結果、帳戶明細、預算、貼上匯入、他給了、
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

/// æ¨é¡è·è¼¸å¥æ¡åä¸è¡ï¼2026-11-06 ä½¿ç¨èï¼ä¸è¦æ¨é¡ä¸è¡ãè¼¸å¥æ¡åæä¸è¡ï¼ã
/// å·¦éåºå®å¯¬åº¦æ¾æ¨é¡ï¼[hint] æ¯ä¸é¢ä¸è¡å°å­ï¼ä¾å¦å¿å¡«ï¼ï¼å³éæ¯è¼¸å¥æ¡ã
/// 表單欄位的字：每個輸入框都一樣大（金額也不特別大）。
const _fieldStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: AppColors.ink,
  fontFeatures: lTabular,
);

/// 左邊的欄位標題：像表單的欄位名稱（深色、粗一點），不是淡淡的小註解。
const _titleStyle = TextStyle(
  fontSize: 13.5,
  fontWeight: FontWeight.w700,
  color: AppColors.ink,
);

/// 標題在左、一組選項（帳戶、分類的膠囊）在右，同一行；膠囊縮小一點才排得下。
Widget _chipRow(String label, Widget chips) => Padding(
  padding: const EdgeInsets.only(top: 12),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 88,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: _titleStyle),
        ),
      ),
      Expanded(
        child: Builder(
          builder: (c) => Theme(
            data: Theme.of(c).copyWith(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: chips,
          ),
        ),
      ),
    ],
  ),
);

Widget _row(String label, Widget field, {String? hint}) => Padding(
  padding: const EdgeInsets.only(top: 12),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _titleStyle),
            if (hint != null)
              Text(
                hint,
                style: AppText.note.copyWith(
                  fontSize: 10,
                  color: AppColors.ink3,
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: Builder(
          builder: (c) {
            final t = Theme.of(c);
            return Theme(
              data: t.copyWith(
                textTheme: t.textTheme.copyWith(
                  titleMedium: _fieldStyle,
                  bodyLarge: _fieldStyle,
                ),
              ),
              child: field,
            );
          },
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.ink3),
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

final _digits = <TextInputFormatter>[const DigitsInputFormatter()];

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

ButtonStyle get _shortcutStyle => OutlinedButton.styleFrom(
  foregroundColor: ledgerAccent,
  side: BorderSide(color: ledgerAccent.withValues(alpha: 0.6)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  visualDensity: VisualDensity.compact,
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

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) =>
    showDateTimeWheel(context, initial);

Widget _accountChips(
  LedgerBook book,
  String? selected,
  ValueChanged<String> onPick, {
  bool Function(LedgerAccount)? only,
  String? disabled,
  List<Widget> extra = const [],
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
    ...extra,
  ],
);

// ── 開始記帳：建帳戶（餘額選填） ─────────────────────────

/// 開始記帳時建的一個帳戶。[opening] 是現在的餘額（信用卡是可用額度），
/// 沒填就是 null，之後再填。
class SetupAccount {
  const SetupAccount(this.name, this.type, this.opening, this.limit);

  final String name;
  final LedgerAccountType type;
  final int? opening;
  final int? limit;
}

/// 2026-11-03 使用者：起始日不用、戶頭餘額先不用強制填、要能多幾個戶頭、
/// 信用卡只有中信。所以這裡只列帳戶名稱，餘額都選填。
Future<List<SetupAccount>?> showSetupSheet(BuildContext context) =>
    _sheet(context, const _Setup());

class _SetupRow {
  _SetupRow(this.type, String name) : name = TextEditingController(text: name);

  final LedgerAccountType type;
  final TextEditingController name;
  final value = TextEditingController();
  final limit = TextEditingController();

  List<TextEditingController> get all => [name, value, limit];
}

class _Setup extends StatefulWidget {
  const _Setup();

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final _rows = [
    _SetupRow(LedgerAccountType.bank, '中信帳戶'),
    _SetupRow(LedgerAccountType.creditCard, '中信卡'),
    _SetupRow(LedgerAccountType.cash, '現金'),
  ];

  @override
  void initState() {
    super.initState();
    for (final r in _rows) {
      _listen(r);
    }
  }

  void _listen(_SetupRow r) {
    for (final c in r.all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      for (final c in r.all) {
        c.dispose();
      }
    }
    super.dispose();
  }

  List<SetupAccount> get _draft => [
    for (final r in _rows)
      if (r.name.text.trim().isNotEmpty)
        SetupAccount(r.name.text.trim(), r.type, _int(r.value), _int(r.limit)),
  ];

  Widget _row(_SetupRow r) {
    final card = r.type == LedgerAccountType.creditCard;
    final removable =
        r.type == LedgerAccountType.bank &&
        _rows.where((x) => x.type == LedgerAccountType.bank).length > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(r.type.emoji, style: const TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: TextField(
                  controller: r.name,
                  inputFormatters: halfWidthFormatters,
                  decoration: _input('名稱'),
                ),
              ),
              if (removable)
                IconButton(
                  onPressed: () => setState(() {
                    _rows.remove(r);
                    for (final c in r.all) {
                      c.dispose();
                    }
                  }),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: AppColors.ink3,
                  tooltip: '不要這個帳戶',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: card
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: r.limit,
                          keyboardType: TextInputType.number,
                          inputFormatters: _digits,
                          decoration: _input('總額度（選填）', prefix: '\$'),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: TextField(
                          controller: r.value,
                          keyboardType: TextInputType.number,
                          inputFormatters: _digits,
                          decoration: _input('可用額度（選填）', prefix: '\$'),
                        ),
                      ),
                    ],
                  )
                : TextField(
                    controller: r.value,
                    keyboardType: TextInputType.number,
                    inputFormatters: _digits,
                    decoration: _input(
                      r.type == LedgerAccountType.cash
                          ? '錢包現在有多少（選填）'
                          : '現在餘額（選填）',
                      prefix: '\$',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return _Frame(
      title: '開始記帳',
      footer: _filled('開始', d.isEmpty ? null : () => Navigator.pop(context, d)),
      children: [
        _note([
          const TextSpan(text: '先建要用的帳戶就能開始記。'),
          _b('餘額都可以先不填'),
          const TextSpan(
            text:
                '；哪天想讓 App 幫你對帳、抓漏記，再到「帳戶」填一次現在的餘額，'
                '從那時候開始算。名稱清空＝不用這個帳戶。',
          ),
        ]),
        for (final r in _rows) _row(r),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            final r = _SetupRow(LedgerAccountType.bank, '');
            _listen(r);
            final i = _rows.lastIndexWhere(
              (x) => x.type == LedgerAccountType.bank,
            );
            _rows.insert(i + 1, r);
          }),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('再加一個銀行戶頭'),
          style: _outline,
        ),
      ],
    );
  }
}

// ── 新增／編輯帳戶 ────────────────────────────────────────

Future<({String name, LedgerAccountType type, int? opening, int? limit})?>
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

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _opening]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  bool get _card => _type == LedgerAccountType.creditCard;

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    final ok = _name.text.trim().isNotEmpty;
    return _Frame(
      title: edit == null ? '新增帳戶' : '編輯帳戶',
      footer: _filled(
        edit == null ? '新增' : '儲存',
        ok
            ? () => Navigator.pop(context, (
                name: _name.text.trim(),
                type: _type,
                opening: _int(_opening),
                limit: null,
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
          inputFormatters: halfWidthFormatters,
          decoration: _input(_card ? '例如 中信卡' : '例如 郵局'),
        ),
        if (edit == null) ...[
          _label(_card ? '現在的可刷額' : '現在有多少', trailing: '選填'),
          TextField(
            controller: _opening,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input(_card ? '看銀行 App' : '餘額', prefix: '\$'),
          ),
          _note([
            const TextSpan(text: '餘額可以先不填，之後到帳戶「填餘額」。填了才會幫你'),
            _b('對帳、抓漏記'),
            const TextSpan(text: '，從填的那時候開始算。'),
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

/// 回傳記好的交易、是否順便標記對方給了，跟選填的「這筆之後帳戶剩多少」
/// （[after]，null＝沒填或清掉）。
Future<({LedgerTx tx, bool settleLinked, int? after, int? afterTo})?>
showTxFormSheet(
  BuildContext context,
  LedgerBook book, {
  LedgerTx? edit,
  TxPrefill prefill = const TxPrefill(),
  int? initialAfter,
  void Function(LedgerTx)? onSwitchEdit,
}) => _sheet(
  context,
  _TxForm(
    book: book,
    edit: edit,
    prefill: prefill,
    initialAfter: initialAfter,
    onSwitchEdit: onSwitchEdit,
  ),
);

class _TxForm extends StatefulWidget {
  const _TxForm({
    required this.book,
    this.edit,
    required this.prefill,
    this.initialAfter,
    this.onSwitchEdit,
  });

  /// 記一筆時貼一行文字、偵測到已經記過同一筆（同帳戶、同分鐘、同金額）：不新增，
  /// 關掉這張表單，交給呼叫的人改成編輯那一筆（2026-11-10 使用者：這樣順暢一點）。
  final void Function(LedgerTx)? onSwitchEdit;

  /// 匯入預覽編輯時，原本那行的「這筆之後餘額」（還沒存、查不到對帳點）。
  final int? initialAfter;
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
  late final TextEditingController _item;
  late final TextEditingController _memo;

  /// 時間不確定時，同一天的排序數字（數字越大越前面）。
  late final TextEditingController _order;
  late DateTime _at;

  /// 時間不確定、只選到哪一天（2026-11-10 使用者）：存那天中午 12:00，畫面只顯示日期。
  bool _timeUnknown = false;

  /// 卡費改負數（2026-11-10 使用者：卡費也可能是退款或部分退款）：只有「轉到信用卡」才用得到，
  /// 存起來是信用卡 → 帳戶的轉帳（金額一樣是正的），畫面上寫「−$」。
  bool _negative = false;
  late bool _flagged;
  late bool _pf;
  bool _pfSettled = false;

  /// 拆分（2026-11-03 使用者）：一筆消費拆成多個分類，加起來要剛好等於整筆金額。
  bool _split = false;
  final _splitRows = <_SplitRow>[];

  _SplitRow _newSplitRow(
    String category,
    String amount, {
    String name = '',
    String people = '',
    bool forOther = false,
    bool settled = false,
    String other = '',
  }) {
    final r = _SplitRow(
      category,
      TextEditingController(text: amount),
      TextEditingController(text: name),
      TextEditingController(text: people),
      TextEditingController(text: other),
      forOther: forOther,
      settled: settled,
    );
    r.amount.addListener(() => setState(() {}));
    r.people.addListener(() => setState(() {}));
    r.other.addListener(() => setState(() {}));
    return r;
  }

  void _disposeRow(_SplitRow r) {
    r.amount.dispose();
    r.name.dispose();
    r.people.dispose();
    r.other.dispose();
  }

  /// 拆分模式下「幫人付」跟著各份走：有任何一份標了就算有幫人付，金額是那幾份加起來。
  bool get _pfOn => _split ? _splitRows.any((r) => r.forOther) : _pf;
  int get _pfSum => _splitRows.fold(0, (s, r) => s + _rowOther(r));

  /// 這一份裡對方要給多少：沒填＝整份，填了不能超過這一份的金額。
  int _rowOther(_SplitRow r) {
    if (!r.forOther) return 0;
    final a = _int(r.amount) ?? 0;
    final t = _int(r.other);
    return t == null ? a : t.clamp(0, a).toInt();
  }

  int get _pfValue => _split ? _pfSum : (_int(_pfAmount) ?? 0);

  /// 幫誰沒填時的預設：快選列的第一個（最近幫過的人）；從來沒幫過人才寫「朋友」
  /// （2026-11-05 使用者：不要直接給我寫「朋友」）。
  String get _defaultPerson => _pfPeopleOptions.firstOrNull ?? '';

  String _rowPeople(_SplitRow r) => r.people.text.trim().isNotEmpty
      ? r.people.text.trim()
      : (_defaultPerson.isEmpty ? '朋友' : _defaultPerson);

  /// 整筆的「幫誰」：拆分時是各份幫的人（不重複，用「、」接起來）。
  String get _pfPeopleText {
    if (!_split) {
      return _pfPeople.text.trim().isNotEmpty
          ? _pfPeople.text.trim()
          : (_defaultPerson.isEmpty ? '朋友' : _defaultPerson);
    }
    final names = <String>[];
    for (final r in _splitRows) {
      if (r.forOther && !names.contains(_rowPeople(r))) {
        names.add(_rowPeople(r));
      }
    }
    return names.join('、');
  }

  bool get _pfAllGiven => _split
      ? _splitRows.where((r) => r.forOther).every((r) => r.settled)
      : _pfSettled;

  void _toggleSplit(bool on) => setState(() {
    // 取消拆分時，各份標的「幫人付」併回整筆的「跟別人一起」。
    if (!on && _split && _splitRows.any((r) => r.forOther)) {
      _pf = true;
      _pfAmount.text = '$_pfSum';
      _pfSettled = _pfAllGiven;
      if (_pfPeople.text.trim().isEmpty) _pfPeople.text = _pfPeopleText;
    }
    _split = on;
    if (on && _splitRows.isEmpty) {
      final all = _int(_amount) ?? 0;
      _splitRows
        // 已經寫了品項名稱就帶進第一份。
        ..add(
          _newSplitRow(
            _category,
            all > 0 ? '$all' : '',
            name: _item.text.trim(),
          ),
        )
        ..add(_newSplitRow('生活', ''));
    }
  });

  int get _splitSum => _splitRows.fold(0, (s, r) => s + (_int(r.amount) ?? 0));
  late final TextEditingController _pfAmount;
  late final TextEditingController _pfPeople;

  /// 這筆之後帳戶剩多少（信用卡是可用額度），選填；有填就附一個對帳點在這筆上。
  late final TextEditingController _after;

  /// 轉帳時入帳那邊帳戶的「這筆之後餘額」（繳卡費＝信用卡的可刷餘額）。
  late final TextEditingController _afterTo;

  String? _linked;
  bool _settle = false;

  /// 轉帳但錢是轉給別人（例如請朋友幫忙買東西）：存成一筆支出（2026-11-03
  /// 使用者：應該要可以勾選算支出）。
  bool _toOther = false;

  /// 轉到「沒記在 App 裡」的自己的戶頭（目前只有 LineBank，2026-11-10 使用者）：空字串＝沒選。
  String _toExt = '';

  /// 排序數字（從 1 開始、最大 99；0 不算，沒填＝沒設定＝0，排在有時分的後面）。
  int get _orderValue =>
      (int.tryParse(_order.text.trim()) ?? 0).clamp(0, ledgerTimeOrderMax);

  /// 實際要存的類型。
  LedgerTxType get _effType =>
      _type == LedgerTxType.transfer && _toOther ? LedgerTxType.expense : _type;

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
    _toExt = e?.toName ?? '';
    _category = e?.category ?? p.category ?? '';
    _merchant = TextEditingController(text: e?.merchant ?? '');
    _item = TextEditingController(text: e?.item ?? '');
    _memo = TextEditingController(text: e?.note ?? '');
    _order = TextEditingController(
      text: (e?.timeOrder ?? 0) == 0 ? '' : '${e!.timeOrder}',
    );
    _at = e?.occurredAt ?? p.at ?? DateTime.now();
    _timeUnknown = e?.timeUnknown ?? false;
    _flagged = e?.flagged ?? false;
    _pf = e?.paidFor != null || p.paidFor;
    _pfSettled = e?.paidFor?.settled ?? false;
    if (e != null && e.isSplit) {
      _split = true;
      for (final x in e.splits) {
        _splitRows.add(
          _newSplitRow(
            x.category,
            '${x.amount}',
            name: x.name,
            // 舊的一份沒存幫誰時，用整筆的幫誰。
            people: x.people.isNotEmpty ? x.people : (e.paidFor?.people ?? ''),
            forOther: x.forOther,
            // 整筆被標「他給了」時，舊資料的每份也算已給。
            settled: x.settled || (x.forOther && (e.paidFor?.settled ?? false)),
            other: x.forOther && x.otherPart != x.amount
                ? '${x.otherPart}'
                : '',
          ),
        );
      }
    }
    _pfAmount = TextEditingController(
      text: e?.paidFor?.amount.toString() ?? '',
    );
    _pfPeople = TextEditingController(text: e?.paidFor?.people ?? '');
    // 一開始就是「跟別人一起」（例如貼上匯入）又沒寫幫誰：預設快選列的第一個。
    if (e == null && _pf && _pfPeople.text.isEmpty) {
      _pfPeople.text = _defaultPerson;
    }
    final oldCp = e == null
        ? null
        : book.checkpointOfTx(e.id, accountId: e.accountId);
    final oldCpTo = e == null || e.toAccountId == null
        ? null
        : book.checkpointOfTx(e.id, accountId: e.toAccountId);
    _afterTo = TextEditingController(
      text: (oldCpTo?.available ?? oldCpTo?.balance)?.toString() ?? '',
    );
    _after = TextEditingController(
      text:
          (oldCp == null
                  ? widget.initialAfter
                  : (oldCp.available ?? oldCp.balance))
              ?.toString() ??
          '',
    );
    // 編輯一筆「卡費退回」（信用卡 → 帳戶）：表單還是照「帳戶 → 信用卡」填，打開負數。
    if (e != null && book.isCardReturn(e)) {
      _negative = true;
      _account = e.toAccountId;
      _to = e.accountId;
      final a = _after.text;
      _after.text = _afterTo.text;
      _afterTo.text = a;
    }
    _linked = e?.linkedId ?? p.linkedId;
    _applyDefaults(fillAmount: e == null && p.amount == null);
    for (final c in [
      _amount,
      _merchant,
      _item,
      _memo,
      _order,
      _pfAmount,
      _pfPeople,
      _after,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _amount,
      _merchant,
      _item,
      _memo,
      _order,
      _pfAmount,
      _pfPeople,
      _after,
    ]) {
      c.dispose();
    }
    _paste.dispose();
    _fixedName.dispose();
    _splitRows.forEach(_disposeRow);
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
        if (_toExt.isEmpty && !_toOther && (!valid(_to) || _to == _account)) {
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

  // ── 上方貼一行文字，下面自動填 ───────────────────────────

  final _paste = TextEditingController();

  /// 貼上的那行讀得懂嗎：null＝還沒貼、'ok'＝填好了、其他＝錯誤說明。
  String? _pasteMsg;

  /// 貼一行匯入格式（`帳戶｜日期時間｜分類｜商家｜金額［｜幫誰｜對方要給｜已給｜餘額｜備註｜品項名稱］`），
  /// 照匯入同一套解析，把表單各欄自動填好（2026-11-03 使用者）。多行請用右上角的匯入。
  void _applyPaste(String text) {
    final raw = text.trim();
    if (raw.isEmpty) {
      setState(() => _pasteMsg = null);
      return;
    }
    final lines = book.parseImport(raw);
    if (lines.length > 1) {
      setState(() => _pasteMsg = '有 ${lines.length} 行：一次貼很多行請用右上角的匯入');
      return;
    }
    final l = lines.single;
    final t = l.tx;
    if (t == null) {
      setState(() => _pasteMsg = l.error);
      return;
    }
    final same = l.duplicateTx;
    if (same != null && widget.edit == null && widget.onSwitchEdit != null) {
      widget.onSwitchEdit!(same);
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _type = t.type == LedgerTxType.transfer
          ? LedgerTxType.transfer
          : t.type == LedgerTxType.income
          ? LedgerTxType.income
          : LedgerTxType.expense;
      _toOther = false;
      _amount.text = '${t.amount}';
      _account = t.accountId;
      _to = t.toAccountId;
      _toExt = t.toName;
      if (t.category != null) _category = t.category!;
      _merchant.text = t.merchant;
      _item.text = t.item;
      _memo.text = t.note;
      _at = t.occurredAt;
      _timeUnknown = t.timeUnknown;
      _order.text = t.timeOrder == 0 ? '' : '${t.timeOrder}';
      final pf = t.paidFor;
      _pf = pf != null;
      _pfSettled = pf?.settled ?? false;
      _split = false; // 貼上的一行不帶拆分
      _splitRows.forEach(_disposeRow);
      _splitRows.clear();
      _pfAmount.text = pf == null ? '' : '${pf.amount}';
      _pfPeople.text = pf?.people ?? '';
      _after.text = l.after == null ? '' : '${l.after}';
      _pasteMsg = l.duplicate ? 'dup:${l.duplicateOf}' : 'ok';
    });
  }

  void _setType(LedgerTxType t) => setState(() {
    _type = t;
    _applyDefaults(fillAmount: true);
  });

  /// 商家名稱必填：支出、收入、轉帳（退款、還錢會自動帶名稱，補記對帳差額也照樣要填）。
  /// 轉帳到信用卡就只會是繳卡費（2026-11-03 使用者）：名稱自動帶「繳卡費」、不能改。
  bool get _cardPayment =>
      _effType == LedgerTxType.transfer && book.account(_to)?.isCard == true;

  /// 轉帳按了「＋」：主帳戶（上面那排）是收到錢的那邊，存的時候兩個帳戶對調
  /// （信用卡 → 帳戶＝卡費退回就是這種）。
  bool get _neg =>
      _negative && _effType == LedgerTxType.transfer && _toExt.isEmpty;

  /// 金額最後面的「＋／−」鈕（2026-11-10 使用者：每種都要有、都要有實際功能）：
  /// 「−」＝錢從這個帳戶出去，「＋」＝錢進來。
  /// 支出 −（按＋變退款＝退刷）／退款 ＋（按−變支出）／收入 ＋（按−變支出，錢出去）／
  /// 還錢 ＋（按−變支出）／轉帳 −（按＋兩個帳戶對調，收款的變主帳戶）。
  /// 不出現的情形：轉給別人（算支出）的轉帳、已經被退過款的支出（會把退款孤立）、
  /// 編輯舊的還錢（原本那筆的「已給」會對不上）、對帳調整。
  bool get _showSign {
    final e = widget.edit;
    if (e != null &&
        e.type == LedgerTxType.expense &&
        book.linkedTo(e.id).isNotEmpty) {
      return false;
    }
    if (e != null && e.type == LedgerTxType.repayment) return false;
    return switch (_type) {
      LedgerTxType.transfer => !_toOther && _toExt.isEmpty,
      LedgerTxType.expense ||
      LedgerTxType.income ||
      LedgerTxType.refund ||
      LedgerTxType.repayment => true,
      _ => false,
    };
  }

  /// 現在是「＋」（錢進來）還是「−」（錢出去）。
  bool get _plus => switch (_type) {
    LedgerTxType.transfer => _neg,
    LedgerTxType.expense => false,
    _ => true,
  };

  /// 金額前面的符號：有「＋／−」鈕的時候跟著變，其他照舊只有 $。
  String get _signPrefix => !_showSign ? r'$ ' : (_plus ? r'+$ ' : r'−$ ');

  /// 按「＋／−」。切換時金額不動。
  void _flipSign() {
    switch (_type) {
      case LedgerTxType.transfer:
        setState(() => _negative = !_negative);
        return;
      case LedgerTxType.expense:
        final keep = _amount.text;
        _setType(LedgerTxType.refund);
        if (keep.isNotEmpty) setState(() => _amount.text = keep);
      case LedgerTxType.refund:
        final keep = _amount.text;
        _setType(LedgerTxType.expense);
        if (keep.isNotEmpty) setState(() => _amount.text = keep);
      case LedgerTxType.income || LedgerTxType.repayment:
        // 收入／還錢按「−」＝錢反過來是出去的：變成支出，分類先放「未分類」。
        final keep = _amount.text;
        _category = ledgerUncategorized;
        _setType(LedgerTxType.expense);
        if (keep.isNotEmpty) setState(() => _amount.text = keep);
      default:
        return;
    }
  }

  final _fixedName = TextEditingController(text: '繳卡費');

  bool get _merchantRequired =>
      !_cardPayment &&
      (_effType == LedgerTxType.expense ||
          _effType == LedgerTxType.income ||
          _effType == LedgerTxType.transfer);

  String? get _error {
    final amt = _int(_amount) ?? 0;
    if (_amount.text.trim().isEmpty) return '金額要填（折扣折抵到 0 就填 0）';
    if (_merchantRequired && _merchant.text.trim().isEmpty) {
      return _effType == LedgerTxType.income ? '來源要選' : '商家名稱要填';
    }
    if (book.account(_account) == null) return '要選帳戶';
    if (_effType == LedgerTxType.transfer) {
      if (_toExt.isEmpty && book.account(_to) == null) {
        return '要選轉到哪個帳戶';
      }
      if (_to == _account) return '轉出跟轉入不能是同一個帳戶';
    }
    if (_type == LedgerTxType.refund && book.tx(_linked) == null) {
      return '要選退哪一筆';
    }
    if (_type == LedgerTxType.repayment && book.tx(_linked) == null) {
      return '要選還哪一筆';
    }
    if (_type == LedgerTxType.expense && _split) {
      final amtAll = _int(_amount) ?? 0;
      if (_splitRows.length < 2) return '拆分至少要兩份';
      if (_splitRows.any((r) => (_int(r.amount) ?? 0) <= 0)) {
        return '每一份都要填金額（不要的份請按刪除）';
      }
      if (_splitSum != amtAll) {
        final d = amtAll - _splitSum;
        return '拆分加起來要剛好等於整筆 ${lMoney(amtAll)}，'
            '${d > 0 ? '還差' : '多了'} ${lMoney(d.abs())}';
      }
    }
    if (_type == LedgerTxType.expense && _pfOn) {
      final p = _pfValue;
      if (p <= 0) return '對方要給多少要填';
      if (p > amt) return '對方要給的不能超過整筆金額';
    }
    return null;
  }

  LedgerTx _build() {
    final e = widget.edit;
    final ty = _effType;
    final amt = _int(_amount)!;
    var merchant = _merchant.text.trim();
    if (_cardPayment) merchant = _neg ? '卡費退回' : '繳卡費';
    if (merchant.isEmpty && ty == LedgerTxType.refund) {
      final o = book.tx(_linked);
      merchant =
          '${o?.merchant.isNotEmpty == true ? o!.merchant : o?.category ?? ''} 退款';
    }
    if (merchant.isEmpty && ty == LedgerTxType.repayment) {
      merchant = '${book.tx(_linked)?.paidFor?.people ?? ''} 還錢';
    }
    final pf = _type == LedgerTxType.expense && _pfOn
        ? PaidFor(amount: _pfValue, people: _pfPeopleText, settled: _pfAllGiven)
        : null;
    final hasCat = ty == LedgerTxType.expense || ty == LedgerTxType.income;
    final linked = ty == LedgerTxType.refund || ty == LedgerTxType.repayment;
    // 拆分：category 放金額最大的那份當代表，統計照 splits 算。
    final splits = ty == LedgerTxType.expense && _split
        ? [
            for (final r in _splitRows)
              LedgerSplit(
                category: r.category,
                amount: _int(r.amount) ?? 0,
                name: r.name.text.trim(),
                forOther: r.forOther,
                settled: r.forOther && r.settled,
                people: r.forOther ? _rowPeople(r) : '',
                // 這一份對方只要給一部分（一人一半）才記，整份就不存。
                otherAmount: r.forOther && _rowOther(r) != (_int(r.amount) ?? 0)
                    ? _rowOther(r)
                    : null,
              ),
          ]
        : const <LedgerSplit>[];
    // 品項名稱只給沒拆分的支出；拆分的每一份各自有名稱。
    final item = ty == LedgerTxType.expense && !_split ? _item.text.trim() : '';
    final mainCat = splits.isEmpty
        ? _category
        : (splits.toList()..sort((a, b) => b.amount.compareTo(a.amount)))
              .first
              .category;
    if (e != null) {
      return e.copyWith(
        type: ty,
        occurredAt: _at,
        timeUnknown: _timeUnknown,
        timeOrder: _timeUnknown ? _orderValue : 0,
        amount: amt,
        // 卡費退回：存成信用卡 → 帳戶（跟繳卡費方向相反）。
        accountId: _neg ? _to! : _account,
        toAccountId: () => ty == LedgerTxType.transfer
            ? (_neg ? _account : (_toExt.isEmpty ? _to : null))
            : null,
        toName: ty == LedgerTxType.transfer ? _toExt : '',
        category: () => hasCat
            ? mainCat
            : ty == LedgerTxType.adjustment
            ? ledgerUncategorized
            : null,
        merchant: merchant,
        item: item,
        note: _memo.text.trim(),
        linkedId: () => linked ? _linked : null,
        flagged: _flagged,
        paidFor: () => pf,
        splits: splits,
      );
    }
    return LedgerTx(
      id: ledgerId(),
      type: ty,
      occurredAt: _at,
      timeUnknown: _timeUnknown,
      timeOrder: _timeUnknown ? _orderValue : 0,
      amount: amt,
      accountId: _neg ? _to! : _account!,
      toAccountId: ty == LedgerTxType.transfer
          ? (_neg ? _account : (_toExt.isEmpty ? _to : null))
          : null,
      toName: ty == LedgerTxType.transfer ? _toExt : '',
      category: hasCat ? mainCat : null,
      merchant: merchant,
      item: item,
      note: _memo.text.trim(),
      linkedId: linked ? _linked : null,
      flagged: _flagged,
      paidFor: pf,
      splits: splits,
      cpId: widget.prefill.cpId,
    );
  }

  /// 「幫誰」的快選：直接列之前幫過的人（最近的在前、不重複、最多 3 個）；Cen 幫過一次
  /// 之後自然就會出現，不用固定放（2026-11-04 使用者）。
  List<String> get _pfPeopleOptions {
    final out = <String>[];
    for (final t in book.txs) {
      // 拆分的每一份各自記了幫誰；沒拆的用整筆的。
      final names = t.splitHasOther
          ? [
              for (final s in t.splits)
                if (s.forOther) s.people.trim(),
            ]
          : [t.paidFor?.people.trim() ?? ''];
      for (final p in names) {
        if (p.isNotEmpty && !out.contains(p)) out.add(p);
        if (out.length >= 3) return out;
      }
    }
    return out;
  }

  /// 選填：這筆記下來之後，帳戶剩多少（信用卡是可刷餘額）。下一筆也有填的話，
  /// App 就能用「上次餘額 − 中間記到的」跟這次比，對不上就是中間漏記
  /// （2026-11-03 使用者）。轉帳（含繳卡費）可以兩邊帳戶各填一個。
  List<Widget> _afterField(LedgerTx? draft) {
    final from = book.account(_account);
    if (from == null) return const [];
    final isTransfer = _effType == LedgerTxType.transfer;
    final to = isTransfer ? book.account(_to) : null;
    return [
      ..._afterBox(
        draft,
        from,
        _after,
        _afterLabel(from, transfer: isTransfer),
      ),
      if (to != null)
        ..._afterBox(draft, to, _afterTo, _afterLabel(to, transfer: true)),
    ];
  }

  /// 餘額欄位的標題（2026-11-03 使用者）：戶頭＝戶頭餘額、現金＝皮包餘額、
  /// 信用卡＝可刷餘額（轉帳）／刷完後可刷額（刷卡）。
  ///
  /// 第一行寫是哪一個帳戶（2026-11-10 使用者：可用額度前面要標示清楚是哪一個帳戶；轉帳有兩個
  /// 帳戶各填一個，不寫名字分不出來）。
  String _afterLabel(LedgerAccount a, {required bool transfer}) =>
      '${a.name}\n${a.isCard
          ? (transfer ? '這筆之後可刷餘額' : '這筆刷完後可刷額')
          : a.type == LedgerAccountType.cash
          ? '這筆之後皮包餘額'
          : '這筆之後戶頭餘額'}';

  List<Widget> _afterBox(
    LedgerTx? draft,
    LedgerAccount a,
    TextEditingController ctrl,
    String label,
  ) {
    final s = book.stateOf(a);
    final card = a.isCard;
    // 照目前記到的推算「這筆之後應該剩多少」當提示（編輯舊的不推算）。
    int? guess;
    if (s != null && draft != null && widget.edit == null) {
      final occupied = s.now + LedgerBook.delta(draft, a);
      guess = card ? s.limit - occupied : occupied;
    }
    final got = _int(ctrl);
    return [
      _row(
        label,
        hint: '選填・抓漏記',
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: _digits,
          decoration: _input('', prefix: '\$'),
        ),
      ),
      if (guess != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 88),
          child: Text(
            got == null
                ? 'App 照記到的推算，這筆之後應該是 ${lMoney(guess)}'
                : got == guess
                ? '✓ 跟 App 推算的一樣'
                : '⚠ App 推算是 ${lMoney(guess)}，差 ${lMoney((guess - got).abs())}'
                      '${card ? (got < guess ? '（可能有刷卡沒記）' : '') : (got < guess ? '（可能有支出沒記）' : '')}'
                      '，新增後這筆會掛「漏記」標籤，補上就消失',
            style: AppText.note.copyWith(
              fontSize: 11,
              color: got == null || got == guess
                  ? AppColors.ink3
                  : AppColors.mid,
            ),
          ),
        )
      else if (s == null && got != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 88),
          child: Text(
            '這是 ${a.name} 第一個餘額，從這筆開始算；下一筆再填餘額就會幫你比對',
            style: AppText.note.copyWith(fontSize: 11, color: AppColors.ink3),
          ),
        ),
    ];
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
            subtitle: sub.isEmpty
                ? null
                : Text(sub, style: AppText.note.copyWith(fontSize: 10.5)),
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
    final pfAmt = _pfValue;
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
              // 退款不放在上面這排（2026-11-06 使用者），改放表單最下面。
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
      if (e == null && p.cpId == null) const SizedBox(height: 10),
      if (e == null && p.cpId == null) ...[
        TextField(
          controller: _paste,
          minLines: 1,
          maxLines: 3,
          onChanged: _applyPaste,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: _input('貼上一行文字，下面自動填（選填）').copyWith(
            suffixIcon: IconButton(
              tooltip: '從剪貼簿貼上',
              icon: const Icon(Icons.content_paste_rounded, size: 20),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text == null) return;
                _paste.text = d!.text!;
                _applyPaste(d.text!);
              },
            ),
          ),
        ),
        if (_pasteMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              _pasteMsg == 'ok'
                  ? '✓ 讀懂了，下面已經填好，確認一下再按「記下來」'
                  : _pasteMsg!.startsWith('dup:')
                  ? '⚠ 讀懂了，但跟${_pasteMsg!.substring(4)}相同（同帳戶、同一分鐘、同金額），按記下來也不會加'
                  : '✕ $_pasteMsg',
              style: TextStyle(
                fontSize: 11.5,
                color: _pasteMsg == 'ok' ? AppColors.ok : AppColors.mid,
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
      if (cp != null)
        _note([
          const TextSpan(text: '補記對帳差額：時間先設在 '),
          _b('${lMd(cp.at)} ${lHm(cp.at)} 對帳之前'),
          const TextSpan(text: '，選好分類、填商家就好，記完差額會自動消失。'),
        ], color: AppColors.mid),
      // 填寫順序：先時間、再金額（2026-11-03 使用者）。
      _row(
        '時間',
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  // 時間不確定就只選到哪一天，存那天中午當代表。
                  final DateTime? v;
                  if (_timeUnknown) {
                    v = await showDateTimeWheel(context, _at, dateOnly: true);
                  } else {
                    v = await _pickDateTime(context, _at);
                  }
                  if (v != null && mounted) {
                    final picked = _timeUnknown
                        ? DateTime(v.year, v.month, v.day, 12)
                        : v;
                    setState(() => _at = picked);
                  }
                },
                child: InputDecorator(
                  decoration: _input('').copyWith(
                    suffixIcon: Icon(
                      _timeUnknown
                          ? Icons.calendar_today_rounded
                          : Icons.schedule_rounded,
                      size: 18,
                      color: AppColors.ink2,
                    ),
                  ),
                  child: Text(
                    _timeUnknown ? lYmd(_at) : '${lYmd(_at)} ${lHm(_at)}',
                    style: _fieldStyle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 時間不確定的開關：打開就只選到天（沒有時、分）。
            Tooltip(
              message: '不確定幾點，只記哪一天',
              child: FilterChip(
                key: const ValueKey('timeUnknown'),
                label: const Text('不確定'),
                selected: _timeUnknown,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() {
                  _timeUnknown = v;
                  if (v) _at = DateTime(_at.year, _at.month, _at.day, 12);
                }),
              ),
            ),
            // 時間不確定的同一天有好幾筆時，右邊填排序數字決定先後（像圖層，2026-11-10 使用者）：
            // 1～20 排在有時分的後面、超過 20 排在有時分的前面，數字大的在前；新增、編輯都能設。
            if (_timeUnknown) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 58,
                child: TextField(
                  key: const ValueKey('timeOrder'),
                  controller: _order,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                    // 從 1 開始，0 不算：開頭的 0 直接去掉。
                    TextInputFormatter.withFunction((old, v) {
                      final t = v.text.replaceFirst(RegExp(r'^0+'), '');
                      return t == v.text
                          ? v
                          : TextEditingValue(
                              text: t,
                              selection: TextSelection.collapsed(
                                offset: t.length,
                              ),
                            );
                    }),
                  ],
                  decoration: _input('排序').copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      // 商家名稱在金額上面（2026-11-03 使用者）：先時間、再商家、再金額。
      if (t != LedgerTxType.adjustment) ...[
        // 商家名稱不放提示字（2026-11-03 使用者），記支出、收入、轉帳一定要填。
        _row(
          t == LedgerTxType.income
              ? '來源'
              : t == LedgerTxType.transfer
              ? (_toOther ? '轉給誰／買什麼' : '名稱')
              : '商家／名稱',
          hint: _cardPayment
              ? '自動帶入'
              : _merchantRequired
              ? '必填'
              : '選填',
          _cardPayment
              ? TextField(
                  controller: _fixedName..text = _neg ? '卡費退回' : '繳卡費',
                  enabled: false,
                  decoration: _input(''),
                )
              : t == LedgerTxType.income
              // 收入的來源就那幾種：下拉選單（2026-11-10 使用者）。
              ? Builder(
                  builder: (btn) => InkWell(
                    key: const ValueKey('incomeSource'),
                    borderRadius: BorderRadius.circular(12),
                    // 毛玻璃小選單（跟明細的篩選一樣）：只往下開、寬度剛好放得下字，不是整排撐開
                    // （2026-11-10 使用者：下拉選單像 iOS 毛玻璃、打開太大一個文字才幾個字）。
                    onTap: () async {
                      final cur = _merchant.text.trim();
                      // 選單只往下開：下面空間不夠就限制高度、裡面可以捲。
                      final box = btn.findRenderObject()! as RenderBox;
                      final below =
                          MediaQuery.sizeOf(context).height -
                          box.localToGlobal(Offset(0, box.size.height)).dy -
                          24;
                      final v = await showGlassMenu<String>(
                        btn,
                        width: 150,
                        maxHeight: below < 120 ? 120 : below,
                        alignLeft: true,
                        selected: cur.isEmpty ? null : cur,
                        items: [
                          for (final s in {
                            ...ledgerIncomeSources,
                            if (cur.isNotEmpty) cur,
                          })
                            GlassMenuItem(value: s, label: s),
                        ],
                      );
                      if (v != null) setState(() => _merchant.text = v);
                    },
                    child: InputDecorator(
                      decoration: _input('').copyWith(
                        suffixIcon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.ink2,
                        ),
                      ),
                      child: Text(
                        _merchant.text.trim().isEmpty
                            ? '選一個來源'
                            : _merchant.text.trim(),
                        style: TextStyle(
                          fontSize: 16,
                          color: _merchant.text.trim().isEmpty
                              ? AppColors.ink3
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                )
              : TextField(
                  controller: _merchant,
                  inputFormatters: halfWidthFormatters,
                  decoration: _input(''),
                ),
        ),
      ],
      _row(
        '金額',
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: _digits,
          autofocus: e == null && p.amount == null,
          decoration: _input('0', prefix: _signPrefix).copyWith(
            // 金額最後面的「＋／−」鈕（2026-11-10 使用者）：預設「−」＝扣款（消費、繳卡費），
            // 按一下變「＋」＝退回（退刷、退款、卡費退回）。新增、編輯都有。
            // 鈕比預設的後綴小一點，金額欄才不會比別的輸入框高（欄位規格要統一）。
            suffixIconConstraints: const BoxConstraints(
              minWidth: 50,
              minHeight: 38,
            ),
            suffixIcon: _showSign
                ? Padding(
                    padding: const EdgeInsets.all(3),
                    child: TextButton(
                      key: const ValueKey('signToggle'),
                      onPressed: _flipSign,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        backgroundColor: _plus
                            ? AppColors.ok.withValues(alpha: .18)
                            : AppColors.glassFill,
                        foregroundColor: _plus ? AppColors.ok : AppColors.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: Text(
                        _plus ? '＋' : '−',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
      // 沒拆分的支出可以寫品項名稱（2026-11-09 使用者），拆分時每一份各自有名稱。
      if (t == LedgerTxType.expense && !_split)
        _row(
          '品項名稱',
          TextField(
            controller: _item,
            maxLength: ledgerSplitNameMax,
            inputFormatters: halfWidthFormatters,
            decoration: _input('').copyWith(counterText: ''),
          ),
        ),
      // 寫了品項名稱之後，可以直接「添加品項 2」：自動變成拆分，這個品項是第一份
      // （2026-11-09 使用者）。
      if (t == LedgerTxType.expense && !_split && _item.text.trim().isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _toggleSplit(true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加品項 2'),
          ),
        ),
    ];

    switch (t) {
      case LedgerTxType.transfer when _toOther:
        children.addAll([
          _toggle(
            '轉給別人（算支出）',
            '例如轉錢給朋友請他幫你買東西：錢離開你的帳戶，算這個月的消費',
            true,
            (v) => setState(() => _toOther = v),
          ),
          _chipRow(
            '從哪個帳戶',
            _accountChips(book, _account, (v) => setState(() => _account = v)),
          ),
          _chipRow(
            '買什麼（分類）',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in ledgerExpenseCats.entries)
                  ChoiceChip(
                    label: Text('${c.value.$1} ${c.key}'),
                    selected: _category == c.key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _category = c.key),
                  ),
              ],
            ),
          ),
        ]);
      case LedgerTxType.transfer:
        children.addAll([
          _toggle(
            '轉給別人（算支出）',
            '錢不是轉到自己的帳戶、是給別人的（例如請朋友幫你買東西）就打開',
            false,
            (v) => setState(() {
              _toOther = v;
              if (v) {
                _to = null;
                _toExt = '';
              }
              if (!ledgerExpenseCats.containsKey(_category)) _category = '生活';
            }),
          ),
          const SizedBox(height: 10),
          // 快捷只是「幫你填好下面的欄位」，不是要選的選項，所以不用選項的膠囊樣子
          // （2026-11-03 使用者）：閃電圖示的按鈕＋一行說明。
          Text('快捷：點一下幫你填好帳戶跟名稱', style: AppText.note),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_firstOf(LedgerAccountType.bank) case final bank?)
                if (_firstOf(LedgerAccountType.cash) case final cash?)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _account = bank.id;
                      _to = cash.id;
                      if (_merchant.text.isEmpty) _merchant.text = 'ATM提款';
                    }),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('ATM 提款'),
                    style: _shortcutStyle,
                  ),
              if (_firstOf(LedgerAccountType.bank) case final bank?)
                if (_firstOf(LedgerAccountType.creditCard) case final card?)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _account = bank.id;
                      _to = card.id;
                    }),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('繳卡費'),
                    style: _shortcutStyle,
                  ),
            ],
          ),
          _chipRow(
            _neg ? '收款帳戶' : '從哪個帳戶',
            _accountChips(
              book,
              _account,
              (v) => setState(() {
                _account = v;
                if (_to == v) _to = null;
                _applyDefaults();
              }),
            ),
          ),
          _chipRow(
            _neg ? '從哪個帳戶轉來' : '轉到',
            _accountChips(
              book,
              _to,
              (v) => setState(() {
                _to = v;
                _toExt = '';
                _toOther = false;
              }),
              disabled: _account,
              // 轉到沒記在 App 裡的地方（2026-11-10 使用者）：自己的 LineBank（平轉，只扣這邊的錢、
              // 不算支出）、別人的戶頭（等於「轉給別人」，算支出）。轉進來（＋）時不顯示。
              extra: _neg
                  ? const []
                  : [
                      ChoiceChip(
                        key: const ValueKey('toLineBank'),
                        label: const Text('🏦 LineBank'),
                        selected: _toExt == 'LineBank',
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _toExt = 'LineBank';
                          _to = null;
                          _toOther = false;
                          if (_merchant.text.trim().isEmpty) {
                            _merchant.text = '平轉';
                          }
                        }),
                      ),
                      ChoiceChip(
                        key: const ValueKey('toOtherAccount'),
                        label: const Text('👤 他人戶頭'),
                        selected: _toOther,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _toOther = true;
                          _to = null;
                          _toExt = '';
                          if (!ledgerExpenseCats.containsKey(_category)) {
                            _category = '生活';
                          }
                        }),
                      ),
                    ],
            ),
          ),
          // 轉到信用卡＝繳卡費：只寫這一句（2026-11-03 使用者）。
          _note(
            _toExt.isNotEmpty
                ? [
                    const TextSpan(text: '平轉到自己的 '),
                    _b(_toExt),
                    TextSpan(
                      text: '：這個帳戶的錢會扣掉、但不算支出；$_toExt 沒記在 App 裡，不追蹤它的餘額。',
                    ),
                  ]
                : book.account(_to)?.isCard == true
                ? [
                    TextSpan(
                      text: _neg
                          ? '卡費退回（＋）：信用卡欠的變多、錢回到帳戶，不會列入支出；按金額最後的「＋」改回「−」。'
                          : '繳卡費不會列入支出，刷卡那時已算過一次。按金額最後的「−」可以改成「＋」（卡費退款、部分退款）。',
                    ),
                  ]
                : [
                    const TextSpan(text: '轉帳只是把錢換個地方放，'),
                    _b('不算支出'),
                    const TextSpan(text: '。'),
                  ],
          ),
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
                  _chipRow(
                    '退回哪個帳戶',
                    _accountChips(
                      book,
                      _account,
                      (v) => setState(() => _account = v),
                    ),
                  ),
                  _note([
                    const TextSpan(text: '退款會從原本那筆的分類扣回來；退回信用卡的話，可刷額也會跟著變多。'),
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
                  _label('給的是哪一筆'),
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
                  _chipRow(
                    '錢進哪個帳戶',
                    _accountChips(
                      book,
                      _account,
                      (v) => setState(() => _account = v),
                      only: (a) => !a.isCard,
                    ),
                  ),
                  if (e == null)
                    _toggle(
                      '這次還完就標記已還清',
                      '打開就標記這筆對方已經給了',
                      _settle,
                      (v) => setState(() => _settle = v),
                    ),
                  _note([
                    const TextSpan(text: '收到欠款'),
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
          _chipRow(
            t == LedgerTxType.income ? '進哪個帳戶' : '用哪個付',
            _accountChips(
              book,
              _account,
              (v) => setState(() => _account = v),
              only: t == LedgerTxType.income ? (a) => !a.isCard : null,
            ),
          ),
          if (_split && t == LedgerTxType.expense) ...[
            _label('拆分（加起來要剛好等於整筆）'),
            for (final (i, r) in _splitRows.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<String>(
                            initialValue: r.category,
                            isExpanded: true,
                            decoration: _input(''),
                            items: [
                              for (final c in ledgerExpenseCats.entries)
                                DropdownMenuItem(
                                  value: c.key,
                                  child: Text('${c.value.$1} ${c.key}'),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => r.category = v ?? r.category),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: r.amount,
                            keyboardType: TextInputType.number,
                            inputFormatters: _digits,
                            decoration: _input('', prefix: '\$'),
                          ),
                        ),
                        IconButton(
                          tooltip: '刪掉這一份',
                          onPressed: _splitRows.length <= 2
                              ? null
                              : () => setState(() {
                                  _disposeRow(_splitRows.removeAt(i));
                                }),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: AppColors.ink3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 品項名稱（選填）＋這一份是不是幫人付的、對方給了沒。
                    // 品項名稱跟「幫人付」按鈕同一行（2026-11-05 使用者）。
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: r.name,
                            inputFormatters: halfWidthFormatters,
                            maxLength: ledgerSplitNameMax,
                            decoration: _input(
                              '品項名稱（選填）',
                            ).copyWith(counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('👥 幫人付'),
                          selected: r.forOther,
                          showCheckmark: false,
                          onSelected: (v) => setState(() {
                            r.forOther = v;
                            if (!v) r.settled = false;
                            // 前一份已經填了幫誰就直接帶過來，常常是同一個人。
                            if (v && r.people.text.trim().isEmpty) {
                              r.people.text =
                                  _splitRows
                                      .where(
                                        (x) =>
                                            x.forOther &&
                                            x.people.text.trim().isNotEmpty,
                                      )
                                      .map((x) => x.people.text.trim())
                                      .firstOrNull ??
                                  _defaultPerson;
                            }
                          }),
                        ),
                      ],
                    ),
                    // 這一份幫誰：直接寫在這一份底下，可以打字或點最近幫過的人；
                    // 對方給了沒（已給）跟幫誰同一行。
                    if (r.forOther) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('splitPeople$i'),
                              controller: r.people,
                              inputFormatters: halfWidthFormatters,
                              decoration: _input('幫誰（例如 Cen）'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('✓ 已給'),
                            selected: r.settled,
                            showCheckmark: false,
                            onSelected: (v) => setState(() => r.settled = v),
                          ),
                        ],
                      ),
                      // 這一份對方要給多少：不填＝整份；一人一半按「一半」（2026-11-09 使用者）。
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('splitOther$i'),
                              controller: r.other,
                              keyboardType: TextInputType.number,
                              inputFormatters: _digits,
                              decoration: _input(
                                '對方要給多少（不填＝整份）',
                                prefix: '\$ ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('一半'),
                            selected:
                                (_int(r.amount) ?? 0) > 1 &&
                                r.other.text.isNotEmpty &&
                                _rowOther(r) == (_int(r.amount) ?? 0) ~/ 2,
                            showCheckmark: false,
                            onSelected: (_) => setState(
                              () => r.other.text =
                                  '${(_int(r.amount) ?? 0) ~/ 2}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('整份'),
                            selected:
                                r.other.text.isEmpty ||
                                _rowOther(r) == (_int(r.amount) ?? 0),
                            showCheckmark: false,
                            onSelected: (_) => setState(() => r.other.clear()),
                          ),
                        ],
                      ),
                      if (_pfPeopleOptions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final n in _pfPeopleOptions)
                                ChoiceChip(
                                  label: Text(n),
                                  selected: r.people.text.trim() == n,
                                  showCheckmark: false,
                                  onSelected: (_) =>
                                      setState(() => r.people.text = n),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _splitRows.add(_newSplitRow('生活', ''))),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('再加一份'),
                ),
                const Spacer(),
                Text(
                  () {
                    final d = (_int(_amount) ?? 0) - _splitSum;
                    return d == 0
                        ? '✓ 剛好拆滿 ${lMoney(_int(_amount) ?? 0)}'
                        : d > 0
                        ? '還差 ${lMoney(d)}'
                        : '多了 ${lMoney(-d)}';
                  }(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: (_int(_amount) ?? 0) - _splitSum == 0
                        ? AppColors.ok
                        : AppColors.mid,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _toggleSplit(false),
              child: const Text('取消拆分，改回單一分類'),
            ),
          ] else ...[
            _chipRow(
              '分類',
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
            ),
            if (t == LedgerTxType.expense)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _toggleSplit(true),
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: const Text('拆分（一筆裡有不同分類）'),
                ),
              ),
          ],
        ]);
    }

    children.addAll([
      ..._afterField(err == null ? _build() : null),
      _row(
        '備註',
        hint: '選填',
        TextField(
          controller: _memo,
          inputFormatters: halfWidthFormatters,
          maxLength: ledgerNoteMax,
          decoration: _input('').copyWith(counterText: ''), // 不顯示 0/100，每個欄位一樣高
        ),
      ),
      _toggle(
        '🚩 標記旗幟',
        '純註記 不影響任何計算',
        _flagged,
        (v) => setState(() => _flagged = v),
      ),
    ]);
    if (t == LedgerTxType.expense) {
      // 2026-11-03 使用者：標一筆是跟別人一起的、對方要給多少（不一定是一半，
      // 100 元可能他該給 70）、後來有沒有給就好。
      // 拆分時改成每一份各自標「幫人付」，這裡只留幫誰（2026-11-05 使用者）。
      if (!_split) {
        children.add(
          _toggle(
            '👥 跟別人一起（對方要給我錢）',
            '例如聚餐你先付，之後他再給你',
            _pf,
            (v) => setState(() {
              _pf = v;
              if (v && _pfAmount.text.isEmpty && amt > 0) {
                _pfAmount.text = '${amt ~/ 2}';
              }
              // 幫誰預設填快選列的第一個，不用再點（2026-11-05 使用者）。
              if (v && _pfPeople.text.trim().isEmpty) {
                _pfPeople.text = _defaultPerson;
              }
            }),
          ),
        );
      }
      if (_pfOn) {
        children.addAll([
          // 拆分時「幫誰」「已給」都寫在每一份底下，這裡只留一句說明。
          if (_split)
            _note([
              const TextSpan(text: '拆分裡標了「幫人付」的那幾份，加起來 '),
              _b(lMoney(pfAmt)),
              const TextSpan(text: ' 是對方要給的；幫誰、已給都在每一份底下各自填。'),
            ], color: ledgerPaidFor)
          else ...[
            // 點一下最近幫過的人就填進去，也可以自己打（2026-11-03 使用者）。
            _row(
              '幫誰',
              TextField(
                controller: _pfPeople,
                inputFormatters: halfWidthFormatters,
                decoration: _input(''),
              ),
            ),
            const SizedBox(height: 6),
            if (_pfPeopleOptions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final n in _pfPeopleOptions)
                    ChoiceChip(
                      label: Text(n),
                      selected: _pfPeople.text.trim() == n,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _pfPeople.text = n),
                    ),
                ],
              ),
            _row(
              '對方給你',
              hint: amt > 0 ? '整筆 ${lMoney(amt)}' : null,
              TextField(
                controller: _pfAmount,
                keyboardType: TextInputType.number,
                inputFormatters: _digits,
                decoration: _input('例如 70', prefix: '\$'),
              ),
            ),
            if (amt > 0) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final (label, v) in [
                    ('一半 ${lMoney(amt ~/ 2)}', amt ~/ 2),
                    ('全部 ${lMoney(amt)}', amt),
                  ])
                    // 目前填的金額剛好等於這個值就亮起來（預設一半時「一半」是選中的）。
                    ChoiceChip(
                      label: Text(label),
                      selected: pfAmt == v,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _pfAmount.text = '$v'),
                    ),
                ],
              ),
            ],
            // 記的當下就能勾「對方已經給我了」（2026-11-03 使用者），不用再進去補。
            _toggle(
              '✓ 對方已給',
              '',
              _pfSettled,
              (v) => setState(() => _pfSettled = v),
            ),
          ],
          if (!_split)
            _note(
              amt > 0 && pfAmt > 0 && pfAmt <= amt
                  ? [
                      const TextSpan(text: '本月消費只算你自己的 '),
                      _b(lMoney(amt - pfAmt)),
                      const TextSpan(text: '；對方給了之後，在這筆按「他給了 ✓」就好。'),
                    ]
                  : [const TextSpan(text: '本月消費只算你自己的那份；他給了之後按「他給了 ✓」就好。')],
              color: ledgerPaidFor,
            ),
        ]);
      }
    }

    // 退款放在整張表單最下面、「跟別人一起」之下（2026-11-06 使用者）：打開就切成退款，
    // 要選退哪一筆；關掉回支出。新增時才有（編輯舊的退款不能改類型）。
    if (e == null && p.cpId == null) {
      children.add(
        _toggle(
          '↩ 退款',
          '退回之前某一筆支出的錢',
          t == LedgerTxType.refund,
          (v) => _setType(v ? LedgerTxType.refund : LedgerTxType.expense),
        ),
      );
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
            e == null ? '新增' : '儲存',
            err == null
                ? () => Navigator.pop(context, (
                    tx: _build(),
                    settleLinked: _type == LedgerTxType.repayment && _settle,
                    // 卡費退回時兩邊帳戶對調，餘額也跟著對調。
                    after: _neg ? _int(_afterTo) : _int(_after),
                    afterTo: _effType == LedgerTxType.transfer
                        ? (_neg ? _int(_after) : _int(_afterTo))
                        : null,
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
              ? '${a.name}可刷額 ${d > 0 ? '−' : '+'}${lInt(d.abs())}'
              : '${a.name} ${d > 0 ? '+' : '−'}${lInt(d.abs())}',
    ].join('\n');
    final counts = switch (t.type) {
      LedgerTxType.expense =>
        t.isSplit
            ? '算進本月消費 ${lMoney(t.ownSpend)}，照拆分分到各分類'
            : '算進本月消費 ${lMoney(t.ownSpend)}（${t.category}）',
      LedgerTxType.income =>
        t.category == ledgerFlatTransfer ? '不算收入，只是自己帳戶之間轉來轉去' : '算進本月收入',
      LedgerTxType.transfer =>
        t.toName.isNotEmpty
            ? '平轉到 ${t.toName}：只是自己的錢換個戶頭放、不算支出；${t.toName} 沒有記在 App 裡，所以只扣這個帳戶的錢'
            : book.isCardReturn(t)
            ? '卡費退回（負的繳卡費）：信用卡欠的變多、錢回到帳戶，不列入支出'
            : book.account(t.toAccountId)?.type == LedgerAccountType.cash
            ? '不算支出，只是從數位轉移至實體現金'
            : book.account(t.toAccountId)?.isCard == true
            ? '繳卡費不會列入支出，刷卡那時已算過一次。'
            : '不算支出，只是換個帳戶放',
      LedgerTxType.refund =>
        '從「${book.tx(t.linkedId)?.category ?? ledgerUncategorized}」扣回 ${lMoney(t.amount)}',
      LedgerTxType.repayment => '不算收入（你的錢回來）',
      LedgerTxType.adjustment => t.isAdjustOut ? '算進本月消費（未分類）' : '對帳多出來的錢，不算收入',
    };
    final sign = t.isOut
        ? '−'
        : t.type == LedgerTxType.transfer
        ? (book.isCardReturn(t) ? '+' : '')
        : '+';
    final pf = t.paidFor;
    final linked = book.linkedTo(t.id);
    final txCp = book.checkpointOfTx(t.id);
    final txGap = book.gapOfTx(t.id);
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
            if (t.flagged) const LedgerPill('🚩 旗幟', color: ledgerBad),
          ],
        ),
        _box([
          _kv(
            '時間',
            t.timeUnknown
                ? '${lYmd(t.occurredAt)}（不確定幾點）'
                : '${lYmd(t.occurredAt)} ${lHm(t.occurredAt)}',
          ),
          _kv(
            '帳戶',
            t.type == LedgerTxType.transfer
                ? '${book.accountName(t.accountId)} → ${book.toLabel(t)}'
                : book.accountName(t.accountId),
          ),
          if (t.isSplit)
            _kv(
              '拆分',
              t.splits
                  .map(
                    (s) =>
                        '${s.category}${s.name.isEmpty ? '' : '・${s.name}'} ${lMoney(s.amount)}'
                        '${s.forOther ? '　👥${s.people.isEmpty ? '幫人付' : '幫${s.people}付'}${s.otherPart != s.amount ? ' ${lMoney(s.otherPart)}' : ''}${s.settled ? '✓已給' : '（還沒給）'}' : ''}',
                  )
                  .join('\n'),
            )
          else if (t.category != null && t.type != LedgerTxType.transfer)
            _kv('分類', t.category!),
          _kv('名稱', t.merchant.isEmpty ? '—' : t.merchant),
          if (t.item.isNotEmpty) _kv('品項', t.item),
          if (t.note.isNotEmpty) _kv('備註', t.note),
          _kv('帳戶變化', effects.isEmpty ? '—' : effects),
          _kv('支出算法', counts),
          _kv('來源', switch (t.source) {
            'paste' => '貼上匯入',
            'adjust' => '對帳產生',
            _ => '手動計帳',
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
        if (txCp != null) ...[
          ledgerSection(
            '${book.accountName(txCp.accountId)}・'
            '${txCp.available != null ? '刷完後的可用額度' : '這筆之後的餘額'}',
          ),
          _box([
            _kv(
              '${book.accountName(txCp.accountId)} '
              '${txCp.available != null ? '可用額度' : '餘額'}',
              lMoney(txCp.available ?? txCp.balance ?? 0),
            ),
            if (txGap == null)
              _kv(
                '跟上一個餘額比',
                book.checkpointDiff(book.account(txCp.accountId)!, txCp) == null
                    ? '這是第一個餘額，從這裡開始算'
                    : '✓ 對得上',
                color: AppColors.ok,
              )
            else
              _kv(
                txGap.miss > 0 ? '漏記' : '多出',
                lMoney(txGap.miss.abs()),
                color: AppColors.mid,
                sub: txGap.miss > 0
                    ? '跟上一個餘額比，中間可能有支出沒記'
                    : '跟上一個餘額比，中間可能有收入或退款沒記',
              ),
          ]),
          if (txGap != null) ...[
            const SizedBox(height: 8),
            // 缺的數字剛好對得上哪一筆已經記的：先提示可能的原因。
            for (final h in book.gapHints(txCp))
              _option(
                context,
                '💡',
                switch (h.kind) {
                  GapHintKind.wrongTime =>
                    '「${LedgerBook.describe(h.tx)}」剛好是缺的數字，但時間在這兩個餘額之外',
                  GapHintKind.wrongAccount =>
                    '「${LedgerBook.describe(h.tx)}」剛好是缺的數字，但記在「${book.accountName(h.tx.accountId)}」',
                  GapHintKind.refund =>
                    '「${LedgerBook.describe(h.tx)}」剛好是多出的數字，是不是退款沒記？',
                },
                switch (h.kind) {
                  GapHintKind.wrongTime => '點一下把它的時間改到這兩個餘額中間',
                  GapHintKind.wrongAccount =>
                    '點一下改成記在「${book.accountName(txCp.accountId)}」',
                  GapHintKind.refund => '點一下記一筆退款（原路退回這張卡）',
                },
                () => pop(switch (h.kind) {
                  GapHintKind.wrongTime => 'hintMove',
                  GapHintKind.wrongAccount => 'hintAccount',
                  GapHintKind.refund => 'hintRefund',
                }, '${h.tx.id}|${txCp.id}'),
              ),
            _option(
              context,
              '✏️',
              '補記漏掉的那筆',
              '時間會放在上一個餘額跟這筆中間，記完這個標籤自己消失',
              () => pop('fixAddCp', txCp.id),
            ),
            _option(
              context,
              '⚖️',
              '想不起來，直接調成未分類',
              '記一筆未分類的調整把差額補平，標籤也會消失',
              () => pop('fixAdjustCp', txCp.id),
            ),
          ],
        ],
        if (pf != null) ...[
          ledgerSection('👥 跟 ${pf.people} 一起'),
          _box([
            _kv('對方要給你', lMoney(pf.amount)),
            if (book.repaidOf(t.id) > 0)
              _kv('已經給', lMoney(book.repaidOf(t.id)), color: AppColors.ok),
            _kv(
              '狀態',
              pf.settled
                  ? '✓ 他給了'
                  : '還沒給 ${lMoney(pf.amount - book.repaidOf(t.id))}',
              color: pf.settled ? AppColors.ok : AppColors.mid,
            ),
            _kv('算進你的消費', lMoney(t.ownSpend)),
          ]),
          const SizedBox(height: 8),
          if (pf.settled)
            OutlinedButton(
              onPressed: () => pop('unsettle'),
              style: _outline,
              child: const Text('改回還沒給'),
            )
          else
            _filled('他給了 ✓', () => pop('settle')),
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
  /// null＝這個帳戶還沒填過餘額：這次只是「填餘額」，從現在開始算。
  late final AccountState? _s = widget.book.stateOf(widget.account);
  final _value = TextEditingController();

  /// 信用卡不需要總額度（使用者）：沿用已經知道的，不知道就 0，只比可用額度。
  int get _knownLimit => _s?.limit ?? widget.account.creditLimit ?? 0;

  @override
  void initState() {
    super.initState();
    _value.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  bool get _card => widget.account.isCard;

  int? get _actual {
    final v = _int(_value);
    if (v == null) return null;
    if (!_card) return v;
    return _knownLimit - v;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account, s = _s, book = widget.book;
    final first = s == null;
    // 信用卡一律寫「可用額度（可刷額）」，不提總額度、已占用。
    final noLimit = _card;
    final since = s == null
        ? const <int>[]
        : book.txs
              .where((t) => book.calcAtOf(t).isAfter(s.last.at))
              .map((t) => LedgerBook.delta(t, a))
              .where((d) => d != 0)
              .toList();
    final plus = since.where((d) => d > 0).fold(0, (x, d) => x + d);
    final minus = since.where((d) => d < 0).fold(0, (x, d) => x - d);
    final actual = _actual;
    final miss = actual == null || s == null
        ? null
        : LedgerBook.missOf(a, actual, s.now);
    final step = widget.step;
    return _Frame(
      title: first ? '填餘額：${a.name}' : '對帳：${a.name}',
      footer: _filled(
        first ? '記下來' : '確認對帳',
        actual == null
            ? null
            : () => Navigator.pop(
                context,
                LedgerCheckpoint(
                  id: ledgerId(),
                  accountId: a.id,
                  at: DateTime.now(),
                  balance: _card ? null : _int(_value),
                  creditLimit: _card && _knownLimit > 0 ? _knownLimit : null,
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
          if (first)
            const TextSpan(text: '\n這是第一次填，App 從現在開始幫你算；之後再填一次就能比對有沒有漏記。'),
        ]),
        if (s != null)
          _box([
            _kv(
              '上次確認',
              noLimit
                  ? lMoney(s.last.available ?? 0)
                  : lMoney(LedgerBook.checkpointValue(a, s.last)),
              sub: '${lYmd(s.last.at)} ${lHm(s.last.at)}',
            ),
            _kv(
              '之後記到的（${since.length} 筆）',
              _card
                  ? '+${lInt(plus)} 刷卡／−${lInt(minus)} 繳款退款'
                  : '+${lInt(plus)}／−${lInt(minus)}',
            ),
            if (noLimit)
              _kv('App 推算可刷額', lMoney(s.available))
            else
              _kv(_card ? 'App 推算已占用' : 'App 推算現在', lMoney(s.now)),
          ]),
        if (_card) ...[
          _label('現在可刷額（可用額度）'),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('', prefix: '\$'),
          ),
        ] else ...[
          _label(a.type == LedgerAccountType.cash ? '錢包實際有多少' : '實際餘額'),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _digits,
            decoration: _input('輸入數字', prefix: '\$'),
          ),
        ],
        if (s == null)
          const SizedBox.shrink()
        else if (actual == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '填完馬上算出差額',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
          )
        else
          _box([
            if (noLimit) ...[
              _kv('實際可刷額', lMoney(_int(_value) ?? 0)),
              _kv('App 推算', lMoney(s.available)),
            ] else ...[
              if (_card)
                _kv('實際已占用＝額度 − 可用', lMoney(actual))
              else
                _kv('實際', lMoney(actual)),
              _kv('App 推算', lMoney(s.now)),
            ],
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
        if (s != null && s.miss != 0)
          _note([
            TextSpan(text: '之前 ${lMd(s.last.at)} 對帳還有 '),
            _b(lMoney(s.miss.abs())),
            const TextSpan(text: ' 沒處理，這次會一起算進總差額。'),
          ], color: AppColors.mid),
        if (_card && (miss ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '可刷額比算的少：可能有刷卡沒記，或是預授權（飯店、加油站）先占了額度。',
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
              ? '${a.name}從第一次填餘額到現在都沒有漏記'
              : '${thisMiss != null && thisMiss != 0 ? '這次差 ${lMoney(thisMiss.abs())}・' : ''}'
                    '${s.miss > 0 ? (a.isCard ? '可刷額比 App 算的少，可能有刷卡沒記到' : '實際比 App 算的少，可能有支出沒記到') : '實際比 App 算的多，可能有收入或退款沒記到'}',
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
    final a = account, s = book.stateOf(a);
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
            if (s != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    a.isCard ? 'App 推算可刷額' : 'App 推算餘額',
                    style: AppText.note,
                  ),
                  Text(
                    lMoney(a.isCard ? s.available : s.now),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontFeatures: lTabular,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (s == null) ...[
          _note([
            const TextSpan(text: '還沒填餘額，這個帳戶只記交易、不算餘額。想讓 App 幫你'),
            _b('對帳、抓漏記'),
            const TextSpan(text: '的話填一次現在有多少，從那時候開始算。'),
          ]),
          const SizedBox(height: 10),
          _filled(a.isCard ? '填可用額度' : '填餘額', () => pop('recon')),
        ] else ...[
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
                  final first = d == null;
                  return InkWell(
                    onLongPress: () => pop('deleteCp', c.id),
                    child: _kv(
                      first
                          ? '📌 第一次填 ${lMd(c.at)}'
                          : '⚖️ ${lMd(c.at)} ${lHm(c.at)}',
                      '${lMoney(LedgerBook.checkpointValue(a, c))}\n'
                      '${first
                          ? '從這裡開始算'
                          : d.miss == 0
                          ? '✓ 對上'
                          : '當時差 ${lMoney(d.miss.abs())}'}',
                      color: first || d.miss == 0 ? null : AppColors.mid,
                      sub:
                          '${a.isCard ? '可刷額 ${lInt(c.available ?? 0)}' : '實際餘額'}'
                          '${fixes.isEmpty ? '' : '・已${fixes.first.type == LedgerTxType.adjustment ? '調整' : '補記'} ${lMoney(fixes.fold(0, (x, t) => x + t.amount))}'}',
                    ),
                  );
                },
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '輸入錯了：長按那一列可以刪掉。',
              style: AppText.note.copyWith(
                fontSize: 10.5,
                color: AppColors.ink3,
              ),
            ),
          ),
        ],
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

/// 回傳要匯入的交易，跟因為重複沒加的那幾行說明。
Future<
  ({
    List<LedgerTx> txs,
    List<String> skipped,
    List<String> sameDay,
    Map<String, int> afters,
  })?
>
showImportSheet(BuildContext context, LedgerBook book) =>
    _sheet(context, _Import(book: book));

class _Import extends StatefulWidget {
  const _Import({required this.book});

  final LedgerBook book;

  @override
  State<_Import> createState() => _ImportState();
}

class _ImportState extends State<_Import> {
  final _text = TextEditingController();

  /// 勾了「算支出」的轉帳那幾行（key＝第幾行｜原文）：錢是轉給別人的。
  final _asSpend = <String>{};

  /// 預覽裡點一行編輯過的結果（key 同上）：匯入時用這個。
  final _over = <String, ({LedgerTx tx, int? after})>{};

  LedgerTx _txOf(int i, ImportLine l) => _over[_key(i, l)]?.tx ?? l.tx!;
  int? _afterOf(int i, ImportLine l) =>
      _over.containsKey(_key(i, l)) ? _over[_key(i, l)]!.after : l.after;

  /// 點一行：開跟普通記帳一樣的編輯表單（欄位先填好），改完回預覽。
  Future<void> _editRow(int i, ImportLine l) async {
    final r = await showTxFormSheet(
      context,
      widget.book,
      edit: _txOf(i, l),
      initialAfter: _afterOf(i, l),
    );
    if (r == null || !mounted) return;
    setState(() => _over[_key(i, l)] = (tx: r.tx, after: r.after));
  }

  static String _key(int i, ImportLine l) => '$i|${l.line}';

  /// 匯入時套用「算支出」：轉帳改成一筆未分類支出。
  LedgerTx _final(int i, ImportLine l) {
    final t = _txOf(i, l);
    if (t.type != LedgerTxType.transfer || !_asSpend.contains(_key(i, l))) {
      return t;
    }
    return t.copyWith(
      type: LedgerTxType.expense,
      toAccountId: () => null,
      category: () => ledgerUncategorized,
    );
  }

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
            : () => Navigator.pop(context, (
                txs: [
                  for (final (i, l) in lines.indexed)
                    if (l.willImport) _final(i, l),
                ],
                skipped: [
                  for (final l in lines)
                    if (l.duplicateOf != null)
                      '「${l.tx!.merchant}」跟${l.duplicateOf}相同',
                ],
                sameDay: [
                  for (final (i, l) in lines.indexed)
                    if (l.willImport && l.sameDayOf != null)
                      '「${_txOf(i, l).merchant}」跟${l.sameDayOf}金額相同',
                ],
                afters: {
                  for (final (i, l) in lines.indexed)
                    if (l.willImport && _afterOf(i, l) != null)
                      _final(i, l).id: _afterOf(i, l)!,
                },
              )),
      ),
      children: [
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          minLines: 5,
          maxLines: 10,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: _input('把文字貼在這裡'),
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
          for (final (i, l) in lines.indexed) _importRow(i, l),
        ledgerSection('格式說明'),
        _note([
          const TextSpan(text: '一行一筆：'),
          _b('帳戶｜日期時間｜分類｜商家｜金額'),
          const TextSpan(text: '，後面可以再加'),
          _b('｜幫誰｜對方要給｜已給｜餘額｜備註｜品項名稱'),
          const TextSpan(
            text:
                '（選填：填幫誰、對方要給就是跟別人一起；他已經給了就再加「｜已給」）。\n'
                '最後可以再加一欄「｜餘額」＝這筆之後帳戶剩多少（信用卡填可用額度），用來抓漏記；'
                '「備註」想寫什麼都可以；最後一欄是「品項名稱」（最多 50 字，只有支出跟轉給別人用得到）；'
                '中間沒有的欄位留空，例如 ……｜1000｜｜｜｜48500｜請客｜牛肉麵。\n',
          ),
          const TextSpan(
            text:
                '帳戶寫帳戶名稱（現金、郵局）就記在那裡；寫銀行名稱（中信銀行）'
                '當刷卡記在信用卡。分類是「提款」的會變成',
          ),
          _b('轉帳（銀行 → 現金）'),
          const TextSpan(
            text:
                '、不算支出。分類寫「轉帳」：商家那欄寫自己的帳戶名稱（郵局）就是轉帳，'
                '寫別人（小美）就當轉給別人、算支出；轉帳那幾行也可以在預覽勾「算支出」。'
                '一樣的紀錄會跳過，原始那行會留在明細裡。',
          ),
          const TextSpan(text: '收入：分類寫 '),
          _b('薪資轉帳、ATM存款（或收入存款、帳戶存款）、轉入、平轉'),
          const TextSpan(
            text:
                '（也可以寫薪資、獎金、存款、其他收入）就記成收入；收入跟分類一次寫好用「收入/分類」，例如「收入/未分類」「收入/薪資」「ATM存款/平轉」；自己帳戶之間轉來轉去寫「平轉」（錢會進帳戶、但不算本月收入），錢進第一欄的帳戶'
                '（寫現金進現金，其他進銀行）；收入最後一欄（第 11 欄）寫的字會當備註；收到的轉帳要寫「轉入」，因為「轉帳」是轉出去。\n',
          ),
        ]),
        _note([
          const TextSpan(
            text:
                '範例：\n'
                '中信銀行｜2026/11/02 19:30｜餐飲｜鼎泰豐｜1000｜小美｜700\n'
                '中信銀行｜2026/11/01 20:00｜餐飲｜火鍋｜900｜小美｜450｜已給\n'
                '中信銀行｜2026/11/04 12:00｜餐飲｜麥當勞｜189｜｜｜｜86000｜加班\n'
                '現金｜2026/11/05 15:00｜寵物｜飼料｜650｜｜｜｜｜補貨\n'
                '現金｜2026/11/05 18:00｜餐飲｜全家｜35｜｜｜｜｜｜御飯糰\n'
                '現金｜2026/11/03 12:30｜餐飲｜便當｜120\n'
                '中信帳戶｜2026/11/01 10:00｜提款｜ATM提款｜3000\n'
                '中信帳戶｜2026/11/01 11:00｜轉帳｜郵局｜5000\n'
                '中信帳戶｜2026/11/01 12:00｜轉帳｜小美｜800\n'
                '中信帳戶｜2026/11/05 09:00｜薪資轉帳｜某某公司｜50000\n'
                '中信帳戶｜2026/11/06 10:00｜ATM存款｜ATM｜3000\n'
                '中信帳戶｜2026/11/07 11:00｜轉入｜小美還款｜800\n'
                '中信銀行｜2026/06/29 20:09｜平轉｜ATM存款｜58000｜｜｜｜｜｜存款入帳',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ]),
      ],
    );
  }

  Widget _importRow(int i, ImportLine l) {
    final t = l.tx == null ? null : _txOf(i, l);
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
        child: InkWell(
          onTap: () => _editRow(i, l),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              LedgerIcon(emoji, color, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.merchant}・${lMd(t.occurredAt)} ${lTxHm(t)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (t.type == LedgerTxType.transfer && !l.duplicate)
                      InkWell(
                        onTap: () => setState(() {
                          final k = _key(i, l);
                          if (!_asSpend.remove(k)) _asSpend.add(k);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _asSpend.contains(_key(i, l))
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 18,
                                color: _asSpend.contains(_key(i, l))
                                    ? ledgerAccent
                                    : AppColors.ink3,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '算支出（錢是給別人的）',
                                style: AppText.note.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      t.type == LedgerTxType.transfer
                          ? _asSpend.contains(_key(i, l))
                                ? '支出・${book.accountName(t.accountId)}・未分類（轉給別人）'
                                : '轉帳 ${book.accountName(t.accountId)} → ${book.toLabel(t)}（不算支出）'
                          : '支出・${book.accountName(t.accountId)}・${t.category}'
                                '${t.paidFor == null ? '' : '・${t.paidFor!.people} ${t.paidFor!.settled ? '已給' : '要給'} ${lMoney(t.paidFor!.amount)}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.note.copyWith(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                      ),
                    ),
                    if (l.duplicateOf != null)
                      Text(
                        '跟${l.duplicateOf}相同（同帳戶、同一分鐘、同金額），不會加',
                        style: AppText.note.copyWith(
                          fontSize: 10.5,
                          color: AppColors.mid,
                        ),
                      ),
                    if (l.sameDayOf != null && !l.duplicate)
                      Text(
                        '⚠ 當天已經有相同金額：${l.sameDayOf}（只提醒，還是會匯入）',
                        style: AppText.note.copyWith(
                          fontSize: 10.5,
                          color: AppColors.mid,
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
                      ? const LedgerPill('重複', color: AppColors.mid)
                      : l.beforeStart
                      ? const LedgerPill('只看消費')
                      : const LedgerPill('會匯入', color: AppColors.ok),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「他給了」：只標記就好，或順便記錢進了哪個戶頭（要對帳的話選戶頭，
/// 那個戶頭的餘額才算得對）。回傳 `mark` 或 `deposit`（id＝帳戶）。
Future<LAction?> showSettleSheet(
  BuildContext context,
  LedgerBook book,
  LedgerTx tx,
) => _sheet(context, _Settle(book: book, tx: tx));

class _Settle extends StatelessWidget {
  const _Settle({required this.book, required this.tx});

  final LedgerBook book;
  final LedgerTx tx;

  @override
  Widget build(BuildContext context) {
    final left = tx.paidFor!.amount - book.repaidOf(tx.id);
    void pop(String k, [String? id]) => Navigator.pop(context, LAction(k, id));
    return _Frame(
      title: '${tx.paidFor!.people} 給了 ${lMoney(left)}',
      children: [
        _option(
          context,
          '✓',
          '標記他給了就好',
          '最常用。不管錢怎麼給的（現金、轉帳），這筆就標成對方已經給了',
          () => pop('mark'),
        ),
        const SizedBox(height: 4),
        Text('或是記下錢進了哪裡（要對帳的戶頭選這個，餘額才對得上）', style: AppText.note),
        const SizedBox(height: 8),
        for (final a in book.accounts.where((a) => !a.isCard))
          _option(
            context,
            a.type.emoji,
            '轉進 ${a.name}',
            '記一筆 ${lMoney(left)} 進這個帳戶，不算收入',
            () => pop('deposit', a.id),
          ),
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

/// 拆分表單的一份：品項名稱＋分類＋金額＋是不是幫人付、對方給了沒。
class _SplitRow {
  _SplitRow(
    this.category,
    this.amount,
    this.name,
    this.people,
    this.other, {
    this.forOther = false,
    this.settled = false,
  });

  String category;
  final TextEditingController amount;
  final TextEditingController name;

  /// 幫誰（標了幫人付才用）。
  final TextEditingController people;

  /// 這一份對方要給多少（空＝整份）。
  final TextEditingController other;
  bool forOther;
  bool settled;
}
