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

/// 多／空這種二選一的大按鈕，選到的那邊用綠或紅底。
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

/// 數字放回輸入框用（編輯舊單時），整數不帶 `.0`、也不加千分位逗號。
String _numText(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// 損益輸入框（USDT 或 %）：左邊的 + / − 點一下切換賺賠（2026-10-10 使用者
/// 要求：不用另外選賺或賠，點符號切換正負）。
Widget _pnlField({
  required TextEditingController controller,
  required bool win,
  required VoidCallback onToggle,
  bool autofocus = false,
  String hint = '點左邊 + / − 切換賺賠',
  String suffix = 'USDT',
  String signKey = 'pnl-sign',
}) {
  final c = win ? tradeUp : tradeDown;
  return TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: _decimalOnly,
    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c),
    decoration: _input(
      hint,
      suffix: suffix,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 6, right: 6),
        child: Material(
          color: c.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey(signKey),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: Text(
                  win ? '+' : '−',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

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
///
/// 2026-10-10 使用者要求一打開就是直接打字輸入（等同按了選擇器右下角的
/// 鍵盤按鈕），不用先在月曆、時鐘上點；想看月曆／時鐘一樣能按圖示切回去。
/// 舊版長相存在 `design-history/2026-10-10_交易記一筆表單現況.html`。
Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: DateTime(2015),
    lastDate: now,
    initialEntryMode: DatePickerEntryMode.input,
    helpText: '輸入日期',
    fieldLabelText: '日期',
    errorFormatText: '日期格式不對',
    errorInvalidText: '不能是未來，也不能早於 2015 年',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    initialEntryMode: TimePickerEntryMode.input,
    // 24 小時制，跟 App 裡顯示的 21:40 一致；不然繁中預設 12 小時制，
    // 打 9 還要另外選上午／下午，下午打開會被當成 21 點。
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
    helpText: '輸入時間',
    hourLabelText: '時',
    minuteLabelText: '分',
    errorInvalidText: '時間不對',
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

/// 2026-10-10 使用者要求整個交易功能槓桿最高 18x（原本 20x）。
const _maxLeverage = 18.0;

/// 槓桿拉桿，照幣安合約的樣子（2026-10-08 使用者要求：改跟幣安一樣的
/// 拉桿）：上面一格大大的倍數，下面拉桿 1x–18x，刻度
/// 1／5／10／15／18x 點了直接跳過去。超過 10x 拉桿跟數字變紅，提醒高槓桿。
/// 2026-10-10 使用者要求只留拉桿，拿掉倍數兩邊的 −／＋ 按鈕。
class LeverageSlider extends StatelessWidget {
  const LeverageSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const _binanceYellow = Color(0xFFF0B90B);
  static const _ticks = [1, 5, 10, 15, 18];

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(1.0, _maxLeverage);
    final hi = v > 10;
    final color = hi ? tradeDown : _binanceYellow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3D)),
          ),
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

/// 編輯已經記下的一單（2026-10-10 使用者要求交易紀錄能編輯）：同一張表單，
/// 欄位先填好原本的值；持倉中的也能直接打開「已經平倉了」補上結果，
/// 已平倉的關掉就變回持倉中。
Future<TradeDraft?> showEditTradeSheet(
  BuildContext context, {
  required TradeEntry trade,
}) => _sheet<TradeDraft>(context, _NewTradeSheet(initial: trade));

class _NewTradeSheet extends StatefulWidget {
  const _NewTradeSheet({this.day, this.initial});

  final DateTime? day;
  final TradeEntry? initial;

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
  final _pctCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  /// 補記已平倉的單時，本金預設由「損益 ÷ 盈虧 %」自動算（2026-10-10 使用者
  /// 要求：幣安歷史紀錄看得到 % 跟損益，本金反而要自己算）。使用者自己改過
  /// 本金就不再自動蓋掉，按「用 % 重新算」才回到自動。
  bool _marginManual = false;

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
    final t = widget.initial;
    if (t != null) {
      if (_symbols.contains(t.symbol)) {
        _symbol = t.symbol;
      } else {
        _customSymbol = true;
        _symbolCtrl.text = t.symbol;
      }
      _isLong = t.isLong;
      _leverage = t.leverage.clamp(1.0, _maxLeverage);
      _marginCtrl.text = _numText(t.margin);
      _openedAt = t.openedAt;
      _closed = !t.isOpen;
      _closedAt = t.closedAt ?? t.openedAt;
      if (t.pnl != null) {
        _win = t.pnl! >= 0;
        _pnlCtrl.text = _numText(t.pnl!.abs());
        if (t.pnlPercent != null) {
          _pctCtrl.text = _numText(_round2(t.pnlPercent!.abs()));
        }
      }
      // 編輯舊單：原本存的本金是準的，% 是四捨五入過的，不要拿 % 回推蓋掉。
      _marginManual = true;
      _noteCtrl.text = t.note ?? '';
    }
    _pnlCtrl.addListener(_autoMargin);
    _pctCtrl.addListener(_autoMargin);
    for (final c in [_symbolCtrl, _marginCtrl, _pnlCtrl, _pctCtrl, _noteCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_symbolCtrl, _marginCtrl, _pnlCtrl, _pctCtrl, _noteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  double? get _pct => double.tryParse(_pctCtrl.text);

  /// 損益 ÷ 盈虧 %，兩個都填了而且 % 不是 0 才算得出來。
  double? get _derivedMargin {
    final p = _pnlAbs, pct = _pct;
    if (p == null || pct == null || pct == 0) return null;
    return _round2(p / pct * 100);
  }

  void _autoMargin() {
    if (!_closed || _marginManual) return;
    final m = _derivedMargin;
    final text = m == null ? '' : _numText(m);
    if (_marginCtrl.text != text) _marginCtrl.text = text;
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
        TextSpan(text: _closed ? '填完 % 跟損益（或本金）之後，這裡會算出' : '填本金之後，這裡會算出'),
        _strong('倉位大小'),
        const TextSpan(text: '和'),
        _strong('價格反向走多少 % 本金就歸零'),
      ]);
    } else {
      final liq = 100 / lev;
      if (_closed && !_marginManual && _pct != null) {
        calc.addAll([
          TextSpan(text: '本金＝${fmtAmount(_pnlAbs!)} ÷ ${_numText(_pct!)}%＝'),
          _strong('${fmtAmount(m)} USDT'),
          const TextSpan(text: '\n'),
        ]);
      }
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

    final editing = widget.initial != null;
    return _SheetFrame(
      title: editing ? '編輯這一單' : (_closed ? '補記一單' : '記一筆開倉'),
      footer: FilledButton(
        onPressed: _valid ? _save : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          editing
              ? (_closed ? '儲存修改' : '儲存修改（持倉中）')
              : (_closed ? '儲存' : '儲存（持倉中）'),
        ),
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
              autofocus: widget.initial == null,
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
        SwitchListTile(
          value: _closed,
          onChanged: (v) => setState(() {
            _closed = v;
            _autoMargin();
          }),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            widget.initial == null ? '已經平倉了（補記以前的單）' : '已經平倉了',
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ),
        if (_closed) ...[
          _fieldLabel('盈虧 %', trailing: '本金報酬率，幣安紀錄上那個 %'),
          _pnlField(
            controller: _pctCtrl,
            win: _win,
            onToggle: () => setState(() => _win = !_win),
            hint: '例如 12.5',
            suffix: '%',
            signKey: 'pct-sign',
          ),
          _fieldLabel('已實現損益', trailing: '記在平倉那天 ${fmtDay(_closedAt)}'),
          _pnlField(
            controller: _pnlCtrl,
            win: _win,
            onToggle: () => setState(() => _win = !_win),
          ),
        ],
        _fieldLabel(
          _closed && !_marginManual ? '本金（自動算）' : '本金（保證金）',
          trailing: _closed && !_marginManual ? '＝損益 ÷ 盈虧 %，可以自己改' : null,
        ),
        TextField(
          controller: _marginCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimalOnly,
          onChanged: (_) => setState(() => _marginManual = true),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          decoration: _input(
            _closed && !_marginManual ? '填完 % 跟損益就會算出來' : '例如 400',
            suffix: 'USDT',
          ),
        ),
        if (_closed &&
            _marginManual &&
            _derivedMargin != null &&
            _derivedMargin != _margin)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _marginManual = false;
                _autoMargin();
              }),
              child: Text('用 % 重新算（${fmtAmount(_derivedMargin!)}）'),
            ),
          ),
        _calcBox(calc),
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
/// 累計」——平倉時間改到別的月，就算那個月。按「編輯開倉資料」會先呼叫
/// [onEdit] 再關掉表單（回傳 null），由呼叫端接著開編輯表單。
Future<({double pnl, DateTime at})?> showCloseTradeSheet(
  BuildContext context, {
  required TradeEntry trade,
  required double Function(DateTime month) monthTotalOf,
  required double? Function(DateTime month) capitalOf,
  required VoidCallback onEdit,
}) => _sheet<({double pnl, DateTime at})>(
  context,
  _CloseTradeSheet(
    trade: trade,
    monthTotalOf: monthTotalOf,
    capitalOf: capitalOf,
    onEdit: onEdit,
  ),
);

class _CloseTradeSheet extends StatefulWidget {
  const _CloseTradeSheet({
    required this.trade,
    required this.monthTotalOf,
    required this.capitalOf,
    required this.onEdit,
  });

  final TradeEntry trade;
  final double Function(DateTime month) monthTotalOf;
  final double? Function(DateTime month) capitalOf;
  final VoidCallback onEdit;

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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              widget.onEdit();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('編輯開倉資料'),
          ),
        ),
        _fieldLabel('已實現損益', trailing: '手續費直接扣在裡面'),
        _pnlField(
          controller: _ctrl,
          win: _win,
          onToggle: () => setState(() => _win = !_win),
          autofocus: true,
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

/// 回傳 true＝使用者確認刪除了。按「編輯」會先呼叫 [onEdit] 再關掉明細
/// （回傳 false），由呼叫端接著開編輯表單。
Future<bool> showTradeDetailSheet(
  BuildContext context, {
  required TradeEntry trade,
  required VoidCallback onEdit,
}) async {
  final deleted = await _sheet<bool>(
    context,
    _TradeDetailSheet(trade: trade, onEdit: onEdit),
  );
  return deleted ?? false;
}

class _TradeDetailSheet extends StatelessWidget {
  const _TradeDetailSheet({required this.trade, required this.onEdit});

  final TradeEntry trade;
  final VoidCallback onEdit;

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
              onPressed: () {
                onEdit();
                Navigator.pop(context, false);
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('編輯'),
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
        if (t.note != null) kv('備註', t.note!),
      ],
    );
  }
}
