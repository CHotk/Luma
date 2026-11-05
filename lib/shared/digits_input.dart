import 'dart:math' as math;

import 'package:flutter/services.dart';

/// 只收數字的輸入過濾（記帳、i88 的金額、餘額、預算都用這個）。
///
/// 跟內建的 `FilteringTextInputFormatter.digitsOnly` 差在兩點（2026-11-03 使用者：
/// 打數字每個下面都有底線，像中文輸入法還沒確定）：
/// 1. **清掉輸入法的「組字中」狀態**：網頁上中文輸入法打數字時，輸入框會把那串字當
///    成還沒確定的組字、畫底線；過濾後把 composing 清空，底線就不會出現。
/// 2. **全形數字（１２３）轉成半形**，不是直接被吃掉。
class DigitsInputFormatter extends TextInputFormatter {
  const DigitsInputFormatter();

  /// 全形數字轉半形，其餘不是數字的字丟掉。
  static String clean(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x30 && r <= 0x39) {
        b.writeCharCode(r);
      } else if (r >= 0xFF10 && r <= 0xFF19) {
        b.writeCharCode(r - 0xFF10 + 0x30);
      }
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = clean(newValue.text);
    final end = newValue.selection.end;
    // 游標位置：游標前面留下幾個數字，游標就放在那個後面。
    final before = end < 0
        ? text.length
        : clean(
            newValue.text.substring(0, math.min(end, newValue.text.length)),
          ).length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: math.min(before, text.length)),
      composing: TextRange.empty,
    );
  }
}
