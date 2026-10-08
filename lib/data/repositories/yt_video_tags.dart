import 'package:flutter/foundation.dart';

import '../services/youtube_api_service.dart';

/// 全 App 共用的「影片類型標籤」表：影片 id → 是不是 Shorts／直播
/// （2026-10-08 使用者回報：類型標籤偶爾有幾部沒補上，切到「影片」
/// 分類才突然出現）。
///
/// 標籤的來源只有影片快取（[YtVideoCacheStore]）：它每次讀或寫都把
/// 看到的標籤 [publish] 到這裡。影片列畫標籤時用 [apply] 從這張表補，
/// 不再靠各頁自己把標籤複製進手上那份清單——頻道頁的「全部」、更早
/// 影片、類型清單、分類頁「依影片」各有各的清單，以前漏改哪一份，那份
/// 的影片就一直沒標籤。現在不管哪一頁，只要快取標到了，畫面上的標籤
/// 就跟著出現。
abstract final class YtVideoTags {
  static final notifier =
      ValueNotifier<Map<String, ({bool? short, bool? live})>>(const {});

  /// 把這批影片已知的標籤併進表裡；有新資訊才通知畫面重畫。已知的值
  /// 不會被 null 蓋掉。
  static void publish(Iterable<YoutubeVideo> videos) {
    Map<String, ({bool? short, bool? live})>? next;
    final current = notifier.value;
    for (final v in videos) {
      if (v.isShort == null && v.isLive == null) continue;
      final old = (next ?? current)[v.videoId];
      final merged = (
        short: v.isShort ?? old?.short,
        live: v.isLive ?? old?.live,
      );
      if (old == merged) continue;
      next ??= {...current};
      next[v.videoId] = merged;
    }
    if (next != null) notifier.value = next;
  }

  /// 影片本身沒帶的類型從表裡補上（本身有的不動）。
  static YoutubeVideo apply(
    YoutubeVideo v, [
    Map<String, ({bool? short, bool? live})>? table,
  ]) {
    final t = (table ?? notifier.value)[v.videoId];
    if (t == null) return v;
    var r = v;
    if (r.isShort == null && t.short != null) r = r.withShort(t.short!);
    if (r.isLive == null && t.live != null) r = r.withLive(t.live!);
    return r;
  }
}
