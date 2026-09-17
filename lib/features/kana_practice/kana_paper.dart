import 'package:flutter/material.dart';

/// 練習紙的顏色跟畫筆邏輯，練習頁（現寫）跟練習紀錄頁（重播）共用，
/// 不要各自刻一份。
///
/// 這幾個顏色是全 App 唯一不從 `AppColors` 取的地方：紙本來就該是
/// 亮色，跟其餘畫面統一的暗色玻璃底不是同一件事，硬套 AppColors
/// 會讓墨跡完全看不清楚，道理跟 `MiniFlag` 不用 AppColors 畫國旗一樣。
const paperColor = Color(0xFFF7ECEC);
const paperLineColor = Color(0x382A1420);
const inkColor = Color(0xFF2A1420);
const guideColor = Color(0x292A1420);

Paint _inkPaint(Color color) => Paint()
  ..color = color
  ..strokeWidth = 5
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

/// 仿「原稿用紙」的十字參考線，不是真的稿紙格，練字夠用。
class PaperGridPainter extends CustomPainter {
  const PaperGridPainter({this.color = paperLineColor});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final padX = size.width * 0.08;
    final padY = size.height * 0.08;
    _dashed(
      canvas,
      Offset(size.width / 2, padY),
      Offset(size.width / 2, size.height - padY),
      paint,
    );
    _dashed(
      canvas,
      Offset(padX, size.height / 2),
      Offset(size.width - padX, size.height / 2),
      paint,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segEnd = covered + dash > total ? total : covered + dash;
      canvas.drawLine(a + dir * covered, a + dir * segEnd, paint);
      covered += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant PaperGridPainter oldDelegate) => false;
}

/// 畫完整的筆畫，不做漸進顯示。練習頁現寫用這個。
class InkPainter extends CustomPainter {
  const InkPainter({required this.strokes, this.color = inkColor});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _inkPaint(color);
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.5, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}

/// 每一筆的軌跡點，帶著「從整次練習第一次落筆算起」的毫秒數。
/// 同一份紀錄裡所有筆畫共用同一條時間軸，不是每筆各自從零起算。
typedef TimedPoint = (Offset pos, double t);

/// 依照原始筆畫順序、真實的落筆時間，逐點畫出來，給「重播當初怎麼
/// 寫的」用。位置跟筆畫之間的停頓長短都是照實際紀錄重播，不是猜的
/// 固定配速（使用者 2026-09-17 要求：位置跟間隔都要對）。
class ReplayInkPainter extends CustomPainter {
  const ReplayInkPainter({
    required this.strokes,
    required this.elapsedMs,
    this.color = inkColor,
  });

  final List<List<TimedPoint>> strokes;
  final double elapsedMs;
  final Color color;

  /// 整份紀錄實際花了多久，取最後一筆最後一個點的時間戳。
  static double totalDurationMs(List<List<TimedPoint>> strokes) {
    for (final stroke in strokes.reversed) {
      if (stroke.isNotEmpty) return stroke.last.$2;
    }
    return 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _inkPaint(color);
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      final visible = <Offset>[];
      Offset? interpolated;
      for (var i = 0; i < stroke.length; i++) {
        final (pos, t) = stroke[i];
        if (t <= elapsedMs) {
          visible.add(pos);
          continue;
        }
        if (i > 0) {
          final (prevPos, prevT) = stroke[i - 1];
          final span = t - prevT;
          final frac = span <= 0 ? 1.0 : ((elapsedMs - prevT) / span).clamp(0.0, 1.0);
          interpolated = Offset.lerp(prevPos, pos, frac);
        }
        break;
      }
      if (visible.isEmpty && interpolated == null) continue;

      if (visible.length <= 1 && interpolated == null) {
        canvas.drawCircle(visible.first, 2.5, Paint()..color = color);
        continue;
      }

      final path = Path();
      final start = visible.isNotEmpty ? visible.first : interpolated!;
      path.moveTo(start.dx, start.dy);
      for (final p in visible.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (interpolated != null && visible.isNotEmpty) {
        path.lineTo(interpolated.dx, interpolated.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ReplayInkPainter oldDelegate) =>
      oldDelegate.elapsedMs != elapsedMs;
}
