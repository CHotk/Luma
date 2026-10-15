import 'package:flutter/foundation.dart';

import '../services/youtube_api_service.dart';

/// 全 App 共用的「觀看次數」表：影片 id → 次數（2026-10-15）。跟
/// [YtVideoTags] 同一套做法：來源只有影片快取，每次讀寫都 [publish]
/// 到這裡；影片列手上那份沒帶次數（例如剛從 API 抓的第一頁）就從這裡補，
/// 背景更新完畫面自己跟著變。
abstract final class YtVideoViews {
  static final notifier = ValueNotifier<Map<String, int>>(const {});

  static void publish(Iterable<YoutubeVideo> videos) {
    Map<String, int>? next;
    final current = notifier.value;
    for (final v in videos) {
      final n = v.viewCount;
      if (n == null || (next ?? current)[v.videoId] == n) continue;
      next ??= {...current};
      next[v.videoId] = n;
    }
    if (next != null) notifier.value = next;
  }
}
