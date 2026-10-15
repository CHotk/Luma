import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/features/yt_tracker/yt_channel_stats.dart';

/// 簡介分頁的數字（2026-10-15）。
void main() {
  YoutubeVideo v(
    String id,
    DateTime at, {
    int? views,
    int? secs,
    bool? short,
    bool? live,
    DateTime? removed,
  }) => YoutubeVideo(
    videoId: id,
    title: id,
    publishedAt: at,
    thumbnailUrl: '',
    viewCount: views,
    duration: secs == null ? null : Duration(seconds: secs),
    isShort: short,
    isLive: live,
    removedAt: removed,
  );

  test('從快取算：類型、平均長度、星期／時段、最熱門、看過幾部', () {
    // 2026-10-03 是星期六、10-10 也是星期六、10-06 是星期二。
    final s = YtChannelStats.from(
      [
        v(
          'a',
          DateTime(2026, 10, 3, 20),
          views: 100,
          secs: 300,
          short: false,
          live: false,
        ),
        v(
          'b',
          DateTime(2026, 10, 10, 21),
          views: 500,
          secs: 60,
          short: true,
          live: false,
        ),
        v(
          'c',
          DateTime(2026, 10, 6, 9),
          views: 50,
          secs: 3600,
          short: false,
          live: true,
        ),
        v(
          'gone',
          DateTime(2026, 9, 1),
          views: 999,
          removed: DateTime(2026, 10),
        ),
      ],
      viewsOf: (x) => x.viewCount,
      lastWatchedOf: (id) => id == 'a' ? DateTime(2026, 10, 12) : null,
      now: DateTime(2026, 10, 15),
    );
    expect(s.total, 3);
    expect((s.regular, s.shorts, s.live), (1, 1, 1));
    expect(s.avgDuration, const Duration(seconds: 1320));
    expect(s.busiestWeekday, 5); // 星期六
    expect(s.busiestSlot, 3); // 晚上
    expect(s.top.map((x) => x.videoId), ['b', 'a', 'c']);
    expect(s.totalViews, 650);
    expect(s.watched, 1);
    expect(s.lastWatched, DateTime(2026, 10, 12));
    expect(s.first, DateTime(2026, 10, 3, 20));
  });

  test('沒有影片：數字都是空的，不會當掉', () {
    final s = YtChannelStats.from(
      const [],
      viewsOf: (_) => null,
      lastWatchedOf: (_) => null,
    );
    expect(s.total, 0);
    expect(s.busiestWeekday, isNull);
    expect(s.perMonth, isNull);
    expect(s.totalViews, isNull);
  });
}
