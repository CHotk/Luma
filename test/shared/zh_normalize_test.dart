import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/text/zh_normalize.dart';

void main() {
  test('簡體關鍵字找得到繁體名稱，反過來也可以', () {
    expect(zhContains('莫兄比特说', '說'), isTrue);
    expect(zhContains('靈佑奇談', '灵佑'), isTrue);
    expect(zhContains('老高與小茉', '与'), isTrue);
    expect(zhContains('Joeman', 'JOE'), isTrue);
  });

  test('不相干的字不會被誤判', () {
    expect(zhContains('靈佑奇談', 'j'), isFalse);
    expect(zhContains('老鳴TV', '奇談'), isFalse);
  });
}
