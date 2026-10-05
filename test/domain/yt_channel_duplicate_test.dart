import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/yt_tracker.dart';

YtChannel _channel(String id, {String url = '', String ytId = ''}) => YtChannel(
  id: id,
  name: id,
  categoryId: null,
  url: url,
  youtubeChannelId: ytId,
  addedAt: DateTime(2026, 10, 1),
);

void main() {
  final channels = [
    _channel('a', url: 'https://www.youtube.com/@SomeChannel', ytId: 'UCaaa'),
    _channel('b', url: 'https://www.youtube.com/@%E5%B0%8F%E6%98%8E/videos'),
    _channel('c', url: 'https://www.youtube.com/channel/UCccc'),
  ];

  test('同一個 @帳號：大小寫、手機版網址、後面多接路徑都算重複', () {
    for (final url in [
      'https://youtube.com/@somechannel',
      'https://m.youtube.com/@SOMECHANNEL/featured',
      'youtube.com/@SomeChannel?si=xyz',
    ]) {
      expect(findDuplicateYtChannel(channels, url: url)?.id, 'a', reason: url);
    }
  });

  test('中文帳號：編碼版跟中文版網址算同一個', () {
    expect(
      findDuplicateYtChannel(channels, url: 'https://www.youtube.com/@小明')?.id,
      'b',
    );
  });

  test('API 抓到的頻道 ID 對上已存的 ID 或 /channel/ 網址都算重複', () {
    expect(
      findDuplicateYtChannel(channels, youtubeChannelId: 'UCaaa')?.id,
      'a',
    );
    expect(
      findDuplicateYtChannel(channels, youtubeChannelId: 'UCccc')?.id,
      'c',
    );
  });

  test('不一樣的頻道、空網址不會誤判', () {
    expect(
      findDuplicateYtChannel(channels, url: 'https://youtube.com/@other'),
      isNull,
    );
    expect(findDuplicateYtChannel(channels, url: ''), isNull);
    expect(findDuplicateYtChannel([_channel('x')], url: ''), isNull);
  });
}
