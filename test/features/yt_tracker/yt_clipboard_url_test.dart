import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

void main() {
  test('自動貼上只認 YouTube 頻道網址，隨便複製的文字不填', () {
    expect(looksLikeYtChannelUrl('https://www.youtube.com/@abc'), isTrue);
    expect(
      looksLikeYtChannelUrl('https://m.youtube.com/channel/UCxyz'),
      isTrue,
    );
    expect(looksLikeYtChannelUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
    expect(looksLikeYtChannelUrl('今天晚餐吃什麼'), isFalse);
    expect(looksLikeYtChannelUrl('https://www.google.com'), isFalse);
  });
}
