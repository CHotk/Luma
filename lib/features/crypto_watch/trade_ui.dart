import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/trade_entry.dart';
import '../../shared/widgets/app_confirm_dialog.dart';

/// 交易&自律各頁共用的小東西（只給這個功能用，不放 shared）：數字格式、
/// 漲跌顏色、交易卡片、記一筆／平倉／明細三個底部表單。
///
/// 顏色是**綠漲紅跌**（2026-10-08 使用者指定：賺錢綠、賠錢紅）。

const tradeUp = AppColors.ok;
const tradeDown = Color(0xFFFF7A70);

Color pnlColor(double? v) => v == null || v == 0
    ? AppColors.ink2
    : v > 0
    ? tradeUp
    : tradeDown;

String _num(double v) {
  final abs = v.abs();
  final whole = abs == abs.roundToDouble();
  final s = whole ? abs.round().toString() : abs.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts.length > 1
      ? '$intPart.${parts[1].replaceFirst(RegExp(r'0+$'), '')}'
      : intPart;
}

/// 「+246」「−120」「0」。
String fmtPnl(double v) =>
    '${v > 0
        ? '+'
        : v < 0
        ? '−'
        : ''}${_num(v)}';

/// 不帶正負號的金額，例如本金 1,500。
String fmtAmount(double v) => _num(v);

String fmtPct(double v) =>
    '${v > 0
        ? '+'
        : v < 0
        ? '−'
        : ''}${v.abs().toStringAsFixed(1)}%';

String fmtLev(double v) =>
    '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}x';

const weekdayZh = ['一', '二', '三', '四', '五', '六', '日'];

String fmtDay(DateTime d) => '${d.month}/${d.day}（${weekdayZh[d.weekday - 1]}）';

String fmtHm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String fmtHold(Duration d) {
  final h = d.inHours;
  if (h < 1) return '${d.inMinutes.clamp(1, 59)} 分鐘';
  if (h < 24) return '$h 小時';
  return '${h ~/ 24} 天${h % 24 == 0 ? '' : ' ${h % 24} 小時'}';
}

/// 槓桿小標籤：超過 10 倍用紅色提醒。
class LeverageBadge extends StatelessWidget {
  const LeverageBadge(this.leverage, {super.key});

  final double leverage;

  @override
  Widget build(BuildContext context) {
    final hi = leverage > 10;
    final c = hi ? tradeDown : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        fmtLev(leverage),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}

Widget directionLabel(bool isLong) => Text(
  isLong ? '多 ▲' : '空 ▼',
  style: TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: isLong ? tradeUp : tradeDown,
  ),
);

/// 一單的卡片（交易日誌、某一天、持倉中清單共用）：左邊色條（綠賺紅賠、
/// 黃色持倉中）、第一行幣種方向槓桿＋損益、第二行本金倉位持倉時間。
class TradeCard extends StatelessWidget {
  const TradeCard({super.key, required this.trade, required this.onTap});

  final TradeEntry trade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final bar = t.isOpen ? AppColors.mid : pnlColor(t.pnl);
    final hold = (t.closedAt ?? DateTime.now()).difference(t.openedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: bar, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    directionLabel(t.isLong),
                    const SizedBox(width: 6),
                    LeverageBadge(t.leverage),
                    const Spacer(),
                    const SizedBox(width: 8),
                    if (t.isOpen)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mid.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          '持倉中・點一下平倉',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.mid,
                          ),
                        ),
                      )
                    else
                      // 金額很大時整組縮小，不擠爆左邊的幣種跟槓桿。
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            children: [
                              Text(
                                fmtPnl(t.pnl!),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: pnlColor(t.pnl),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                fmtPct(t.pnlPercent!),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: pnlColor(t.pnl),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '本金 ${fmtAmount(t.margin)}・倉位 ${fmtAmount(t.positionSize)}'
                  '・${t.isOpen ? '已持倉' : '持倉'} ${fmtHold(hold)}'
                  '${t.note == null ? '' : '・${t.note}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.note.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 底部表單共用 ──────────────────────────────────────────

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: child,
      ),
    );

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    required this.footer,
  });

  final String title;
  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
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
            padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
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
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
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
}

Widget _fieldLabel(String text, {String? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Row(
    children: [
      Text(text, style: AppText.note),
      const Spacer(),
      if (trailing != null)
        Text(trailing, style: AppText.note.copyWith(color: AppColors.ink3)),
    ],
  ),
);

Widget _choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
  label: Text(label),
  selected: selected,
  onSelected: (_) => onTap(),
  showCheckmark: false,
  selectedColor: AppColors.accentSolid.withValues(alpha: 0.4),
  side: BorderSide(
    color: selected ? AppColors.accent : const Color(0xFF2A2A3D),
  ),
  labelStyle: TextStyle(
    fontSize: 13,
    color: selected ? Colors.white : AppColors.ink2,
  ),
);

/// 多／空、賺／賠這種二選一的大按鈕，選到的那邊用綠或紅底。
Widget _twoWay({
  required String left,
  required String right,
  required bool leftSelected,
  required ValueChanged<bool> onChanged,
}) {
  Widget side(String label, bool isLeft) {
    final on = leftSelected == isLeft;
    final c = isLeft ? tradeUp : tradeDown;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(isLeft),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: on ? c : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFF161622),
      border: Border.all(color: const Color(0xFF2A2A3D)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [side(left, true), side(right, false)]),
  );
}

InputDecoration _input(String hint, {String? suffix, Widget? prefix}) =>
    InputDecoration(
      hintText: hint,
      suffixText: suffix,
      prefixIcon: prefix,
      prefixIconConstraints: const BoxConstraints(minWidth: 34),
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
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    );

final _decimalOnly = [
  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}')),
];

Widget _calcBox(List<InlineSpan> spans, {Color? border}) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.03),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: border ?? const Color(0xFF2A2A3D)),
  ),
  child: Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.7),
      children: spans,
    ),
  ),
);

TextSpan _strong(String s, {Color color = AppColors.ink, double? size}) =>
    TextSpan(
      text: s,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: size,
      ),
    );

/// 選日期再選時間（補記舊交易用，2026-10-08 使用者要求開倉、平倉時間都能
/// 自己填）。不能選未來；取消回傳 null。
Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: DateTime(2015),
    lastDate: now,
    helpText: '選日期',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: '選時間',
  );
  if (time == null) return null;
  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return picked.isAfter(now) ? now : picked;
}

/// 「開倉時間 10/3（六）21:40 ›」這種點了會跳日期時間選擇器的一列。
Widget _timeField(String label, DateTime value, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Material(
    color: const Color(0xFF161622),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3D)),
        ),
        child: Row(
          children: [
            Text(label, style: AppText.bodyDim),
            const Spacer(),
            Text(
              '${value.year == DateTime.now().year ? '' : '${value.year}/'}'
              '${fmtDay(value)} ${fmtHm(value)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.edit_calendar_outlined,
              size: 17,
              color: AppColors.ink2,
            ),
          ],
        ),
      ),
    ),
  ),
);

const _maxLeverage = 20.0;

/// 槓桿拉桿，照幣安合約的樣子（2026-10-08 使用者要求：改跟幣安一樣的
/// 拉桿，最高 20x）：上面一格大大的倍數、左右 −／＋ 一次調 1 倍，下面
/// 拉桿 1x–20x，刻度 1／5／10／15／20x 點了直接跳過去。超過 10x 拉桿
/// 跟數字變紅，提醒高槓桿。
class LeverageSlider extends StatelessWidget {
  const LeverageSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const _binanceYellow = Color(0xFFF0B90B);
  static const _ticks = [1, 5, 10, 15, 20];

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(1.0, _maxLeverage);
    final hi = v > 10;
    final color = hi ? tradeDown : _binanceYellow;
    Widget step(IconData icon, double next) => IconButton(
      onPressed: next < 1 || next > _maxLeverage ? null : () => onChanged(next),
      icon: Icon(icon, size: 20),
      color: AppColors.ink,
      disabledColor: AppColors.ink3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3D)),
          ),
          child: Row(
            children: [
              step(Icons.remove_rounded, v - 1),
              Expanded(
                child: Text(
                  fmtLev(v),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: hi ? tradeDown : AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              step(Icons.add_rounded, v + 1),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: const Color(0xFF2A2A3D),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.15),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: v,
            min: 1,
            max: _maxLeverage,
            divisions: (_maxLeverage - 1).round(),
            onChanged: (x) => onChanged(x.roundToDouble()),
          ),
        ),
        // 刻度：跟拉桿兩端對齊（拉桿左右各內縮 overlay 半徑 16）。
        SizedBox(
          height: 22,
          child: LayoutBuilder(
            builder: (_, c) {
              const inset = 16.0;
              final w = c.maxWidth - inset * 2;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final t in _ticks)
                    Positioned(
                      left: inset + (t - 1) / (_maxLeverage - 1) * w - 18,
                      width: 36,
                      top: 0,
                      child: InkWell(
                        onTap: () => onChanged(t.toDouble()),
                        borderRadius: BorderRadius.circular(6),
                        child: Text(
                          '${t}x',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: v.round() == t
                                ? FontWeight.w800
                                : FontWeight.w400,
                            color: v.round() == t
                                ? (t > 10 ? tradeDown : _binanceYellow)
                                : AppColors.ink3,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── 記一筆（開倉，或補記一整單）────────────────────────────

/// 記一筆表單填完的結果，由呼叫端存進 repository。
class TradeDraft {
  const TradeDraft({
    required this.symbol,
    required this.isLong,
    required this.leverage,
    required this.margin,
    required this.openedAt,
    this.closedAt,
    this.pnl,
    this.note,
  });

  final String symbol;
  final bool isLong;
  final double leverage;
  final double margin;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double? pnl;
  final String? note;
}

/// [day] 有給（從月曆某一天「替這天補記」進來）時，日期用那天、預設打開
/// 「已經平倉了」。
Future<TradeDraft?> showNewTradeSheet(BuildContext context, {DateTime? day}) =>
    _sheet<TradeDraft>(context, _NewTradeSheet(day: day));

class _NewTradeSheet extends StatefulWidget {
  const _NewTradeSheet({this.day});

  final DateTime? day;

  @override
  State<_NewTradeSheet> createState() => _NewTradeSheetState();
}

class _NewTradeSheetState extends State<_NewTradeSheet> {
  static const _symbols = ['BTC', 'ETH', 'SOL'];

  String _symbol = 'BTC';
  bool _customSymbol = false;
  bool _isLong = true;
  double _leverage = 10;
  late bool _closed;
  bool _win = true;
  late DateTime _openedAt;
  late DateTime _closedAt;

  final _symbolCtrl = TextEditingController();
  final _marginCtrl = TextEditingController();
  final _pnlCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.day;
    final isPast =
        d != null &&
        DateTime(
          d.year,
          d.month,
          d.day,
        ).isBefore(DateTime(now.year, now.month, now.day));
    final at = d == null
        ? now
        : DateTime(d.year, d.month, d.day, now.hour, now.minute);
    _openedAt = at.isAfter(now) ? now : at;
    _closedAt = _openedAt;
    _closed = isPast;
    for (final c in [_symbolCtrl, _marginCtrl, _pnlCtrl, _noteCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_symbolCtrl, _marginCtrl, _pnlCtrl, _noteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _sym =>
      _customSymbol ? _symbolCtrl.text.trim().toUpperCase() : _symbol;

  double? get _lev => _leverage;

  double? get _margin => double.tryParse(_marginCtrl.text);

  double? get _pnlAbs => double.tryParse(_pnlCtrl.text);

  bool get _valid {
    final lev = _lev, m = _margin;
    if (_sym.isEmpty || lev == null || lev < 1 || m == null || m <= 0) {
      return false;
    }
    return !_closed || (_pnlAbs != null && !_closedAt.isBefore(_openedAt));
  }

  void _save() {
    final pnl = _closed ? (_win ? _pnlAbs! : -_pnlAbs!) : null;
    Navigator.pop(
      context,
      TradeDraft(
        symbol: _sym,
        isLong: _isLong,
        leverage: _lev!,
        margin: _margin!,
        openedAt: _openedAt,
        closedAt: _closed ? _closedAt : null,
        pnl: pnl,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lev = _lev, m = _margin;
    final calc = <InlineSpan>[];
    if (lev == null || m == null || m <= 0 || lev < 1) {
      calc.addAll([
        const TextSpan(text: '填本金之後，這裡會算出'),
        _strong('倉位大小'),
        const TextSpan(text: '和'),
        _strong('價格反向走多少 % 本金就歸零'),
      ]);
    } else {
      final liq = 100 / lev;
      calc.addAll([
        TextSpan(text: '倉位大小＝${fmtAmount(m)} × ${fmtLev(lev)}＝'),
        _strong('${fmtAmount(m * lev)} USDT'),
        TextSpan(text: '\n價格${_isLong ? '下跌' : '上漲'} '),
        _strong(
          '${liq.toStringAsFixed(liq < 10 ? 1 : 0)}%',
          color: liq <= 5 ? tradeDown : AppColors.ink,
        ),
        TextSpan(text: ' 本金就歸零${liq <= 5 ? '　⚠ 很容易爆倉' : ''}'),
      ]);
      if (_closed && _pnlAbs != null) {
        final v = _win ? _pnlAbs! : -_pnlAbs!;
        calc.addAll([
          const TextSpan(text: '\n本金報酬率 '),
          _strong(fmtPct(v / m * 100), color: pnlColor(v)),
        ]);
      }
    }

    return _SheetFrame(
      title: _closed ? '補記一單' : '記一筆開倉',
      footer: FilledButton(
        onPressed: _valid ? _save : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(_closed ? '儲存' : '儲存（持倉中）'),
      ),
      children: [
        _fieldLabel('幣種'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _symbols)
              _choice(
                s,
                !_customSymbol && _symbol == s,
                () => setState(() {
                  _symbol = s;
                  _customSymbol = false;
                }),
              ),
            _choice(
              '其他',
              _customSymbol,
              () => setState(() => _customSymbol = true),
            ),
          ],
        ),
        if (_customSymbol)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _symbolCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: _input('幣種代號，例如 DOGE'),
            ),
          ),
        _fieldLabel('方向'),
        _twoWay(
          left: '多 ▲',
          right: '空 ▼',
          leftSelected: _isLong,
          onChanged: (v) => setState(() => _isLong = v),
        ),
        _fieldLabel('槓桿', trailing: '最高 ${_maxLeverage.round()}x'),
        LeverageSlider(
          value: _leverage,
          onChanged: (v) => setState(() => _leverage = v),
        ),
        _fieldLabel('本金（保證金）'),
        TextField(
          controller: _marginCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimalOnly,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          decoration: _input('例如 400', suffix: 'USDT'),
        ),
        _calcBox(calc),
        const SizedBox(height: 6),
        SwitchListTile(
          value: _closed,
          onChanged: (v) => setState(() => _closed = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            '已經平倉了（補記一整單）',
            style: TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ),
        _fieldLabel('時間', trailing: '補記以前的單可以改'),
        _timeField('開倉時間', _openedAt, () async {
          final t = await _pickDateTime(context, _openedAt);
          if (t == null || !mounted) return;
          setState(() {
            _openedAt = t;
            if (_closedAt.isBefore(t)) _closedAt = t;
          });
        }),
        if (_closed) ...[
          _timeField('平倉時間', _closedAt, () async {
            final t = await _pickDateTime(context, _closedAt);
            if (t != null && mounted) setState(() => _closedAt = t);
          }),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _closedAt.isBefore(_openedAt)
                  ? '⚠ 平倉時間比開倉早，改一下'
                  : '持倉 ${fmtHold(_closedAt.difference(_openedAt))}',
              style: AppText.note.copyWith(
                color: _closedAt.isBefore(_openedAt)
                    ? tradeDown
                    : AppColors.ink3,
              ),
            ),
          ),
        ],
        if (_closed) ...[
          _fieldLabel('結果'),
          _twoWay(
            left: '賺',
            right: '賠',
            leftSelected: _win,
            onChanged: (v) => setState(() => _win = v),
          ),
          _fieldLabel('已實現損益', trailing: '記在平倉那天 ${fmtDay(_closedAt)}'),
          TextField(
            controller: _pnlCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimalOnly,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _win ? tradeUp : tradeDown,
            ),
            decoration: _input(
              '賺或賠多少',
              suffix: 'USDT',
              prefix: Center(
                widthFactor: 1,
                child: Text(
                  _win ? '+' : '−',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _win ? tradeUp : tradeDown,
                  ),
                ),
              ),
            ),
          ),
        ],
        _fieldLabel('備註（選填）'),
        TextField(controller: _noteCtrl, decoration: _input('為什麼開這單？停損設哪？')),
      ],
    );
  }
}

// ── 平倉結算 ──────────────────────────────────────────────

/// 回傳已實現損益（賠是負數）跟平倉時間，取消回傳 null。平倉時間預設
/// 現在，補記以前的單可以改（2026-10-08 使用者要求）。[monthTotalOf]、
/// [capitalOf] 給某個月目前的累計跟月初資金，用來即時算「結算後那個月
/// 累計」——平倉時間改到別的月，就算那個月。
Future<({double pnl, DateTime at})?> showCloseTradeSheet(
  BuildContext context, {
  required TradeEntry trade,
  required double Function(DateTime month) monthTotalOf,
  required double? Function(DateTime month) capitalOf,
}) => _sheet<({double pnl, DateTime at})>(
  context,
  _CloseTradeSheet(
    trade: trade,
    monthTotalOf: monthTotalOf,
    capitalOf: capitalOf,
  ),
);

class _CloseTradeSheet extends StatefulWidget {
  const _CloseTradeSheet({
    required this.trade,
    required this.monthTotalOf,
    required this.capitalOf,
  });

  final TradeEntry trade;
  final double Function(DateTime month) monthTotalOf;
  final double? Function(DateTime month) capitalOf;

  @override
  State<_CloseTradeSheet> createState() => _CloseTradeSheetState();
}

class _CloseTradeSheetState extends State<_CloseTradeSheet> {
  bool _win = true;
  DateTime _at = DateTime.now();
  final _ctrl = TextEditingController();

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
    final t = widget.trade;
    final abs = double.tryParse(_ctrl.text);
    final v = abs == null ? null : (_win ? abs : -abs);
    final calc = <InlineSpan>[];
    if (v == null) {
      calc.addAll([
        const TextSpan(text: '填完會算出'),
        _strong('本金報酬率'),
        const TextSpan(text: '和'),
        _strong('這個月累計'),
      ]);
    } else {
      final after = widget.monthTotalOf(_at) + v;
      final capital = widget.capitalOf(_at);
      calc.addAll([
        const TextSpan(text: '本金報酬率 '),
        _strong(fmtPct(v / t.margin * 100), color: pnlColor(v), size: 15),
        TextSpan(text: '\n${_at.month} 月累計會變成 '),
        _strong(
          '${fmtPnl(after)} USDT'
          '${capital == null ? '' : '（${fmtPct(after / capital * 100)}）'}',
          color: pnlColor(after),
        ),
      ]);
      if (v < 0 && -v > t.margin) {
        calc.add(
          const TextSpan(
            text: '\n⚠ 賠的比本金還多？確認一下數字',
            style: TextStyle(color: tradeDown),
          ),
        );
      }
    }
    return _SheetFrame(
      title: '平倉結算',
      footer: FilledButton(
        onPressed: v == null || _at.isBefore(t.openedAt)
            ? null
            : () => Navigator.pop(context, (pnl: v, at: _at)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(_isToday(_at) ? '結算（記在今天）' : '結算（記在 ${fmtDay(_at)}）'),
      ),
      children: [
        TradeCard(trade: t, onTap: () {}),
        _fieldLabel('結果'),
        _twoWay(
          left: '賺',
          right: '賠',
          leftSelected: _win,
          onChanged: (w) => setState(() => _win = w),
        ),
        _fieldLabel('已實現損益', trailing: '手續費直接扣在裡面'),
        TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimalOnly,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _win ? tradeUp : tradeDown,
          ),
          decoration: _input(
            '賺或賠多少',
            suffix: 'USDT',
            prefix: Center(
              widthFactor: 1,
              child: Text(
                _win ? '+' : '−',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _win ? tradeUp : tradeDown,
                ),
              ),
            ),
          ),
        ),
        _timeField('平倉時間', _at, () async {
          final p = await _pickDateTime(context, _at);
          if (p != null && mounted) setState(() => _at = p);
        }),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            _at.isBefore(t.openedAt)
                ? '⚠ 平倉時間比開倉（${fmtDay(t.openedAt)} ${fmtHm(t.openedAt)}）早，改一下'
                : '持倉 ${fmtHold(_at.difference(t.openedAt))}・補記以前平倉的單可以改時間',
            style: AppText.note.copyWith(
              color: _at.isBefore(t.openedAt) ? tradeDown : AppColors.ink3,
            ),
          ),
        ),
        _calcBox(calc),
      ],
    );
  }

  static bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}

// ── 已平倉那一單的明細 ────────────────────────────────────

/// 回傳 true＝使用者確認刪除了。
Future<bool> showTradeDetailSheet(
  BuildContext context, {
  required TradeEntry trade,
  required int watchCountThatDay,
}) async {
  final deleted = await _sheet<bool>(
    context,
    _TradeDetailSheet(trade: trade, watchCount: watchCountThatDay),
  );
  return deleted ?? false;
}

class _TradeDetailSheet extends StatelessWidget {
  const _TradeDetailSheet({required this.trade, required this.watchCount});

  final TradeEntry trade;
  final int watchCount;

  @override
  Widget build(BuildContext context) {
    final t = trade;
    Widget kv(String k, String v, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A3D))),
      ),
      child: Row(
        children: [
          Text(k, style: AppText.bodyDim),
          const Spacer(),
          Text(
            v,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
    return _SheetFrame(
      title: '這一單',
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final ok = await showAppConfirmDialog(
                  context,
                  title: '刪除這一單？',
                  message:
                      '${fmtDay(t.closedAt!)} ${t.symbol} ${fmtPnl(t.pnl!)} USDT，'
                      '刪掉之後月曆和月報會重算。',
                  confirmLabel: '刪除',
                );
                if (ok && context.mounted) Navigator.pop(context, true);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: tradeDown,
                side: BorderSide(color: tradeDown.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('刪除'),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('關閉'),
            ),
          ),
        ],
      ),
      children: [
        TradeCard(trade: t, onTap: () {}),
        const SizedBox(height: 6),
        kv('本金', '${fmtAmount(t.margin)} USDT'),
        kv('倉位大小', '${fmtAmount(t.positionSize)} USDT'),
        kv('開倉', '${fmtDay(t.openedAt)} ${fmtHm(t.openedAt)}'),
        kv('平倉', '${fmtDay(t.closedAt!)} ${fmtHm(t.closedAt!)}'),
        kv('持倉時間', fmtHold(t.closedAt!.difference(t.openedAt))),
        kv(
          '平倉那天看盤',
          '$watchCount 次',
          color: watchCount > 8 ? AppColors.mid : null,
        ),
        if (t.note != null) kv('備註', t.note!),
      ],
    );
  }
}
