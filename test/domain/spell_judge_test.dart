import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/spell_judge.dart';

/// 拼字判定的三條規則是使用者決定的，改動前先看 app-spec.md 第十節。
/// 這幾個測試就是用來擋「好像太嚴，放寬一點好了」這種手癢。
void main() {
  group('SpellJudge', () {
    test('不管大小寫', () {
      expect(SpellJudge.isCorrect(input: 'Weather', answer: 'weather'), isTrue);
      expect(SpellJudge.isCorrect(input: 'WEATHER', answer: 'weather'), isTrue);
    });

    test('前後空白不算錯', () {
      expect(SpellJudge.isCorrect(input: '  towel ', answer: 'towel'), isTrue);
    });

    test('複數算錯', () {
      expect(SpellJudge.isCorrect(input: 'sock', answer: 'socks'), isFalse);
      expect(SpellJudge.isCorrect(input: 'towels', answer: 'towel'), isFalse);
    });

    test('a 和 an 是不同的字', () {
      expect(SpellJudge.isCorrect(input: 'a', answer: 'an'), isFalse);
    });

    test('遮罩只露出第一個字母', () {
      expect(SpellJudge.mask('weather'), 'w _ _ _ _ _ _');
      expect(SpellJudge.mask('a'), 'a');
    });
  });
}
