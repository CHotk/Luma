import 'package:flutter/material.dart';

/// 全 App 共用的「統計」圖示——使用者準備了一張圖放在
/// `assets/images/fitness/stats_icon.png`，要求所有「統計」按鈕都用
/// 同一張，不要各自零散用內建 Material 圖示（2026-09-23 使用者要求：
/// 整個 App 統計都要用他）。放在 `fitness/` 資料夾底下只是因為那是
/// 這張圖第一次出現的地方，不代表這個圖示只給健身功能用。
///
/// 圖片載入失敗（還沒放、路徑打錯）就退回原本設計的 [Icons.bar_chart_rounded]，
/// 不會讓按鈕壞掉或丟例外——跟側邊選單自訂圖示同一套防呆做法
/// （見 `app_side_drawer.dart` 的 `_NavItem`）。
class StatsIcon extends StatelessWidget {
  const StatsIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/fitness/stats_icon.png',
      width: size,
      height: size,
      color: color,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.bar_chart_rounded, size: size, color: color),
    );
  }
}
