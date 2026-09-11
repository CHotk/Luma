/// 間距與圓角。畫面不准直接寫數字，一律從這裡取。
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const xl = 26.0;

  /// 畫面左右的固定留白。整支 App 用同一個值，換了就整體一起換。
  static const screenSide = 18.0;
}

/// 圓角。卡片大、按鈕中、標籤小，三級就夠，不要再多。
abstract final class Radii {
  static const card = 18.0;
  static const button = 15.0;
  static const chip = 999.0;
}
