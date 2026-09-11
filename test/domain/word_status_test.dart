import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/word.dart';
import 'package:lume/domain/rules_config.dart';

/// 狀態判定是全 App 唯一的真相來源，出題、單字庫、統計都靠它。
/// 改壞了不會當掉，只會讓該練的字默默消失。
void main() {
  const rules = RulesConfig(confirmRight: 3, recoveryRatio: 10);

  Word word({int right = 0, int wrong = 0}) => Word(
    id: 1,
    word: 'test',
    pos: 'n.',
    zh: '測試',
    grade: WordGrade.elementary,
    right: right,
    wrong: wrong,
  );

  group('沒錯過的字', () {
    test('沒考過', () {
      expect(word().statusWith(rules), WordStatus.untested);
    });

    test('答對過但沒到門檻也算待複習', () {
      expect(word(right: 2).statusWith(rules), WordStatus.pending);
    });

    test('答對到門檻就掌握', () {
      expect(word(right: 3).statusWith(rules), WordStatus.confirmed);
    });
  });

  group('錯過的字', () {
    test('錯過就是待複習，就算後來答對過', () {
      expect(word(right: 5, wrong: 1).statusWith(rules), WordStatus.pending);
    });

    test('答對次數達到答錯的十倍才算掌握', () {
      expect(word(right: 9, wrong: 1).statusWith(rules), WordStatus.pending);
      expect(word(right: 10, wrong: 1).statusWith(rules), WordStatus.confirmed);
    });

    test('錯五次要答對五十次', () {
      expect(word(right: 49, wrong: 5).statusWith(rules), WordStatus.pending);
      expect(word(right: 50, wrong: 5).statusWith(rules), WordStatus.confirmed);
    });

    test('倍率可以調', () {
      const loose = RulesConfig(recoveryRatio: 2);
      expect(word(right: 2, wrong: 1).statusWith(loose), WordStatus.confirmed);
    });
  });

  group('離掌握還差幾次', () {
    test('沒錯過的算法是門檻減答對', () {
      expect(word(right: 1).rightNeededFor(rules), 2);
    });

    test('錯過的算法是倍數減答對', () {
      expect(word(right: 4, wrong: 1).rightNeededFor(rules), 6);
    });

    test('已經掌握就是零，但次數不會被清掉', () {
      final mastered = word(right: 12, wrong: 1);
      expect(mastered.rightNeededFor(rules), 0);
      expect(mastered.right, 12, reason: '次數被動到了');
      expect(mastered.wrong, 1, reason: '次數被動到了');
    });
  });

  test('門檻調高之後原本掌握的字會掉回去', () {
    final w = word(right: 3);
    expect(w.statusWith(rules), WordStatus.confirmed);
    expect(
      w.statusWith(const RulesConfig(confirmRight: 5)),
      WordStatus.pending,
      reason: '門檻變嚴就該重新驗證',
    );
  });
}
