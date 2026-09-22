import 'dart:convert';

import 'package:http/http.dart' as http;

/// YouTube Data API v3 回錯誤（金鑰不對、配額用完、頻道不存在……）時
/// 丟這個，訊息已經是給使用者看的中文，呼叫端直接顯示就好。
class YoutubeApiException implements Exception {
  YoutubeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class YoutubeChannelInfo {
  const YoutubeChannelInfo({
    required this.channelId,
    required this.uploadsPlaylistId,
    required this.title,
    required this.avatarUrl,
  });

  final String channelId;

  /// 頻道的「已上傳影片」播放清單 ID——抓最新影片是去讀這個播放清單，
  /// 不是用 `search.list`（那個一次要吃 100 單位配額，讀播放清單只要
  /// 1 單位，划算很多）。
  final String uploadsPlaylistId;
  final String title;
  final String avatarUrl;
}

class YoutubeVideo {
  const YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.publishedAt,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final DateTime publishedAt;
  final String thumbnailUrl;

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// 直接打 YouTube Data API v3，純前端 HTTP 呼叫，不用整包 googleapis
/// SDK。金鑰只在記憶體（見 `app/providers.dart` 的 `ytApiKeyProvider`），
/// 不會被這個 service 存起來。
class YoutubeApiService {
  const YoutubeApiService(this.apiKey);

  final String apiKey;

  static const _base = 'https://www.googleapis.com/youtube/v3';

  /// 從頻道網址解析出 `@handle`——YouTube Data API 的 `forHandle` 參數
  /// 可以直接吃這個字串去查頻道，不用自己先轉成頻道 ID。網址格式抓不
  /// 到 handle（例如根本沒填網址）就回傳 null。
  static String? parseHandle(String url) {
    final match = RegExp(r'@[\w.\-]+').firstMatch(url);
    return match?.group(0);
  }

  Future<YoutubeChannelInfo> fetchChannelInfo(String handle) async {
    final uri = Uri.parse('$_base/channels').replace(
      queryParameters: {
        'part': 'snippet,contentDetails',
        'forHandle': handle,
        'key': apiKey,
      },
    );
    final res = await http.get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw YoutubeApiException(_errorMessage(res.statusCode, body));
    }
    final items = (body['items'] as List?) ?? const [];
    if (items.isEmpty) {
      throw YoutubeApiException('找不到頻道 $handle，確認網址裡的 @帳號 對不對');
    }
    final item = items.first as Map<String, dynamic>;
    final snippet = item['snippet'] as Map<String, dynamic>;
    final contentDetails = item['contentDetails'] as Map<String, dynamic>;
    final uploads =
        (contentDetails['relatedPlaylists'] as Map<String, dynamic>)['uploads']
            as String;
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>;
    final avatar =
        (thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default'])
            as Map<String, dynamic>;
    return YoutubeChannelInfo(
      channelId: item['id'] as String,
      uploadsPlaylistId: uploads,
      title: snippet['title'] as String,
      avatarUrl: avatar['url'] as String,
    );
  }

  Future<List<YoutubeVideo>> fetchRecentVideos(
    String uploadsPlaylistId, {
    int maxResults = 6,
  }) async {
    final uri = Uri.parse('$_base/playlistItems').replace(
      queryParameters: {
        'part': 'snippet',
        'playlistId': uploadsPlaylistId,
        'maxResults': '$maxResults',
        'key': apiKey,
      },
    );
    final res = await http.get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw YoutubeApiException(_errorMessage(res.statusCode, body));
    }
    final items = ((body['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final item in items) _videoFrom(item),
    ];
  }

  YoutubeVideo _videoFrom(Map<String, dynamic> item) {
    final snippet = item['snippet'] as Map<String, dynamic>;
    final resourceId = snippet['resourceId'] as Map<String, dynamic>;
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>;
    final thumb =
        (thumbnails['medium'] ?? thumbnails['default']) as Map<String, dynamic>;
    return YoutubeVideo(
      videoId: resourceId['videoId'] as String,
      title: snippet['title'] as String,
      publishedAt: DateTime.parse(snippet['publishedAt'] as String),
      thumbnailUrl: thumb['url'] as String,
    );
  }

  String _errorMessage(int status, Map<String, dynamic> body) {
    final error = body['error'] as Map<String, dynamic>?;
    final errors = (error?['errors'] as List?)?.cast<Map<String, dynamic>>();
    final reason = (errors != null && errors.isNotEmpty)
        ? errors.first['reason'] as String?
        : null;
    if (reason == 'quotaExceeded') return '今天的 API 配額用完了，明天（美國太平洋時間午夜）會重置';
    if (status == 400 || status == 403) {
      return 'API 金鑰不對，或是被限制擋住了（檢查金鑰的網域/API 限制設定）';
    }
    return (error?['message'] as String?) ?? 'YouTube API 發生錯誤（狀態碼 $status）';
  }
}
