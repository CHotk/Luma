import 'package:flutter/material.dart';

/// 小國旗圖示，標示目前在練哪個語言的軌道（例如首頁左上角）。
///
/// 不用國旗 emoji（🇺🇸）：Windows 的系統字型（Segoe UI Emoji）不畫
/// 國旗圖案，會直接退成「US」兩個字母，這個 App 主要在 Windows + Chrome
/// 上開發測試，用 emoji 會直接看到退化畫面。改用 CustomPainter 自己畫
/// 簡化版國旗，顏色是國旗本身固有的顏色，不是這個 App 的配色系統，
/// 不受 AppColors「畫面裡不准出現 Color(0x...)」那條規範限制。
enum FlagCountry { us }

class MiniFlag extends StatelessWidget {
  const MiniFlag({super.key, required this.country, this.width = 20});

  final FlagCountry country;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: width,
        height: width * 2 / 3,
        child: CustomPaint(painter: _painterFor(country)),
      ),
    );
  }

  CustomPainter _painterFor(FlagCountry c) => switch (c) {
    FlagCountry.us => const _UsFlagPainter(),
  };
}

class _UsFlagPainter extends CustomPainter {
  const _UsFlagPainter();

  static const _red = Color(0xFFB22234);
  static const _white = Color(0xFFFFFFFF);
  static const _blue = Color(0xFF3C3B6E);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _white);
    final stripeH = size.height / 7;
    for (var i = 0; i < 7; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, stripeH * i, size.width, stripeH),
        Paint()..color = _red,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.4, stripeH * 4),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant _UsFlagPainter oldDelegate) => false;
}
