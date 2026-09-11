import 'package:flutter/material.dart';

/// 全專案唯一可以寫死色碼的地方。
///
/// 規範：畫面裡不准出現 Color(0x...)，一律從這裡取。
/// 之後要調深淺或換色系，只改這個檔。
abstract final class AppColors {
  // 底色
  static const bg = Color(0xFF0C0C13);
  static const bgDeep = Color(0xFF0A0A10);

  // 文字。ink 最亮，ink3 最暗，照層級使用。
  static const ink = Color(0xFFF3F2F8);
  static const ink2 = Color(0xFFA3A2B2);
  static const ink3 = Color(0xFF74738A);

  // 主色
  static const accent = Color(0xFF7EA6FF);
  static const accentSolid = Color(0xFF2E6BFF);

  /// 語意色。跟主色分開，不可互相借用。
  /// 綠代表答對、黃代表未確認、紅代表答錯，標誌和裝飾都不准用這三個。
  static const ok = Color(0xFF5FE08D);
  static const mid = Color(0xFFF5C763);
  static const bad = Color(0xFFFF938B);

  // 毛玻璃面板
  static const glassFill = Color(0x13FFFFFF);
  static const glassEdge = Color(0x24FFFFFF);
  static const glassHi = Color(0x21FFFFFF);

  /// 啟動畫面與背景的環境光。四團模糊色塊，暗底才看得出玻璃的邊。
  static const ambBlue = Color(0xFF2450D8);
  static const ambEmber = Color(0xFFC2521C);
  static const ambViolet = Color(0xFF6C2FCE);
  static const ambTeal = Color(0xFF0E7C6C);

  /// 標誌配色 10：直的一筆從白漸層到紫，橫的一筆淺藍半透明。
  static const markTop = Color(0xFFFFFFFF);
  static const markBottom = Color(0xFF9B7BFF);
  static const markArm = Color(0x8C7EA6FF);
}
