import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/debug/app_log.dart';

/// 除錯訊息（2026-11-13 第 19 項）：一般訊息只留最近 300 筆、錯誤一筆都不丟；
/// 錯誤會叫持久化、一般訊息不會；讀回持久化的錯誤不重複、照時間排；看過的時間；
/// JSON 來回（缺 isError 當錯誤、沒有裝置）；暫時追蹤印出帶毫秒的時間。
void main() {
  setUp(() {
    AppLog.entries.value = const [];
    AppLog.persistError = null;
  });

  test('一般訊息只留最近 300 筆，錯誤一筆都不丟', () {
    AppLog.add('最早的錯誤', isError: true);
    for (var i = 0; i < 305; i++) {
      AppLog.add('訊息 $i');
    }
    final all = AppLog.entries.value;
    expect(all.where((e) => !e.isError).length, 300);
    expect(all.first.message, '最早的錯誤');
    expect(all.any((e) => e.message == '訊息 0'), isFalse);
    expect(all.last.message, '訊息 304');
  });

  test('錯誤叫持久化，一般訊息不叫；沒接持久化也不會壞', () {
    AppLog.add('沒接', isError: true);
    final saved = <AppLogEntry>[];
    AppLog.persistError = saved.add;
    AppLog.add('一般');
    AppLog.add('錯誤', isError: true);
    expect(saved.map((e) => e.message), ['錯誤']);
    expect(saved.single.device, isNotNull);
  });

  test('讀回持久化的錯誤：已經有的不重複、空的不動、照時間排', () {
    final a = AppLogEntry(
      message: 'a',
      at: DateTime(2026, 1, 2),
      isError: true,
      device: 'd',
    );
    final b = AppLogEntry(
      message: 'b',
      at: DateTime(2026, 1, 1),
      isError: true,
    );
    AppLog.restore([a]);
    final before = AppLog.entries.value;
    AppLog.restore([a]);
    expect(identical(AppLog.entries.value, before), isTrue);
    AppLog.restore(const []);
    AppLog.restore([a, b]);
    expect(AppLog.entries.value.map((e) => e.message), ['b', 'a']);
  });

  test('看過的時間', () {
    final t = DateTime.now();
    AppLog.markViewed();
    expect(AppLog.lastViewedAt.isBefore(t), isFalse);
  });

  test('JSON 來回；缺 isError 當錯誤、沒有裝置', () {
    final e = AppLogEntry(
      message: 'm',
      at: DateTime(2026, 3, 4, 5, 6),
      isError: false,
      device: 'Android・Chrome',
    );
    final back = AppLogEntry.fromJson(e.toJson());
    expect(back.identity, e.identity);
    expect(back.isError, isFalse);
    final old = AppLogEntry.fromJson({
      'at': '2026-03-04T05:06:00.000',
      'message': '舊的',
    });
    expect(old.isError, isTrue);
    expect(old.device, isNull);
  });

  test('暫時追蹤：印出 時:分:秒.毫秒 [tag] 訊息', () {
    final printed = <String?>[];
    final original = debugPrint;
    debugPrint = (m, {wrapWidth}) => printed.add(m);
    addTearDown(() => debugPrint = original);
    debugTrace('置頂', '按了');
    expect(
      printed.single,
      matches(RegExp(r'^\d\d:\d\d:\d\d\.\d{3} \[置頂\] 按了$')),
    );
  });
}
