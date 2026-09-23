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
/// 各一條線——月份數一多（追蹤好幾年的頻道）畫面放不下，用橫向
/// 捲動撐開，不縮圖擠壓資料，預設捲到最右邊（最新月份）。
class UploadFrequencyChart extends StatelessWidget {
  const UploadFrequencyChart({super.key, required this.data});

  final List<MonthlyUploadCount> data;

  static const _pxPerMonth = 30.0;
  static const _height = 160.0;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: _height,
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
    final controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
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
          height: _height,
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: CustomPaint(
              size: Size(data.length * _pxPerMonth + 24, _height),
              painter: _ChartPainter(data: data, maxCount: maxCount),
            ),
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

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.data, required this.maxCount});

  final List<MonthlyUploadCount> data;
  final int maxCount;

  static const _leftPad = 8.0;
  static const _bottomPad = 22.0;
  static const _topPad = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _bottomPad - _topPad;
    final stepX = (size.width - _leftPad * 2) / (data.length - 1).clamp(1, 1 << 30);

    double xAt(int i) => _leftPad + stepX * i;
    double yAt(int count) =>
        _topPad + plotHeight - (count / maxCount) * plotHeight;

    // 底線
    final axisPaint = Paint()
      ..color = AppColors.glassEdge
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_leftPad, size.height - _bottomPad),
      Offset(size.width - _leftPad, size.height - _bottomPad),
      axisPaint,
    );

    _drawSeries(
      canvas,
      data.map((d) => d.regularCount).toList(),
      xAt,
      yAt,
      AppColors.accent,
    );
    _drawSeries(
      canvas,
      data.map((d) => d.shortsCount).toList(),
      xAt,
      yAt,
      AppColors.ytAccent,
    );

    // X 軸標籤：每年一月、或資料第一個點才標，中間月份太密不標，
    // 不然字會疊在一起看不清楚。
    final labelStyle = TextStyle(fontSize: 9.5, color: AppColors.ink3);
    for (var i = 0; i < data.length; i++) {
      final m = data[i].month;
      final isFirst = i == 0;
      final isJan = m.month == 1;
      if (!isFirst && !isJan) continue;
      final text = isJan ? '${m.year}' : '${m.year}.${m.month}';
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xAt(i) - tp.width / 2, size.height - _bottomPad + 4),
      );
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
      ..strokeWidth = 1.6
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
      canvas.drawCircle(Offset(xAt(i), yAt(values[i])), 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.maxCount != maxCount;
}
