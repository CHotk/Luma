import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/half_width_input.dart';

/// 文字欄位的全形英數字自動轉半形小寫：ＦＯＯＤＰＡＮＤＡ → foodpanda。
void main() {
  test('全形英文字母（大小寫都是）、數字、空白轉成半形小寫', () {
    expect(HalfWidthTextFormatter.normalize('ＦＯＯＤＰＡＮＤＡ'), 'foodpanda');
    expect(HalfWidthTextFormatter.normalize('ＦｏｏｄＰａｎｄａ'), 'foodpanda');
    expect(HalfWidthTextFormatter.normalize('７－ＥＬＥＶＥＮ'), '7－eleven');
    expect(HalfWidthTextFormatter.normalize('ＦＯＯＤ　ＰＡＮＤＡ'), 'food panda');
    expect(HalfWidthTextFormatter.normalize('１２３'), '123');
  });

  test('中文跟中文標點不動；本來就是半形的字母大小寫也不動', () {
    expect(HalfWidthTextFormatter.normalize('鼎泰豐，聚餐！（朋友）'), '鼎泰豐，聚餐！（朋友）');
    expect(HalfWidthTextFormatter.normalize('FoodPanda'), 'FoodPanda');
    expect(HalfWidthTextFormatter.normalize('Uber Eats 外送'), 'Uber Eats 外送');
    expect(HalfWidthTextFormatter.normalize(''), '');
  });

  test('輸入過濾：打全形馬上變半形小寫，游標位置不變、組字狀態清掉', () {
    const f = HalfWidthTextFormatter();
    final out = f.formatEditUpdate(
      const TextEditingValue(text: 'ＦＯＯ'),
      const TextEditingValue(
        text: 'ＦＯＯＤ',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    expect(out.text, 'food');
    expect(out.selection.baseOffset, 4);
    expect(out.composing, TextRange.empty);
    // 沒有全形字就原樣交回（不動輸入法的組字）。
    const plain = TextEditingValue(
      text: '午餐',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    expect(f.formatEditUpdate(const TextEditingValue(), plain), plain);
  });
}
