import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 測試用開關：連續跑的動畫會讓 `pumpAndSettle` 永遠等不完，測試裡關掉。
bool sakuraPetalsEnabled = true;

/// 日文首頁的櫻花飄落特效（2026-09-24 使用者要求：偶爾一片櫻花花瓣
/// 自然飄下來，唯美不要太吵）。
///
/// 疊在頁面內容上面、不吃點擊（[IgnorePointer]）。不是一直下花瓣雨，
/// 而是隔幾秒才飄下一片（偶爾兩片）；每片花瓣有自己的大小、飄移方向、
/// 左右擺盪跟翻轉節奏，開頭結尾淡入淡出，看起來像風吹落的。
/// 沒有花瓣在飄的空檔不畫東西，也不占效能。
class SakuraPetals extends StatefulWidget {
  const SakuraPetals({super.key, required this.child});

  final Widget child;

  @override
  State<SakuraPetals> createState() => _SakuraPetalsState();
}

class _Petal {
  _Petal(Random r, this.bornAt)
    : startX = 0.08 + r.nextDouble() * 0.84,
      drift = (r.nextDouble() - 0.4) * 0.35,
      swayAmp = 0.03 + r.nextDouble() * 0.05,
      swayFreq = 1.2 + r.nextDouble() * 1.4,
      phase = r.nextDouble() * pi * 2,
      size = 11 + r.nextDouble() * 9,
      spin = (r.nextDouble() - 0.5) * 2.4,
      flipFreq = 1.6 + r.nextDouble() * 1.8,
      lifeSec = 10 + r.nextDouble() * 6,
      tint = r.nextDouble();

  final Duration bornAt;
  final double startX; // 0~1，畫面寬的比例
  final double drift; // 整段飄下來水平位移的比例
  final double swayAmp;
  final double swayFreq;
  final double phase;
  final double size;
  final double spin;
  final double flipFreq;
  final double lifeSec;
  final double tint; // 0~1，在淺粉到深粉之間挑色
}

class _SakuraPetalsState extends State<SakuraPetals>
    with SingleTickerProviderStateMixin {
  final _rng = Random();
  final _petals = <_Petal>[];
  final _clock = ValueNotifier<Duration>(Duration.zero);
  Ticker? _ticker;
  Duration _nextSpawn = const Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    if (sakuraPetalsEnabled) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration now) {
    if (now >= _nextSpawn) {
      _petals.add(_Petal(_rng, now));
      // 偶爾（約 1/4）緊接著再飄一片。
      if (_rng.nextDouble() < 0.25) {
        _petals.add(_Petal(_rng, now + const Duration(milliseconds: 900)));
      }
      _nextSpawn = now + Duration(milliseconds: 5000 + _rng.nextInt(7000));
    }
    _petals.removeWhere(
      (p) => (now - p.bornAt).inMilliseconds / 1000 > p.lifeSec,
    );
    _clock.value = now;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_ticker != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _PetalPainter(_petals, _clock)),
              ),
            ),
          ),
      ],
    );
  }
}

class _PetalPainter extends CustomPainter {
  _PetalPainter(this.petals, this.clock) : super(repaint: clock);

  final List<_Petal> petals;
  final ValueNotifier<Duration> clock;

  static const _light = Color(0xFFFBDCE6);
  static const _deep = Color(0xFFEA92AC);

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    for (final p in petals) {
      final t = (now - p.bornAt).inMilliseconds / 1000;
      if (t < 0) continue;
      final u = (t / p.lifeSec).clamp(0.0, 1.0);
      // 下落稍微加速，比等速自然。
      final y = -0.06 + 1.12 * (u * (0.85 + 0.15 * u));
      final x =
          p.startX + p.drift * u + p.swayAmp * sin(t * p.swayFreq + p.phase);
      final fade = min(1.0, min(u / 0.1, (1 - u) / 0.18));
      final flip = cos(t * p.flipFreq + p.phase);

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.phase + t * p.spin);
      // 翻轉：X 方向縮放，模擬花瓣在空中側過來。
      canvas.scale(0.35 + 0.65 * flip.abs(), 1);
      final color = Color.lerp(_light, _deep, p.tint * 0.7)!;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.95 * fade),
            _deep.withValues(alpha: 0.75 * fade),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: p.size));
      canvas.drawPath(_petalPath(p.size), paint);
      canvas.restore();
    }
  }

  /// 櫻花瓣：上緣中間有個小缺口，往下收成圓潤的尖。
  Path _petalPath(double s) {
    final path = Path()
      ..moveTo(0, -s * 0.55)
      ..cubicTo(-s * 0.2, -s * 0.85, -s * 0.75, -s * 0.7, -s * 0.6, -s * 0.05)
      ..cubicTo(-s * 0.5, s * 0.45, -s * 0.12, s * 0.8, 0, s * 0.95)
      ..cubicTo(s * 0.12, s * 0.8, s * 0.5, s * 0.45, s * 0.6, -s * 0.05)
      ..cubicTo(s * 0.75, -s * 0.7, s * 0.2, -s * 0.85, 0, -s * 0.55)
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PetalPainter oldDelegate) => true;
}
