import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../data/services/youtube_api_service.dart';

/// 一個月的上傳統計，一般影片跟 Shorts 分開算（見
/// [YoutubeVideo.isLikelyShort] 的判斷依據跟侷限）。
class MonthlyUploadCount {
  const MonthlyUploadCount({
    required this.month,
    required this.regularCount,
    required this.shortsCount,
  });

  /// 固定是該月 1 號，只拿來排序跟標籤用。
  final DateTime month;
  final int regularCount;
  final int shortsCount;
}

/// 把影片清單依發布月份分桶。月份區間是「第一部影片所在月」到「這個月」
/// 中間完整補滿，不是只列有資料的月份——不然中間空月份的地方，折線會
/// 直接跳過去，看起來像是斷點接錯，實際上是那個月真的沒發影片
/// （上傳頻率圖的重點正是要看得出「這段時間有沒有在發」）。
List<MonthlyUploadCount> bucketVideosByMonth(List<YoutubeVideo> videos) {
  if (videos.isEmpty) return const [];
  DateTime keyOf(DateTime t) => DateTime(t.year, t.month);
  final counts = <DateTime, ({int regular, int shorts})>{};
  var earliest = keyOf(videos.first.publishedAt);
  for (final v in videos) {
    final key = keyOf(v.publishedAt);
    if (key.isBefore(earliest)) earliest = key;
    final prev = counts[key] ?? (regular: 0, shorts: 0);
    counts[key] = v.isLikelyShort
        ? (regular: prev.regular, shorts: prev.shorts + 1)
        : (regular: prev.regular + 1, shorts: prev.shorts);
  }
  final now = keyOf(DateTime.now());
  final result = <MonthlyUploadCount>[];
  var cursor = earliest;
  while (!cursor.isAfter(now)) {
    final c = counts[cursor] ?? (regular: 0, shorts: 0);
    result.add(
      MonthlyUploadCount(
        month: cursor,
        regularCount: c.regular,
        shortsCount: c.shorts,
      ),
    );
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return result;
}

/// 頻道詳情頁的「上傳頻率」摺線圖。每月一個點，一般影片跟 Shorts
/// 各一條線。左邊固定一欄 Y 軸刻度（0～最大值，不跟著捲動），中間畫格線，
/// 底下每個月都標「n月」、第一個點跟跨年的一月才多標年份。月份少（近半年
/// 只有 7 個點）就撐滿寬度不捲動；月份多到放不下才用橫向捲動，預設捲到
/// 最右邊（最新月份）。
class UploadFrequencyChart extends StatefulWidget {
  const UploadFrequencyChart({super.key, required this.data});

  final List<MonthlyUploadCount> data;

  static const _minPxPerMonth = 34.0;
  static const _height = 176.0;

  @override
  State<UploadFrequencyChart> createState() => _UploadFrequencyChartState();
}

class _UploadFrequencyChartState extends State<UploadFrequencyChart> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把最大值進位成 4 的倍數（4 → 4、7 → 8、13 → 16…），Y 軸切成 4 等分
  /// 整數格。
  static int _niceMax(int max) {
    if (max <= 4) return 4;
    return (max / 4).ceil() * 4;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    const height = UploadFrequencyChart._height;
    if (data.isEmpty) {
      return const SizedBox(
        height: height,
        child: Center(
          child: Text(
            '還沒有影片資料可以畫圖',
            style: TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
        ),
      );
    }
    final maxCount = data
        .map((d) => d.regularCount > d.shortsCount ? d.regularCount : d.shortsCount)
        .fold<int>(1, (a, b) => a > b ? a : b);
    final top = _niceMax(maxCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: AppColors.accent, label: '一般影片'),
            const SizedBox(width: 14),
            _LegendDot(color: AppColors.ytAccent, label: 'Shorts（估計，≤60秒）'),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final plotWidth = constraints.maxWidth - _ChartPainter.yAxisWidth;
              final needed = data.length * UploadFrequencyChart._minPxPerMonth;
              final contentWidth = needed > plotWidth ? needed : plotWidth;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_controller.hasClients) {
                  _controller.jumpTo(_controller.position.maxScrollExtent);
                }
              });
              return Row(
                children: [
                  // 固定的 Y 軸刻度欄，不跟著橫向捲動。
                  CustomPaint(
                    size: const Size(_ChartPainter.yAxisWidth, height),
                    painter: _YAxisPainter(top: top),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      child: CustomPaint(
                        size: Size(contentWidth, height),
                        painter: _ChartPainter(data: data, top: top),
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.ink2)),
      ],
    );
  }
}

const _bottomPad = 26.0;
const _topPad = 8.0;

/// Y 軸刻度：0、1/4、2/4、3/4、上限，靠右對齊。
class _YAxisPainter extends CustomPainter {
  _YAxisPainter({required this.top});

  final int top;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _bottomPad - _topPad;
    const style = TextStyle(fontSize: 9.5, color: AppColors.ink3);
    for (var i = 0; i <= 4; i++) {
      final value = top * i ~/ 4;
      final y = _topPad + plotHeight - plotHeight * i / 4;
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 6, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _YAxisPainter oldDelegate) =>
      oldDelegate.top != top;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.data, required this.top});

  final List<MonthlyUploadCount> data;
  final int top;

  static const yAxisWidth = 30.0;
  static const _sidePad = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _bottomPad - _topPad;
    final usable = size.width - _sidePad * 2;
    final stepX = data.length > 1 ? usable / (data.length - 1) : 0.0;

    double xAt(int i) =>
        data.length > 1 ? _sidePad + stepX * i : size.width / 2;
    double yAt(int count) => _topPad + plotHeight - (count / top) * plotHeight;

    // 水平格線，對應左邊 Y 軸的刻度。
    final gridPaint = Paint()
      ..color = AppColors.glassEdge
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = _topPad + plotHeight - plotHeight * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSeries(canvas, data.map((d) => d.regularCount).toList(), xAt, yAt,
        AppColors.accent);
    _drawSeries(canvas, data.map((d) => d.shortsCount).toList(), xAt, yAt,
        AppColors.ytAccent);

    // X 軸標籤：每個月都標「n月」，第一個點跟跨年的一月再多標年份放
    // 第二行。月份很多（>14）時只標一月跟每 3 個月，避免疊字。
    final crowded = data.length > 14;
    const monthStyle = TextStyle(fontSize: 9.5, color: AppColors.ink2);
    const yearStyle = TextStyle(fontSize: 8.5, color: AppColors.ink3);
    for (var i = 0; i < data.length; i++) {
      final m = data[i].month;
      final showYear = i == 0 || m.month == 1;
      if (crowded && !showYear && m.month % 3 != 1) continue;
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: '${m.month}月', style: monthStyle),
            if (showYear) TextSpan(text: '\n${m.year}', style: yearStyle),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      // 別讓最左最右的字被切掉。
      final x = (xAt(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - _bottomPad + 4));
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<int> values,
    double Function(int) xAt,
    double Function(int) yAt,
    Color color,
  ) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(xAt(i), yAt(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      canvas.drawCircle(Offset(xAt(i), yAt(values[i])), 2.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.top != top;
}
