import 'package:flutter/foundation.dart';

/// 這次打開 App 才從 YouTube 抓到、原本快取裡沒有的影片（2026-10-15
/// 使用者定義的「NEW」：當下快取沒有、API 抓到的）。影片列看這張表在
/// 縮圖左上角標「NEW」（影片列設計稿第 2 版）。
///
/// 只記在記憶體：關掉 App 再開就不算新了（那時快取已經有了）。來源只有
/// [YtVideoCacheStore] 把 API 抓到的影片併進快取那一刻；同步從別台帶來的
/// 不算。一個頻道第一次抓（快取原本是空的）也不算，不然整個頻道都是 NEW。
abstract final class YtNewVideos {
  static final notifier = ValueNotifier<Set<String>>(const {});

  static void add(Iterable<String> ids) {
    final next = {...notifier.value, ...ids};
    if (next.length != notifier.value.length) notifier.value = next;
  }
}
