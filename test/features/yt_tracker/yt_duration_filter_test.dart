import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/features/yt_tracker/yt_duration_filter.dart';

YoutubeVideo _v(int seconds) => YoutubeVideo(
  videoId: 'v$seconds',
  title: 't',
  publishedAt: DateTime(2026, 10, 1),
  thumbnailUrl: '',
  duration: Duration(seconds: seconds),
);

// 2026-10-06 使用者定的規則：上限算進去、算到秒；6:00 算「2–6 分」。
void main() {
  final under2 = YtDurationFilter.preset(YtDurationPreset.under2);
  final from2to6 = YtDurationFilter.preset(YtDurationPreset.from2to6);
  final from6to20 = YtDurationFilter.preset(YtDurationPreset.from6to20);

  test('交界：上限算進去', () {
    expect(under2.matches(_v(120)), isTrue);
    expect(from2to6.matches(_v(120)), isFalse);
    expect(from2to6.matches(_v(121)), isTrue);
    expect(from2to6.matches(_v(360)), isTrue);
    expect(from6to20.matches(_v(360)), isFalse);
    expect(from6to20.matches(_v(361)), isTrue);
    expect(from6to20.matches(_v(1200)), isTrue);
    expect(from6to20.matches(_v(1201)), isFalse);
  });

  test('自訂：整數分鐘，拉到 40 是 40+ 不設上限', () {
    const custom = YtDurationFilter.custom(20, 40);
    expect(custom.matches(_v(1200)), isFalse);
    expect(custom.matches(_v(1201)), isTrue);
    expect(custom.matches(_v(3 * 3600)), isTrue);
    expect(custom.rangeLabel, '20–40+ 分');
    expect(const YtDurationFilter.custom(0, 15).rangeLabel, '15 分內');
    expect(const YtDurationFilter.custom(8, 35).rangeLabel, '8–35 分');
  });

  test('時長沒抓到的影片只在「不限」出現', () {
    final noDuration = YoutubeVideo(
      videoId: 'x',
      title: 't',
      publishedAt: DateTime(2026, 10, 1),
      thumbnailUrl: '',
    );
    expect(const YtDurationFilter.any().matches(noDuration), isTrue);
    expect(under2.matches(noDuration), isFalse);
  });
}
