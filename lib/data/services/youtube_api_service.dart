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
    this.duration,
  });

  final String videoId;
  final String title;
  final DateTime publishedAt;
  final String thumbnailUrl;

  /// 影片長度——`playlistItems.list`（抓影片清單那支 API）不會給這個，
  /// 要另外呼叫 `videos.list` 才拿得到，所以先建好物件、抓完清單之後
  /// 再補一次請求把這欄填回去（見 [YoutubeApiService.fetchDurations]）。
  /// 沒填到（那次呼叫失敗、或還沒補）就是 null，畫面上不顯示時長角標，
  /// 不是硬顯示 0:00 誤導人。
  final Duration? duration;

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  /// Shorts／一般影片的分辨啟發式判斷。YouTube Data API **沒有**任何
  /// 欄位直接標「這是 Shorts」——`playlistItems.list`／`videos.list`
  /// 都查不到，官方文件也沒有公開這個資訊，只能用已知線索猜：Shorts
  /// 傳統上限制在 60 秒內（2024 年後 YouTube 放寬到最長 3 分鐘，但
  /// 大多數 Shorts 還是很短），拿 60 秒當門檻是業界最常見的近似值，
  /// 不是 100% 準——例如一部剛好 45 秒的一般直式影片也會被誤判成
  /// Shorts（2026-09-23 使用者問「api給的資料有區分嗎」，答案是沒有，
  /// 這是退而求其次的做法）。[duration] 還沒抓到時回傳 false，不猜。
  bool get isLikelyShort =>
      duration != null && duration!.inSeconds > 0 && duration!.inSeconds <= 60;

  YoutubeVideo withDuration(Duration value) => YoutubeVideo(
    videoId: videoId,
    title: title,
    publishedAt: publishedAt,
    thumbnailUrl: thumbnailUrl,
    duration: value,
  );

  /// 給 `yt_video_cache_store.dart` 落地快取用——只有歷史影片（上傳
  /// 頻率圖那批）會被快取，不是每次抓影片都序列化，見該檔案說明。
  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'publishedAt': publishedAt.toIso8601String(),
    'thumbnailUrl': thumbnailUrl,
    'durationSeconds': duration?.inSeconds,
  };

  factory YoutubeVideo.fromJson(Map<String, dynamic> json) => YoutubeVideo(
    videoId: json['videoId'] as String,
    title: json['title'] as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    thumbnailUrl: json['thumbnailUrl'] as String,
    duration: json['durationSeconds'] == null
        ? null
        : Duration(seconds: json['durationSeconds'] as int),
  );
}

/// YouTube API 的影片長度是 ISO 8601 格式（例如 `PT1H2M10S`、`PT4M13S`），
/// Dart 沒有內建剖析器，自己抓三個數字。抓不到的部分當 0（例如
/// `PT45S` 沒有 H、M 兩段）。
Duration parseIso8601Duration(String iso) {
  final match = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
  if (match == null) return Duration.zero;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

/// 時長角標要顯示的文字，跟 YouTube 網站同一種慣例：超過一小時才顯示
/// 時的那一段，分鐘/秒數固定補零到兩位數。
String formatVideoDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 直接打 YouTube Data API v3，純前端 HTTP 呼叫，不用整包 googleapis
/// SDK。金鑰只在記憶體（見 `app/providers.dart` 的 `ytApiKeyProvider`），
/// 不會被這個 service 存起來。
class YoutubeApiService {
  const YoutubeApiService(this.apiKey);

  final String apiKey;

  static const _base = 'https://www.googleapis.com/youtube/v3';

  /// 所有 API 請求共用：加逾時，避免手機網路怪怪時請求永遠不回來、
  /// 畫面一直轉圈轉不出東西（2026-09-24 使用者回報），逾時會變成看得到
  /// 的錯誤訊息。
  Future<http.Response> _get(Uri uri) => http
      .get(uri)
      .timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw YoutubeApiException('連線 YouTube 逾時，檢查網路後重試'),
      );

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
    final res = await _get(uri);
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
  }) async => (await fetchVideosPage(
    uploadsPlaylistId,
    maxResults: maxResults,
  )).videos;

  /// 抓一頁上傳影片（新到舊），[pageToken] 給上一頁回傳的
  /// `nextPageToken` 就會接著抓更早的——頻道詳情頁「最近影片」往下滑
  /// 到底時繼續載入更早影片用（2026-09-24 使用者要求）。一次呼叫
  /// 1 單位配額。沒有下一頁時 `nextPageToken` 是 null。
  Future<({List<YoutubeVideo> videos, String? nextPageToken})> fetchVideosPage(
    String uploadsPlaylistId, {
    String? pageToken,
    int maxResults = 10,
  }) async {
    final uri = Uri.parse('$_base/playlistItems').replace(
      queryParameters: {
        'part': 'snippet',
        'playlistId': uploadsPlaylistId,
        'maxResults': '$maxResults',
        'key': apiKey,
        if (pageToken != null) 'pageToken': pageToken,
      },
    );
    final res = await _get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw YoutubeApiException(_errorMessage(res.statusCode, body));
    }
    final items = ((body['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return (
      videos: [for (final item in items) _videoFrom(item)],
      nextPageToken: body['nextPageToken'] as String?,
    );
  }

  /// 抓一個頻道「`since` 之後」的全部上傳影片，給統計圖用——不是抓從
  /// 有紀錄以來的完整歷史，只抓最近一段時間（頻道詳情頁傳「近半年」，
  /// 見 `yt_tracker_channel_page.dart`）（2026-09-23 使用者拿掉「全部
  /// 歷史」的範圍，改成半年就好，時間範圍固定，不會因為頻道發片多寡
  /// 讓等待時間跟配額失控）。
  ///
  /// `playlistItems.list` 一次最多回 50 筆，回傳順序是新到舊，靠
  /// `pageToken` 翻頁；每頁檢查最後一筆的發布時間，一旦早於 [since] 就
  /// 不用再翻下一頁——`maxPages` 是額外的安全上限，正常情況半年份的
  /// 影片翻不了幾頁就會被時間篩到，這個上限只是防止極端狀況（例如
  /// `since` 給了很久以前的時間）翻到失控。
  ///
  /// [knownVideoIds] 是呼叫端本機已經快取過的影片 id（見
  /// `yt_video_cache_store.dart`）——`playlistItems.list` 新到舊回傳，
  /// 一旦某一頁「整頁」都已經在快取裡，代表這頁（跟更舊的）之前都已經
  /// 抓過了，直接停止翻頁，不用把整段歷史重抓一次（2026-09-23 使用者
  /// 要求：本機已經有的資料就不用再往後拿，省配額）。回傳的是「這次
  /// 翻頁翻到的」影片，不代表本機快取的全部，合併快取跟這次結果是
  /// 呼叫端的事。
  Future<List<YoutubeVideo>> fetchAllVideos(
    String uploadsPlaylistId, {
    required DateTime since,
    Set<String> knownVideoIds = const {},
    int maxPages = 20,
    void Function(String? nextToken, int offset)? onPage,
  }) async {
    final videos = <YoutubeVideo>[];
    String? pageToken;
    var offset = 0;
    for (var page = 0; page < maxPages; page++) {
      final uri = Uri.parse('$_base/playlistItems').replace(
        queryParameters: {
          'part': 'snippet',
          'playlistId': uploadsPlaylistId,
          'maxResults': '50',
          'key': apiKey,
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final res = await _get(uri);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw YoutubeApiException(_errorMessage(res.statusCode, body));
      }
      final items = ((body['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final pageVideos = items.map(_videoFrom).toList();
      videos.addAll(pageVideos.where((v) => !v.publishedAt.isBefore(since)));
      final oldestInPage = pageVideos.isEmpty
          ? null
          : pageVideos.map((v) => v.publishedAt).reduce(
              (a, b) => a.isBefore(b) ? a : b,
            );
      // 新到舊排序，這頁只要出現任何一部本機已經有的影片，比它更舊的
      // 就一定也都有了，不用再翻下一頁（原本要「整頁都已知」才停，
      // 每次至少多翻一頁、白白多一趟網路來回）。
      final hitKnown = pageVideos.any((v) => knownVideoIds.contains(v.videoId));
      pageToken = body['nextPageToken'] as String?;
      offset += pageVideos.length;
      onPage?.call(pageToken, offset);
      if (pageToken == null) break;
      if (oldestInPage != null && oldestInPage.isBefore(since)) break;
      if (hitKnown) break;
    }
    return videos;
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

  /// 補影片長度——`videos.list` 一次最多吃 50 個 id，`videoIds` 超過 50
  /// 筆（統計圖抓全部歷史影片時很常見）就切成好幾批依序呼叫，每批
  /// 1 單位配額，跟一次呼叫的用量算法一樣，只是拆開打。
  Future<Map<String, Duration>> fetchDurations(List<String> videoIds) async {
    if (videoIds.isEmpty) return const {};
    final result = <String, Duration>{};
    for (var i = 0; i < videoIds.length; i += 50) {
      final batch = videoIds.sublist(
        i,
        i + 50 > videoIds.length ? videoIds.length : i + 50,
      );
      final uri = Uri.parse('$_base/videos').replace(
        queryParameters: {
          'part': 'contentDetails',
          'id': batch.join(','),
          'key': apiKey,
        },
      );
      final res = await _get(uri);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw YoutubeApiException(_errorMessage(res.statusCode, body));
      }
      final items = ((body['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final item in items) {
        result[item['id'] as String] = parseIso8601Duration(
          (item['contentDetails'] as Map<String, dynamic>)['duration']
              as String,
        );
      }
    }
    return result;
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
