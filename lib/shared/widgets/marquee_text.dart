import 'package:flutter/material.dart';

/// 放得下就是一般的單行文字；放不下就走馬燈：停一下、往左捲到第二份
/// 接上來、再停一下，一直循環（2026-10-12 使用者要求：YT 頻道詳情頁標題
/// 名字太長要走馬燈，不要被「…」切掉）。
class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  /// 兩份文字中間的空白。
  static const _gap = 40.0;

  /// 每秒捲幾個像素。
  static const _speed = 40.0;

  /// 每一輪開頭停多久，先讓人看清楚開頭。
  static const _pause = Duration(milliseconds: 1500);

  late final AnimationController _ctrl;
  double _distance = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 文字寬度變了（換字、換寬度）才重新設定動畫；放得下就停掉。排到
  /// 這一幀畫完才做，不在 layout 當中改動畫（會觸發重繪）。
  void _configure(double textWidth, double maxWidth) {
    if (!mounted) return;
    final overflow = textWidth > maxWidth;
    final distance = overflow ? textWidth + _gap : 0.0;
    if (distance == _distance) return;
    _distance = distance;
    _ctrl.stop();
    _ctrl.value = 0;
    if (!overflow) return;
    final scroll = Duration(milliseconds: (distance / _speed * 1000).round());
    _ctrl.duration = _pause + scroll;
    _ctrl.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final textWidth = painter.width;
        final height = painter.height;
        painter.dispose();
        final maxWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _configure(textWidth, maxWidth),
        );
        if (textWidth <= maxWidth) {
          return Text(widget.text, style: style, maxLines: 1);
        }
        return SizedBox(
          width: maxWidth,
          height: height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final total = _ctrl.duration?.inMilliseconds ?? 0;
                final pauseFrac = total == 0
                    ? 1.0
                    : _pause.inMilliseconds / total;
                final t = _ctrl.value <= pauseFrac || pauseFrac >= 1
                    ? 0.0
                    : Curves.linear.transform(
                        (_ctrl.value - pauseFrac) / (1 - pauseFrac),
                      );
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(-t * _distance, 0),
                    child: child,
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, style: style, maxLines: 1, softWrap: false),
                  const SizedBox(width: _gap),
                  Text(widget.text, style: style, maxLines: 1, softWrap: false),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
