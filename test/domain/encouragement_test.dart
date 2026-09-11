import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/encouragement.dart';

/// 這幾條測試是要確保「每天不一樣，輪完才重來」真的成立。
/// 用日期算出來的東西很容易寫錯又不會當掉，所以得盯著。
void main() {
  group('Encouragement', () {
    test('剛好五十句，而且沒有重複', () {
      expect(Encouragement.lines.length, 50);
      expect(Encouragement.lines.toSet().length, 50, reason: '有重複的句子');
    });

    test('同一天永遠是同一句，不受時分秒影響', () {
      final morning = DateTime(2026, 9, 11, 7, 30);
      final night = DateTime(2026, 9, 11, 23, 59);
      expect(
        Encouragement.forDate(morning),
        Encouragement.forDate(night),
      );
    });

    // 起點要對齊輪次的開頭，不然五十天會跨到下一輪去，
    // 那時候換了順序，本來就可能撞到已經出現過的句子。
    final cycleStart = DateTime(2026, 1, 1);

    List<String> cycleFrom(int offset) => [
      for (var i = 0; i < 50; i++)
        Encouragement.forDate(cycleStart.add(Duration(days: offset + i))),
    ];

    test('一輪五十天，每天都不一樣', () {
      expect(cycleFrom(0).toSet().length, 50, reason: '一輪之內有句子重複出現');
    });

    test('第二輪會換一個順序，不是照抄第一輪', () {
      final first = cycleFrom(0);
      final second = cycleFrom(50);
      expect(second, isNot(equals(first)), reason: '兩輪順序一樣就不叫重新抽');
      expect(second.toSet().length, 50, reason: '第二輪之內也不能重複');
    });
  });
}
