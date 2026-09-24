import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/services/youtube_api_service.dart';

void main() {
  test('parseHandle：@handle 網址、/channel/UC 網址都要解析得出來', () {
    expect(
      YoutubeApiService.parseHandle('https://youtube.com/@laogao?si=abc'),
      '@laogao',
    );
    expect(
      YoutubeApiService.parseHandle(
        'https://youtube.com/channel/UCuYFKZ_VPKi4LBw2n4IPRug?si=x',
      ),
      'UCuYFKZ_VPKi4LBw2n4IPRug',
    );
    expect(YoutubeApiService.parseHandle(''), isNull);
  });

  test('Shorts 判斷：有比對結果就用比對結果，沒有才退回 ≤60 秒估計', () {
    YoutubeVideo v({bool? isShort, int? seconds}) => YoutubeVideo(
      videoId: 'a',
      title: 't',
      publishedAt: DateTime(2026, 9, 24),
      thumbnailUrl: '',
      duration: seconds == null ? null : Duration(seconds: seconds),
      isShort: isShort,
    );
    expect(v(seconds: 45).isLikelyShort, isTrue); // 沒比對過：估計
    expect(v(seconds: 45, isShort: false).isLikelyShort, isFalse); // 真實結果優先
    expect(
      v(seconds: 170, isShort: true).isLikelyShort,
      isTrue,
    ); // 3 分鐘內的 Shorts
    final back = YoutubeVideo.fromJson(v(isShort: true).toJson());
    expect(back.isShort, isTrue);
  });
}
