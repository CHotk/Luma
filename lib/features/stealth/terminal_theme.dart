import 'package:flutter/material.dart';

/// 偽裝模式專用的配色與字體。
///
/// 這裡刻意不用 AppColors，因為它模仿的是 Windows 的命令提示字元，
/// 不是 Lume 自己的視覺。兩者混用就不像了。
abstract final class TerminalTheme {
  /// Windows Terminal 的預設底色。純黑反而不像，這個偏一點點灰。
  static const background = Color(0xFF0C0C0C);
  static const titleBar = Color(0xFF1F1F1F);
  static const titleText = Color(0xFFCCCCCC);

  /// 關閉鈕滑過去會變紅，這個細節做了才像。
  static const closeTint = Color(0xFFC42B1C);

  static const text = Color(0xFFCCCCCC);
  static const textBright = Color(0xFFF2F2F2);

  /// Consolas 是 Windows 內建，其他平台退回系統等寬字。
  static const fontFamily = 'Consolas';
  static const _fallback = ['Courier New', 'Menlo', 'monospace'];

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 1.45,
    color: text,
  );

  static const bodyBright = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 1.45,
    color: textBright,
  );
}
