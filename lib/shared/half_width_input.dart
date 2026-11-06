import 'package:flutter/services.dart';

/// 文字欄位的全形英數字自動轉半形小寫（2026-11-06 使用者：記帳如果輸入全形的
/// `ＦＯＯＤＰＡＮＤＡ`，自動偵測並改成正常的 `foodpanda`）。
///
/// 只動全形的英文字母、數字跟全形空白：
/// - `Ａ–Ｚ`、`ａ–ｚ` → 半形**小寫** `a–z`
/// - `０–９` → `0–9`
/// - 全形空白（U+3000）→ 一般空白
///
/// 中文標點（，。！？（）「」）一律不動，不然中文句子會被改壞；已經是半形的字母
/// 大小寫也不動（打 `FoodPanda` 就是 `FoodPanda`）。
class HalfWidthTextFormatter extends TextInputFormatter {
  const HalfWidthTextFormatter();

  /// 轉換後的字串（每個字元一對一替換，長度不變，游標位置不用重算）。
  static String normalize(String s) {
    var changed = false;
    final b = StringBuffer();
    for (final r in s.runes) {
      var o = r;
      if (r >= 0xFF21 && r <= 0xFF3A) {
        o = r - 0xFF21 + 0x61; // Ａ–Ｚ → a–z
      } else if (r >= 0xFF41 && r <= 0xFF5A) {
        o = r - 0xFF41 + 0x61; // ａ–ｚ → a–z
      } else if (r >= 0xFF10 && r <= 0xFF19) {
        o = r - 0xFF10 + 0x30; // ０–９ → 0–9
      } else if (r == 0x3000) {
        o = 0x20;
      }
      if (o != r) changed = true;
      b.writeCharCode(o);
    }
    return changed ? b.toString() : s;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalize(newValue.text);
    if (identical(text, newValue.text) || text == newValue.text) {
      return newValue;
    }
    // 有轉換時清掉輸入法的組字狀態（跟金額欄位同一個做法），游標位置不變。
    return TextEditingValue(
      text: text,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// 常用的一組：全形轉半形。
const halfWidthFormatters = <TextInputFormatter>[HalfWidthTextFormatter()];
