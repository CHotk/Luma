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

    test('打滿答案的長度才算打完，前後空白不算', () {
      expect(SpellJudge.isComplete(input: 'towe', answer: 'towel'), isFalse);
      expect(SpellJudge.isComplete(input: 'towel', answer: 'towel'), isTrue);
      expect(SpellJudge.isComplete(input: ' towe ', answer: 'towel'), isFalse);
    });

    test('標點符號不算數，句型才打得過（使用者 2026-09-16 決定）', () {
      expect(
        SpellJudge.isCorrect(input: 'I dont care', answer: "I don't care."),
        isTrue,
        reason: '漏打撇號、句號都不該算錯',
      );
      expect(
        SpellJudge.isCorrect(input: "I don't care.", answer: "I don't care."),
        isTrue,
        reason: '有打標點符號當然也要算對，不是反過來要求不能打',
      );
    });

    test('打滿的判斷也要用拿掉標點符號之後的長度', () {
      // "I don't care." 拿掉標點符號、空白收成一個之後是 "i dont care"，11 字。
      expect(
        SpellJudge.isComplete(input: 'I dont care', answer: "I don't care."),
        isTrue,
        reason: '沒打標點符號也該算打完，不然打字的人永遠湊不滿原始字數',
      );
    });

    test('拿掉標點符號不動大小寫，畫面的空格格數要用這個', () {
      expect(SpellJudge.stripPunctuation("I don't care."), 'I dont care');
      expect(SpellJudge.stripPunctuation('Weather'), 'Weather');
    });
  });
}
