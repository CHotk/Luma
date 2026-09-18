import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 練習紙的顏色跟畫筆邏輯，練習頁（現寫）跟練習紀錄頁（重播／匯出）
/// 共用，不要各自刻一份。
///
/// 這幾個顏色是全 App 唯一不從 `AppColors` 取的地方：紙本來就該是
/// 亮色，跟其餘畫面統一的暗色玻璃底不是同一件事，硬套 AppColors
/// 會讓墨跡完全看不清楚。
const paperColor = Color(0xFFF7ECEC);
const paperLineColor = Color(0x382A1420);
const inkColor = Color(0xFF2A1420);
const guideColor = Color(0x292A1420);

/// 這個檔案裡所有筆畫座標都是**正規化座標**：x/y 各是紙寬／紙高的
/// 0~1 比例，不是實際像素。原因：練習頁的紙不是固定尺寸（手機窄、
/// 桌面寬，同一個字兩邊寫出來的原始像素座標範圍差很多），存正規化
/// 座標才能保證同一筆紀錄無論在多大的畫布上重播、匯出，字都置中、
/// 填滿，不會因為存檔當下螢幕大小不同而跑位或縮成一小角。畫的時候
/// 各個 painter 自己乘回目前 `size` 還原成實際像素。
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

/// 畫完整的筆畫，不做漸進顯示。練習頁現寫、練習紀錄頁的靜態縮圖、
/// 匯出成 PNG 都用這個——差別只在餵給它的 `size` 多大。
class InkPainter extends CustomPainter {
  const InkPainter({required this.strokes, this.color = inkColor});

  /// 正規化座標（0~1），見檔案開頭說明。
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _inkPaint(color);
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final pts = [
        for (final p in stroke) Offset(p.dx * size.width, p.dy * size.height),
      ];
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, 2.5, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}

/// 每一筆的軌跡點：正規化座標（0~1，見檔案開頭說明）＋「從整次練習
/// 第一次落筆算起」的毫秒數。同一份紀錄裡所有筆畫共用同一條時間軸，
/// 不是每筆各自從零起算。
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
        final scaled = Offset(pos.dx * size.width, pos.dy * size.height);
        if (t <= elapsedMs) {
          visible.add(scaled);
          continue;
        }
        if (i > 0) {
          final (prevPos, prevT) = stroke[i - 1];
          final prevScaled = Offset(
            prevPos.dx * size.width,
            prevPos.dy * size.height,
          );
          final span = t - prevT;
          final frac = span <= 0
              ? 1.0
              : ((elapsedMs - prevT) / span).clamp(0.0, 1.0);
          interpolated = Offset.lerp(prevScaled, scaled, frac);
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

/// 把一份筆畫紀錄（正規化座標）畫成一張獨立的 PNG，給「匯出這張」用。
///
/// 不靠 `RepaintBoundary` 截圖——那需要這份紀錄當下真的顯示在畫面上
/// 才能截，練習紀錄頁列出的是「過去」的紀錄，不會為了匯出特地重新
/// 顯示一次。直接用 `PictureRecorder` 在背景畫一張全新的圖，跟畫面上
/// 顯示什麼完全無關，纪录多久以前存的都能匯出。
Future<Uint8List> renderStrokesToPng(
  List<List<Offset>> strokes, {
  int size = 480,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final logicalSize = Size(size.toDouble(), size.toDouble());
  canvas.drawRect(Offset.zero & logicalSize, Paint()..color = paperColor);
  const PaperGridPainter().paint(canvas, logicalSize);
  InkPainter(strokes: strokes).paint(canvas, logicalSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 把一份重播紀錄（見 [ReplayInkPainter]）畫成一份動畫 GIF，給「重播
/// 旁邊下載動畫」用（2026-09-18 使用者要求）。
///
/// 沒有做真正的影片編碼（mp4／webm）——純 Flutter Web 沒有內建影片
/// 編碼能力，要編碼成真的影片得另外引入很重的套件（例如 ffmpeg.wasm），
/// 跟「看筆畫怎麼畫出來」這個小功能的規模不相稱。GIF 一樣是「筆畫自己
/// 畫出來」的動畫效果，`image` 套件純 Dart 就能編，不用加重依賴。
///
/// 逐格畫法跟 [renderStrokesToPng] 同一套：不靠 `RepaintBoundary` 截圖，
/// 直接用 `PictureRecorder` 在背景依序畫出每一格的時間點，跟畫面上
/// 顯示什麼完全無關。
Future<Uint8List> renderStrokesToGif(
  List<List<TimedPoint>> strokes, {
  int size = 320,
  int maxFrames = 90,
}) async {
  final totalMs = ReplayInkPainter.totalDurationMs(strokes);
  // 目標每格 45ms（約 22fps）——原本是 80ms（約 12fps），使用者回饋
  // 看起來會頓；上限也從 40 格提高到 90 格，不然寫比較久的字還是會
  // 被 maxFrames 卡回更粗的格數，等於白調（2026-09-18 使用者要求）。
  final frameCount = totalMs <= 0
      ? 1
      : math.min(maxFrames, math.max(1, (totalMs / 45).ceil()));
  final stepMs = frameCount <= 1 ? 0.0 : totalMs / frameCount;

  // 幾乎全是紙色背景加深色墨線的簡單畫面，不用神經網路量化那麼講究，
  // 用比較快的 octree、色數也不用到 256，逐格編碼才不會卡太久。
  final encoder = img.GifEncoder(
    repeat: 0,
    quantizerType: img.QuantizerType.octree,
    numColors: 64,
  );

  for (var i = 0; i <= frameCount; i++) {
    final isLast = i == frameCount;
    final t = isLast ? totalMs : stepMs * i;
    final frame = await _rasterizeFrame(strokes, t, size);
    // GIF 的格延遲單位是 1/100 秒，最後一格多停留一下，讓看的人來得及
    // 看到寫完的完整樣子，不是畫完馬上就跳回去重播（repeat: 0 是無限
    // 循環）。
    final duration = isLast ? 120 : (stepMs / 10).round().clamp(2, 100);
    encoder.addFrame(frame, duration: duration);
  }

  return encoder.finish()!;
}

Future<img.Image> _rasterizeFrame(
  List<List<TimedPoint>> strokes,
  double elapsedMs,
  int size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final logicalSize = Size(size.toDouble(), size.toDouble());
  canvas.drawRect(Offset.zero & logicalSize, Paint()..color = paperColor);
  const PaperGridPainter().paint(canvas, logicalSize);
  ReplayInkPainter(strokes: strokes, elapsedMs: elapsedMs).paint(
    canvas,
    logicalSize,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return img.Image.fromBytes(
    width: size,
    height: size,
    bytes: byteData!.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}
