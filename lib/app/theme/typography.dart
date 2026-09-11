import 'package:flutter/material.dart';

import 'colors.dart';

/// 字級與字重。
///
/// 中文字體之後會打包思源黑體，屆時只要在這裡指定 fontFamily，
/// 畫面不用改任何一行。
abstract final class AppText {
  /// 單字卡正面那個大字。整支 App 最大的字只有這個。
  static const hero = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    height: 1.1,
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const body = TextStyle(fontSize: 14, color: AppColors.ink);

  static const bodyDim = TextStyle(fontSize: 13.5, color: AppColors.ink2);

  /// 小標。全大寫加寬字距，用在面板標題。
  static const label = TextStyle(
    fontSize: 10,
    letterSpacing: 1.1,
    color: AppColors.ink2,
    fontWeight: FontWeight.w500,
  );

  static const note = TextStyle(fontSize: 11.5, color: AppColors.ink2);

  /// 數字專用。等寬才不會跳動。
  static const number = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
