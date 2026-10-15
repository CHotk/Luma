import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';

/// 全 App 的小元件樣子（2026-10-15 使用者選設計稿
/// `design-history/已選擇完成/2026-10-15_共用小元件五種風格.html` 第 3 版
/// 「毛玻璃（現在的整理版）」）：保留現在的玻璃卡片、藍色主色，把各頁
/// 不一致的地方統一——
/// - 開關一律藍色（原本預設的有綠有藍）
/// - 標籤（chip）、分段切換一律膠囊形
/// - 主按鈕藍色、圓角跟卡片同一家族，帶一點藍色光暈
/// - 輸入框半透明玻璃底、細白邊，選中變藍
/// 個別頁面自己指定的顏色照舊（例如日記的主色）。
ThemeData buildAppTheme() {
  const fill = AppColors.glassFill;
  const edge = AppColors.glassEdge;
  final pill = WidgetStateProperty.all<OutlinedBorder>(const StadiumBorder());
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.button),
  );
  OutlineInputBorder inputBorder(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.button),
    borderSide: BorderSide(color: c),
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.bg,
      primary: AppColors.accent,
      secondary: AppColors.accentSolid,
      error: AppColors.bad,
    ),
    // 之後打包思源黑體時，字體只要在這裡指定一次。
    fontFamily: null,
    useMaterial3: true,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accentSolid
            : Colors.white.withValues(alpha: 0.12),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(side: BorderSide(color: edge)),
      side: const BorderSide(color: edge),
      backgroundColor: fill,
      selectedColor: AppColors.accentSolid.withValues(alpha: 0.55),
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: AppColors.ink, fontSize: 13),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        side: WidgetStateProperty.all(const BorderSide(color: edge)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white.withValues(alpha: 0.16)
              : fill,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? AppColors.ink : AppColors.ink2,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentSolid,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        shape: buttonShape,
        elevation: 3,
        shadowColor: AppColors.accentSolid.withValues(alpha: 0.6),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        shape: buttonShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: inputBorder(edge),
      enabledBorder: inputBorder(edge),
      focusedBorder: inputBorder(AppColors.accent),
      errorBorder: inputBorder(AppColors.bad),
      focusedErrorBorder: inputBorder(AppColors.bad),
    ),
    cardTheme: CardThemeData(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: edge),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accentSolid : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.ink3,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accentSolid,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
      thumbColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
