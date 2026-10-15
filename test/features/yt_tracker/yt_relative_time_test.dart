import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

/// YT 時間（2026-10-15 使用者要求）：三個月內寫多久前，更早寫日期。
void main() {
  final now = DateTime(2026, 10, 15, 12);

  test('三個月內：多久前', () {
    expect(ytRelativeTime(DateTime(2026, 10, 15, 11, 30), now: now), '30 分鐘前');
    expect(ytRelativeTime(DateTime(2026, 10, 15, 2), now: now), '10 小時前');
    expect(ytRelativeTime(DateTime(2026, 10, 3), now: now), '12 天前');
    expect(ytRelativeTime(DateTime(2026, 8, 1), now: now), '2 個月前');
    expect(ytRelativeTime(DateTime(2026, 7, 15, 12), now: now), '3 個月前');
  });

  test('超過三個月：日期', () {
    expect(ytRelativeTime(DateTime(2026, 7, 14), now: now), '2026/07/14');
    expect(ytRelativeTime(DateTime(2024, 3, 5), now: now), '2024/03/05');
  });
}
