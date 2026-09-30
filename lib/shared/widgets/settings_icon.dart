import 'package:flutter/material.dart';

import '../small_asset.dart';

/// 全 App 共用的「設定」齒輪圖示，跟 [StatsIcon]（見 `stats_icon.dart`）
/// 同一套做法：讀使用者準備的 `assets/images/fitness/setting_icon.png`，
/// 失敗就退回原本設計的 [Icons.settings_outlined]
/// （2026-09-23 使用者要求：全 App 的設定齒輪都換成他準備的圖）。
///
/// 檔案放在 `fitness/` 資料夾底下只是使用者當時丟檔案的地方，跟健身
/// 功能無關，這張圖是全 App 共用的。
class SettingsIcon extends StatelessWidget {
  const SettingsIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 縮小版（見 `small_asset.dart`，原圖 1254x1254 只顯示 20px 上下）。
    return Image.asset(
      smallAssetFor('assets/images/fitness/setting_icon.png'),
      width: size,
      height: size,
      color: color,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.settings_outlined, size: size, color: color),
    );
  }
}
