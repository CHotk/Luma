import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../data/services/youtube_api_service.dart';

/// 頻道頁影片的時長篩選（2026-10-06 使用者要求，挑了設計稿第 03 版
/// 「類型列尾端加一顆時長 ▾」，見
/// `design-history/已選擇完成/2026-10-06_影片時長篩選五種設計.html`）。
///
/// 選項：不限／2 分內／2–6 分／6–20 分／自訂（使用者定的，不要「20 分
/// 以上」）。交界**上限算進去**、算到秒：2:00 算「2 分內」、6:00 算
/// 「2–6 分」、6:01 起算「6–20 分」。自訂用整數分鐘，0 到 [ceilingMinutes]，
/// 拉到 [ceilingMinutes] 代表「40+」不設上限；自訂也套同一個規則（大於下限、
/// 小於等於上限），所以自訂 6–20 跟預設 6–20 完全一樣。
/// 時長沒抓到的影片只在「不限」出現。
enum YtDurationPreset { any, under2, from2to6, from6to20, custom }

class YtDurationFilter {
  const YtDurationFilter._(this.preset, this.minMinutes, this.maxMinutes);

  const YtDurationFilter.any()
    : this._(YtDurationPreset.any, 0, ceilingMinutes);

  factory YtDurationFilter.preset(YtDurationPreset p) => switch (p) {
    YtDurationPreset.any => const YtDurationFilter.any(),
    YtDurationPreset.under2 => const YtDurationFilter._(
      YtDurationPreset.under2,
      0,
      2,
    ),
    YtDurationPreset.from2to6 => const YtDurationFilter._(
      YtDurationPreset.from2to6,
      2,
      6,
    ),
    YtDurationPreset.from6to20 => const YtDurationFilter._(
      YtDurationPreset.from6to20,
      6,
      20,
    ),
    YtDurationPreset.custom => const YtDurationFilter._(
      YtDurationPreset.custom,
      0,
      ceilingMinutes,
    ),
  };

  const YtDurationFilter.custom(int min, int max)
    : this._(YtDurationPreset.custom, min, max);

  /// 自訂拉桿的最右邊；拉到這裡＝「40+」，不設上限（2026-10-06 使用者
  /// 定的，這樣拉桿正中間剛好是 20 分）。
  static const ceilingMinutes = 40;

  final YtDurationPreset preset;
  final int minMinutes;
  final int maxMinutes;

  bool get isAny => preset == YtDurationPreset.any;

  bool matches(YoutubeVideo v) {
    if (isAny) return true;
    // 自訂拉成 0–40+ 等於沒限制。
    if (minMinutes <= 0 && maxMinutes >= YtDurationFilter.ceilingMinutes) {
      return true;
    }
    final d = v.duration;
    if (d == null || d.inSeconds <= 0) return false;
    final s = d.inSeconds;
    if (minMinutes > 0 && s <= minMinutes * 60) return false;
    if (maxMinutes < YtDurationFilter.ceilingMinutes && s > maxMinutes * 60) {
      return false;
    }
    return true;
  }

  /// 膠囊上顯示的字。
  String get chipLabel => isAny ? '時長' : rangeLabel;

  String get rangeLabel => switch (preset) {
    YtDurationPreset.any => '不限',
    YtDurationPreset.under2 => '2 分內',
    YtDurationPreset.from2to6 => '2–6 分',
    YtDurationPreset.from6to20 => '6–20 分',
    YtDurationPreset.custom => customLabel(minMinutes, maxMinutes),
  };

  static String customLabel(int min, int max) {
    final top = max >= YtDurationFilter.ceilingMinutes ? '$max+' : '$max';
    if (min <= 0) {
      return max >= YtDurationFilter.ceilingMinutes ? '不限' : '$max 分內';
    }
    return '$min–$top 分';
  }
}

/// 類型列尾端那顆「⏱ 時長 ▾」。選了條件就亮起來、改寫成目前的區間。
class YtDurationChip extends StatelessWidget {
  const YtDurationChip({
    super.key,
    required this.filter,
    required this.countOf,
    required this.onChanged,
  });

  final YtDurationFilter filter;

  /// 某個條件下目前已載入的影片有幾部（小選單每個選項旁的數字）。
  final int Function(YtDurationFilter) countOf;
  final ValueChanged<YtDurationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = !filter.isAny;
    const color = AppColors.accentSolid;
    return Builder(
      builder: (chipContext) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          final box = chipContext.findRenderObject()! as RenderBox;
          final anchor = box.localToGlobal(Offset.zero) & box.size;
          _showDurationMenu(
            context,
            anchor: anchor,
            initial: filter,
            countOf: countOf,
            onChanged: onChanged,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: on ? color.withValues(alpha: 0.22) : AppColors.glassFill,
            border: Border.all(color: on ? color : AppColors.glassEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: on ? AppColors.ink : AppColors.ink2,
              ),
              const SizedBox(width: 4),
              Text(
                filter.chipLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.ink : AppColors.ink2,
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 16,
                color: on ? AppColors.ink : AppColors.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 膠囊下方跳出的小選單（深色，跟長按泡泡選單同一套顏色）。選預設區間
/// 選完就收；選「自訂」展開拉桿，拉的當下清單就跟著變，點外面收起。
Future<void> _showDurationMenu(
  BuildContext context, {
  required Rect anchor,
  required YtDurationFilter initial,
  required int Function(YtDurationFilter) countOf,
  required ValueChanged<YtDurationFilter> onChanged,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '關閉時長選單',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, _) => _DurationMenu(
      anchor: anchor,
      initial: initial,
      countOf: countOf,
      onChanged: onChanged,
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _DurationMenu extends StatefulWidget {
  const _DurationMenu({
    required this.anchor,
    required this.initial,
    required this.countOf,
    required this.onChanged,
  });

  final Rect anchor;
  final YtDurationFilter initial;
  final int Function(YtDurationFilter) countOf;
  final ValueChanged<YtDurationFilter> onChanged;

  @override
  State<_DurationMenu> createState() => _DurationMenuState();
}

class _DurationMenuState extends State<_DurationMenu> {
  late YtDurationFilter _filter = widget.initial;

  /// 自訂拉桿的位置；第一次點「自訂」時從目前選的區間帶過去。
  late RangeValues _range = RangeValues(
    widget.initial.minMinutes.toDouble(),
    widget.initial.maxMinutes.toDouble(),
  );

  static const _width = 248.0;

  void _pick(YtDurationPreset p) {
    if (p == YtDurationPreset.custom) {
      final f = YtDurationFilter.custom(
        _range.start.round(),
        _range.end.round(),
      );
      setState(() => _filter = f);
      widget.onChanged(f);
      return;
    }
    final f = YtDurationFilter.preset(p);
    widget.onChanged(f);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final left = (widget.anchor.right - _width)
        .clamp(8.0, math.max(8.0, screen.width - _width - 8))
        .toDouble();
    final custom = _filter.preset == YtDurationPreset.custom;

    Widget item(YtDurationPreset p, String label) {
      final selected = _filter.preset == p;
      final count = p == YtDurationPreset.custom
          ? null
          : widget.countOf(YtDurationFilter.preset(p));
      return InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _pick(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected
                ? AppColors.accentSolid.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
                ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.accentSolid,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: widget.anchor.bottom + 6,
          width: _width,
          child: Material(
            color: const Color(0xF21C1C2B),
            borderRadius: BorderRadius.circular(14),
            elevation: 12,
            shadowColor: Colors.black,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.glassEdge),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  item(YtDurationPreset.any, '不限'),
                  item(YtDurationPreset.under2, '2 分內'),
                  item(YtDurationPreset.from2to6, '2–6 分'),
                  item(YtDurationPreset.from6to20, '6–20 分'),
                  item(YtDurationPreset.custom, '自訂'),
                  if (custom) ...[
                    const SizedBox(height: 4),
                    Text(
                      YtDurationFilter.customLabel(
                        _range.start.round(),
                        _range.end.round(),
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '符合 ${widget.countOf(_filter)} 部',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accentSolid,
                        inactiveTrackColor: AppColors.glassEdge,
                        thumbColor: Colors.white,
                        overlayColor: AppColors.accentSolid.withValues(
                          alpha: 0.15,
                        ),
                        trackHeight: 3,
                        showValueIndicator: ShowValueIndicator.never,
                        rangeTickMarkShape: const RoundRangeSliderTickMarkShape(
                          tickMarkRadius: 0,
                        ),
                      ),
                      child: RangeSlider(
                        min: 0,
                        max: YtDurationFilter.ceilingMinutes.toDouble(),
                        divisions: YtDurationFilter.ceilingMinutes,
                        values: _range,
                        onChanged: (v) {
                          // 至少留 1 分鐘的區間，兩顆不能疊在一起。
                          if (v.end - v.start < 1) return;
                          final f = YtDurationFilter.custom(
                            v.start.round(),
                            v.end.round(),
                          );
                          setState(() {
                            _range = v;
                            _filter = f;
                          });
                          widget.onChanged(f);
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0', style: _tick),
                          Text('10', style: _tick),
                          Text('20', style: _tick),
                          Text('30', style: _tick),
                          Text('40+ 分', style: _tick),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _tick = TextStyle(fontSize: 10, color: AppColors.ink3);
