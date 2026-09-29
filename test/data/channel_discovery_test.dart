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
  String? country,
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
  country: country,
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

  test('passesQuality：隱藏訂閱數、訂閱太少、影片太少都要濾掉（預設門檻）', () {
    expect(passesQuality(cand()), isTrue);
    expect(passesQuality(cand(hidden: true, subs: null)), isFalse);
    expect(passesQuality(cand(subs: 500)), isFalse);
    expect(passesQuality(cand(videos: 3)), isFalse);
  });

  test('passesQuality：自訂訂閱數範圍', () {
    const c = DiscoverCriteria(minSubscribers: 2000, maxSubscribers: 10000);
    expect(passesQuality(cand(subs: 1000), c), isFalse); // 低於下限
    expect(passesQuality(cand(subs: 5000), c), isTrue);
    expect(passesQuality(cand(subs: 20000), c), isFalse); // 高於上限
    // 沒設上下限就是不限。
    expect(
      passesQuality(
        cand(subs: 999999),
        const DiscoverCriteria(minSubscribers: null),
      ),
      isTrue,
    );
  });

  test('passesQuality：允許隱藏訂閱數的頻道', () {
    const c = DiscoverCriteria(allowHiddenSubscribers: true);
    expect(passesQuality(cand(hidden: true, subs: null), c), isTrue);
  });

  test('passesQuality：限定國家，沒填國家的頻道當不確定排除', () {
    const c = DiscoverCriteria(countries: {'TW', 'JP'});
    expect(passesQuality(cand(country: 'TW'), c), isTrue);
    expect(passesQuality(cand(country: 'US'), c), isFalse);
    expect(passesQuality(cand(country: null), c), isFalse);
    // 不限國家（預設）：沒填國家也算過關。
    expect(passesQuality(cand(country: null)), isTrue);
  });
}
