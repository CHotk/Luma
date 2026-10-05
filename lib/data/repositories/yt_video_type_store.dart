import 'dart:convert';

import '../storage/key_value_store.dart';

/// 一個頻道某一種特殊清單（Shorts＝UUSH、直播＝UULV）掃到哪裡了。
///
/// 2026-10-05 使用者要求：打開頻道時在背景把 Shorts 跟直播清單翻一遍，
/// 讓快取裡的影片一開始就知道自己是哪一類，類型篩選的數字才準。不是
/// 每次都從頭翻到底：
/// - [videoIds]：這份清單裡已經看過的影片 id。
/// - [oldest]／[nextToken]：已經往回翻到哪一天、下一頁從哪接，「全部」
///   清單往下捲變深時，從這裡接著往更早翻，不重翻。
/// - [complete]：整份清單翻完了（或頻道根本沒有這種清單）。
class YtTypeScan {
  const YtTypeScan({
    this.videoIds = const {},
    this.oldest,
    this.nextToken,
    this.complete = false,
  });

  final Set<String> videoIds;
  final DateTime? oldest;
  final String? nextToken;
  final bool complete;

  /// 還沒掃過任何一頁。
  bool get isFresh => oldest == null && !complete;

  /// 這部影片的發布時間在已經掃過的範圍內：不在 [videoIds] 裡就可以確定
  /// 「不是這一類」。範圍外的還不知道。
  bool covers(DateTime publishedAt) =>
      complete || (oldest != null && !publishedAt.isBefore(oldest!));

  Map<String, dynamic> toJson() => {
    'videoIds': videoIds.toList(),
    'oldest': oldest?.toIso8601String(),
    'nextToken': nextToken,
    'complete': complete,
  };

  factory YtTypeScan.fromJson(Map<String, dynamic> json) => YtTypeScan(
    videoIds: {...((json['videoIds'] as List?) ?? const []).cast<String>()},
    oldest: json['oldest'] == null
        ? null
        : DateTime.parse(json['oldest'] as String),
    nextToken: json['nextToken'] as String?,
    complete: json['complete'] as bool? ?? false,
  );
}

/// 存 [YtTypeScan] 的地方，只存在這台裝置。掃描結果本身會寫進影片快取的
/// `isShort`／`isLive`（那份會同步），這裡只是「掃到哪」的進度，換裝置
/// 重新掃一次就好。
class YtVideoTypeStore {
  YtVideoTypeStore(this._store);

  final KeyValueStore _store;

  static String _key(String channelId, String kind) =>
      'yt_tracker.type_scan.$channelId.$kind.v1';

  Future<YtTypeScan> load(String channelId, String kind) async {
    final raw = await _store.read(_key(channelId, kind));
    if (raw == null) return const YtTypeScan();
    return YtTypeScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(String channelId, String kind, YtTypeScan scan) =>
      _store.write(_key(channelId, kind), jsonEncode(scan.toJson()));
}
