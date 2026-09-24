import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/services/channel_discovery_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';

YtChannel ch({String id = 'a', String url = '', String ytId = ''}) => YtChannel(
  id: id,
  name: id,
  categoryId: null,
  url: url,
  youtubeChannelId: ytId,
  addedAt: DateTime(2026, 9, 24),
);

ChannelCandidate cand({
  int? subs = 5000,
  bool hidden = false,
  int videos = 50,
}) => ChannelCandidate(
  channelId: 'UCx',
  title: 't',
  avatarUrl: '',
  customUrl: '@x',
  description: '',
  subscriberCount: subs,
  subscribersHidden: hidden,
  videoCount: videos,
  uploadsPlaylistId: 'UUx',
);

void main() {
  test('isKnownChannel：頻道 ID、網址裡的 UC ID、@handle 三種都要能認出來', () {
    expect(
      isKnownChannel(
        channelId: 'UC123',
        customUrl: '',
        existing: [ch(ytId: 'UC123')],
      ),
      isTrue,
    );
    expect(
      isKnownChannel(
        channelId: 'UC123',
        customUrl: '',
        existing: [ch(url: 'https://youtube.com/channel/UC123?si=x')],
      ),
      isTrue,
    );
    expect(
      isKnownChannel(
        channelId: 'UC999',
        customUrl: '@Laogao',
        existing: [ch(url: 'https://youtube.com/@laogao?si=x')],
      ),
      isTrue,
    );
    expect(
      isKnownChannel(
        channelId: 'UC999',
        customUrl: '@other',
        existing: [ch(url: 'https://youtube.com/@laogao')],
      ),
      isFalse,
    );
  });

  test('passesQuality：隱藏訂閱數、訂閱太少、影片太少都要濾掉', () {
    expect(passesQuality(cand()), isTrue);
    expect(passesQuality(cand(hidden: true, subs: null)), isFalse);
    expect(passesQuality(cand(subs: 500)), isFalse);
    expect(passesQuality(cand(videos: 3)), isFalse);
  });
}
