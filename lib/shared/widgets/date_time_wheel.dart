import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 年月日時分一頁選完的滾輪（2026-11-03 使用者：原本日期、時間分兩頁很難用）。
/// 五個滾輪並排，24 小時制，上面有「現在／今天／昨天」快捷，確定才回傳。
/// [monthOnly] 只選年、月（回傳那個月 1 號），不顯示日、時、分。
Future<DateTime?> showDateTimeWheel(
  BuildContext context,
  DateTime initial, {
  int minYear = 2020,
  int maxYear = 2035,
  bool monthOnly = false,
}) => showModalBottomSheet<DateTime>(
  context: context,
  useSafeArea: true,
  backgroundColor: const Color(0xFF1A1A27),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _Wheel(
    initial: initial,
    minYear: minYear,
    maxYear: maxYear,
    monthOnly: monthOnly,
  ),
);

class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.initial,
    required this.minYear,
    required this.maxYear,
    this.monthOnly = false,
  });

  final DateTime initial;
  final int minYear;
  final int maxYear;
  final bool monthOnly;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late int _y = widget.initial.year.clamp(widget.minYear, widget.maxYear);
  late int _m = widget.initial.month;
  late int _d = widget.initial.day;
  late int _h = widget.initial.hour;
  late int _mi = widget.initial.minute;

  late final _cy = FixedExtentScrollController(
    initialItem: _y - widget.minYear,
  );
  late final _cm = FixedExtentScrollController(initialItem: _m - 1);
  late final _cd = FixedExtentScrollController(initialItem: _d - 1);
  late final _ch = FixedExtentScrollController(initialItem: _h);
  late final _cmi = FixedExtentScrollController(initialItem: _mi);

  int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

  DateTime get _value =>
      widget.monthOnly ? DateTime(_y, _m) : DateTime(_y, _m, _d, _h, _mi);

  @override
  void dispose() {
    for (final c in [_cy, _cm, _cd, _ch, _cmi]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 年或月改了，日超過那個月的天數就拉回月底。
  void _fixDay() {
    final max = _daysIn(_y, _m);
    if (_d > max) {
      _d = max;
      _cd.jumpToItem(_d - 1);
    }
  }

  /// 把五個滾輪都轉到 [t]（快捷鍵用）。
  void _jump(DateTime t) {
    setState(() {
      _y = t.year.clamp(widget.minYear, widget.maxYear);
      _m = t.month;
      _d = t.day;
      _h = t.hour;
      _mi = t.minute;
    });
    _cy.jumpToItem(_y - widget.minYear);
    _cm.jumpToItem(_m - 1);
    _cd.jumpToItem(_d - 1);
    _ch.jumpToItem(_h);
    _cmi.jumpToItem(_mi);
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    double flex = 1,
  }) => Expanded(
    flex: (flex * 10).round(),
    child: CupertinoPicker(
      scrollController: controller,
      itemExtent: 36,
      magnification: 1.08,
      squeeze: 1.1,
      useMagnifier: true,
      selectionOverlay: Container(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(
              color: AppColors.glassEdge.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
      onSelectedItemChanged: onChanged,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(
              label(i),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _chip(String text, DateTime Function() to) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(label: Text(text), onPressed: () => _jump(to())),
  );

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final only = widget.monthOnly;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.glassEdge,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              only
                  ? '${v.year}/${v.month}'
                  : '${v.year}/${v.month}/${v.day} '
                        '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (only)
                    _chip('這個月', DateTime.now)
                  else ...[
                    _chip('現在', DateTime.now),
                    _chip('今天', () {
                      final n = DateTime.now();
                      return DateTime(n.year, n.month, n.day, _h, _mi);
                    }),
                    _chip('昨天', () {
                      final n = DateTime.now().subtract(
                        const Duration(days: 1),
                      );
                      return DateTime(n.year, n.month, n.day, _h, _mi);
                    }),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: Row(
                children: [
                  _wheel(
                    controller: _cy,
                    count: widget.maxYear - widget.minYear + 1,
                    label: (i) => '${widget.minYear + i}年',
                    flex: 1.3,
                    onChanged: (i) => setState(() {
                      _y = widget.minYear + i;
                      _fixDay();
                    }),
                  ),
                  _wheel(
                    controller: _cm,
                    count: 12,
                    label: (i) => '${i + 1}月',
                    onChanged: (i) => setState(() {
                      _m = i + 1;
                      _fixDay();
                    }),
                  ),
                  if (!only) ...[
                    _wheel(
                      controller: _cd,
                      count: 31,
                      label: (i) => '${i + 1}日',
                      onChanged: (i) => setState(() {
                        // 超過這個月天數的滾輪停在月底。
                        final max = _daysIn(_y, _m);
                        _d = i + 1 > max ? max : i + 1;
                        if (i + 1 > max) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_cd.hasClients) _cd.jumpToItem(_d - 1);
                          });
                        }
                      }),
                    ),
                    _wheel(
                      controller: _ch,
                      count: 24,
                      label: (i) => i.toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() => _h = i),
                    ),
                    const Text(
                      ':',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink2,
                      ),
                    ),
                    _wheel(
                      controller: _cmi,
                      count: 60,
                      label: (i) => i.toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() => _mi = i),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _value),
                    child: const Text('確定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
