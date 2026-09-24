import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../domain/models/yt_tracker.dart';
import 'youtube_api_service.dart';

/// 挖掘出來的一個新頻道（還沒加進 App）。
class DiscoveredChannel {
  const DiscoveredChannel({
    required this.channelId,
    required this.title,
    required this.avatarUrl,
    required this.url,
    required this.description,
    required this.subscriberCount,
    required this.videoCount,
    required this.uploadsPlaylistId,
    this.lastUploadAt,
  });

  final String channelId;
  final String title;
  final String avatarUrl;
  final String url;
  final String description;
  final int subscriberCount;
  final int videoCount;
  final String uploadsPlaylistId;
  final DateTime? lastUploadAt;
}

/// `channels.list` 回來的原始資料（篩選前）。
class ChannelCandidate {
  const ChannelCandidate({
    required this.channelId,
    required this.title,
    required this.avatarUrl,
    required this.customUrl,
    required this.description,
    required this.subscriberCount,
    required this.subscribersHidden,
    required this.videoCount,
    required this.uploadsPlaylistId,
  });

  final String channelId;
  final String title;
  final String avatarUrl;

  /// `@handle`（含 @），沒有就是空字串。
  final String customUrl;
  final String description;
  final int? subscriberCount;
  final bool subscribersHidden;
  final int videoCount;
  final String uploadsPlaylistId;
}

/// 篩選門檻（2026-09-24 使用者提供的挖掘流程：訂閱數範圍、影片數排除空
/// 帳號、排除隱藏訂閱數、排除很久沒更新的頻道）。
const discoverMinSubscribers = 1000;
const discoverMinVideos = 10;
const discoverMaxIdleDays = 180;

/// 這個頻道 App 裡是不是已經有了（不管在哪個分類）。用頻道 ID、網址裡的
/// `UC…` ID、`@handle` 三種方式比對，因為有些頻道還沒解析過頻道 ID。
bool isKnownChannel({
  required String channelId,
  required String customUrl,
  required Iterable<YtChannel> existing,
}) {
  final handle = customUrl.toLowerCase();
  for (final c in existing) {
    if (c.youtubeChannelId == channelId) return true;
    final url = c.url.toLowerCase();
    if (url.contains(channelId.toLowerCase())) return true;
    if (handle.isNotEmpty && handle.length > 1) {
      final existingHandle = RegExp(r'@[\w.\-]+').firstMatch(url)?.group(0);
      if (existingHandle == handle) return true;
    }
  }
  return false;
}

/// 品質篩選（不含「最近有沒有上傳」，那要另外打 API）。
bool passesQuality(ChannelCandidate c) =>
    !c.subscribersHidden &&
    (c.subscriberCount ?? 0) >= discoverMinSubscribers &&
    c.videoCount >= discoverMinVideos;

/// 挖掘新頻道（2026-09-24 使用者要求，流程參考使用者貼的方法）：
/// 1. 「種子頻道滾雪球」：挑幾個 App 裡已有的頻道，讀它們首頁的「精選／
///    推薦頻道」區塊（`channelSections.list`，1 單位配額一次）。
/// 2. 不夠的話「以影片找頻道」：用分類名稱搜尋影片（`search.list`，100 單位
///    一次，最多 2 次），取影片所屬的頻道。
/// 3. 排除 App 已有的、批次驗證（`channels.list` 一次 50 個，1 單位）、
///    門檻篩選、最後檢查最新上傳日期（`playlistItems.list`，1 單位一個）。
/// Google Custom Search 那條路要另外的搜尋引擎金鑰，這裡先不做。
class ChannelDiscoveryService {
  ChannelDiscoveryService(this.apiKey, {Random? random, http.Client? client})
    : _random = random ?? Random(),
      _client = client ?? http.Client();

  final String apiKey;
  final Random _random;
  final http.Client _client;

  static const _base = 'https://www.googleapis.com/youtube/v3';

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse(
      '$_base/$path',
    ).replace(queryParameters: {...params, 'key': apiKey});
    final res = await _client
        .get(uri)
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw YoutubeApiException('連線 YouTube 逾時，檢查網路後重試'),
        );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final error = body['error'] as Map<String, dynamic>?;
      final message = error?['message'] ?? 'HTTP ${res.statusCode}';
      throw YoutubeApiException('YouTube API 錯誤：$message');
    }
    return body;
  }

  Future<List<DiscoveredChannel>> discover({
    required List<YtChannel> existing,
    required List<String> keywords,
    int count = 10,
    void Function(String status)? onProgress,
  }) async {
    final candidateIds = <String>{};
    bool isNew(String id) =>
        !isKnownChannel(channelId: id, customUrl: '', existing: existing);

    // 1. 種子頻道的精選／推薦頻道
    final seeds = existing.where((c) => c.youtubeChannelId.isNotEmpty).toList()
      ..shuffle(_random);
    var seedTried = 0;
    for (final seed in seeds.take(6)) {
      seedTried++;
      onProgress?.call('讀取「${seed.name}」推薦的頻道…（$seedTried/6）');
      try {
        final body = await _getJson('channelSections', {
          'part': 'contentDetails',
          'channelId': seed.youtubeChannelId,
        });
        for (final item in (body['items'] as List? ?? const [])) {
          final details = (item as Map)['contentDetails'] as Map?;
          final ids = details?['channels'] as List?;
          if (ids == null) continue;
          for (final id in ids) {
            if (isNew(id as String)) candidateIds.add(id);
          }
        }
      } on YoutubeApiException {
        rethrow;
      } catch (_) {
        // 某個種子頻道讀不到（沒有推薦區塊等），換下一個。
      }
      if (candidateIds.length >= count * 6) break;
    }

    // 2. 不夠就用分類名稱搜尋影片，取影片所屬頻道
    if (candidateIds.length < count * 3 && keywords.isNotEmpty) {
      final shuffled = [...keywords]..shuffle(_random);
      const orders = ['relevance', 'date', 'viewCount'];
      for (var i = 0; i < 2 && i < shuffled.length; i++) {
        final q = shuffled[i];
        onProgress?.call('搜尋「$q」相關影片找新頻道…');
        final body = await _getJson('search', {
          'part': 'snippet',
          'type': 'video',
          'q': q,
          'maxResults': '50',
          'order': orders[_random.nextInt(orders.length)],
          'regionCode': 'TW',
          'relevanceLanguage': 'zh-Hant',
        });
        for (final item in (body['items'] as List? ?? const [])) {
          final id =
              ((item as Map)['snippet'] as Map?)?['channelId'] as String?;
          if (id != null && isNew(id)) candidateIds.add(id);
        }
      }
    }

    if (candidateIds.isEmpty) return const [];

    // 3. 批次驗證
    final ids = candidateIds.toList()..shuffle(_random);
    final capped = ids.take(150).toList();
    final candidates = <ChannelCandidate>[];
    for (var i = 0; i < capped.length; i += 50) {
      onProgress?.call('驗證 ${capped.length} 個候選頻道…');
      final chunk = capped.sublist(i, min(i + 50, capped.length));
      final body = await _getJson('channels', {
        'part': 'snippet,statistics,contentDetails',
        'id': chunk.join(','),
        'maxResults': '50',
      });
      for (final item in (body['items'] as List? ?? const [])) {
        final c = _parseCandidate(item as Map<String, dynamic>);
        if (c != null) candidates.add(c);
      }
    }

    final passed =
        candidates
            .where(
              (c) =>
                  passesQuality(c) &&
                  !isKnownChannel(
                    channelId: c.channelId,
                    customUrl: c.customUrl,
                    existing: existing,
                  ),
            )
            .toList()
          ..shuffle(_random);

    // 4. 最新上傳日期檢查，湊滿 count 個就停
    final now = DateTime.now();
    final found = <DiscoveredChannel>[];
    for (final c in passed) {
      if (found.length >= count) break;
      onProgress?.call('檢查「${c.title}」是否還在更新…（已挖到 ${found.length}/$count）');
      final last = await _latestUpload(c.uploadsPlaylistId);
      if (last == null || now.difference(last).inDays > discoverMaxIdleDays) {
        continue;
      }
      found.add(
        DiscoveredChannel(
          channelId: c.channelId,
          title: c.title,
          avatarUrl: c.avatarUrl,
          url: c.customUrl.isNotEmpty
              ? 'https://www.youtube.com/${c.customUrl}'
              : 'https://www.youtube.com/channel/${c.channelId}',
          description: _shorten(c.description),
          subscriberCount: c.subscriberCount ?? 0,
          videoCount: c.videoCount,
          uploadsPlaylistId: c.uploadsPlaylistId,
          lastUploadAt: last,
        ),
      );
    }
    return found;
  }

  ChannelCandidate? _parseCandidate(Map<String, dynamic> item) {
    final snippet = item['snippet'] as Map<String, dynamic>?;
    final stats = item['statistics'] as Map<String, dynamic>?;
    final uploads =
        ((item['contentDetails'] as Map?)?['relatedPlaylists']
                as Map?)?['uploads']
            as String?;
    if (snippet == null || uploads == null) return null;
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? const {};
    final avatar =
        (thumbs['high'] ?? thumbs['medium'] ?? thumbs['default'])
            as Map<String, dynamic>?;
    final hidden = stats?['hiddenSubscriberCount'] == true;
    return ChannelCandidate(
      channelId: item['id'] as String,
      title: snippet['title'] as String? ?? '',
      avatarUrl: (avatar?['url'] as String? ?? '').replaceFirst(
        RegExp(r'=s\d+.*$'),
        '=s160-c-k-c0x00ffffff-no-rj',
      ),
      customUrl: snippet['customUrl'] as String? ?? '',
      description: snippet['description'] as String? ?? '',
      subscriberCount: hidden
          ? null
          : int.tryParse('${stats?['subscriberCount'] ?? ''}'),
      subscribersHidden: hidden,
      videoCount: int.tryParse('${stats?['videoCount'] ?? ''}') ?? 0,
      uploadsPlaylistId: uploads,
    );
  }

  Future<DateTime?> _latestUpload(String uploadsPlaylistId) async {
    try {
      final body = await _getJson('playlistItems', {
        'part': 'contentDetails',
        'playlistId': uploadsPlaylistId,
        'maxResults': '1',
      });
      final items = body['items'] as List? ?? const [];
      if (items.isEmpty) return null;
      final published =
          ((items.first as Map)['contentDetails'] as Map?)?['videoPublishedAt']
              as String?;
      return published == null ? null : DateTime.tryParse(published);
    } on YoutubeApiException {
      return null;
    }
  }

  String _shorten(String s) {
    final oneLine = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= 80 ? oneLine : '${oneLine.substring(0, 80)}…';
  }
}
