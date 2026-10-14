import 'dart:convert';

import '../services/youtube_api_service.dart';
import '../storage/key_value_store.dart';

/// 播放清單裡的一部影片。存的是加進來那時候的標題、縮圖、頻道（之後頻道
/// 刪掉、影片下架也看得到是什麼），不是只存 id。
class YtPlaylistItem {
  const YtPlaylistItem({
    required this.video,
    required this.channelName,
    this.channelId,
    required this.addedAt,
  });

  final YoutubeVideo video;
  final String? channelId;
  final String channelName;
  final DateTime addedAt;

  String get videoId => video.videoId;

  Map<String, dynamic> toJson() => {
    'video': video.toJson(),
    'channelId': channelId,
    'channelName': channelName,
    'addedAt': addedAt.toIso8601String(),
  };

  factory YtPlaylistItem.fromJson(Map<String, dynamic> j) => YtPlaylistItem(
    video: YoutubeVideo.fromJson(j['video'] as Map<String, dynamic>),
    channelId: j['channelId'] as String?,
    channelName: j['channelName'] as String? ?? '',
    addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime(2000),
  );
}

/// YT 播放清單（2026-10-14 使用者選設計稿第 1 版「YouTube 式」）。
///
/// 每份清單是一筆「內容＋改的時間」，同步時一份一份比，後改的贏
/// （見 `R2SyncService.syncYtPlaylists`）；刪掉的清單留墓碑
/// （[deletedAt]），別台才知道是刪了不是還沒同步到。
class YtPlaylist {
  const YtPlaylist({
    required this.id,
    required this.name,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// 「稍後觀看」：一定有、不能改名或刪除。
  static const laterId = 'later';

  final String id;
  final String name;

  /// 清單裡的順序就是顯示順序（新加的放最前面）。
  final List<YtPlaylistItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLater => id == laterId;
  bool contains(String videoId) => items.any((i) => i.videoId == videoId);

  YtPlaylist copyWith({
    String? name,
    List<YtPlaylistItem>? items,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => YtPlaylist(
    id: id,
    name: name ?? this.name,
    items: items ?? this.items,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'items': [for (final i in items) i.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
  };

  factory YtPlaylist.fromJson(Map<String, dynamic> j) => YtPlaylist(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    items: [
      for (final i in (j['items'] as List? ?? const []))
        YtPlaylistItem.fromJson(i as Map<String, dynamic>),
    ],
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime(2000),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime(2000),
    deletedAt: DateTime.tryParse(j['deletedAt'] as String? ?? ''),
  );

  /// 還沒建過「稍後觀看」時補一份空的，時間給很舊：雲端有就用雲端的。
  static YtPlaylist emptyLater() => YtPlaylist(
    id: laterId,
    name: '稍後觀看',
    createdAt: DateTime(2000),
    updatedAt: DateTime(2000),
  );
}

class YtPlaylistStore {
  YtPlaylistStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.playlists.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'yt_playlists.json';

  /// 全部（含刪掉的墓碑），「稍後觀看」一定在。
  Future<List<YtPlaylist>> loadAll() async {
    final raw = await _store.read(_key);
    var list = <YtPlaylist>[];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list = [
            for (final p in decoded)
              YtPlaylist.fromJson(p as Map<String, dynamic>),
          ];
        }
      } on FormatException {
        // 壞掉的當沒有。
      }
    }
    if (!list.any((p) => p.isLater)) list.insert(0, YtPlaylist.emptyLater());
    return list;
  }

  Future<void> saveAll(List<YtPlaylist> playlists) =>
      _store.write(_key, jsonEncode([for (final p in playlists) p.toJson()]));

  /// 畫面上看得到的：拿掉刪掉的，「稍後觀看」排第一，其他照建立時間。
  static List<YtPlaylist> visible(List<YtPlaylist> all) =>
      [
        for (final p in all)
          if (p.deletedAt == null) p,
      ]..sort((a, b) {
        if (a.isLater != b.isLater) return a.isLater ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });

  /// 兩邊合併：同一份清單比 [YtPlaylist.updatedAt]，後改的贏；只有一邊
  /// 有的直接留下。
  static List<YtPlaylist> merge(List<YtPlaylist> a, List<YtPlaylist> b) {
    final byId = {for (final p in a) p.id: p};
    for (final p in b) {
      final mine = byId[p.id];
      if (mine == null || p.updatedAt.isAfter(mine.updatedAt)) byId[p.id] = p;
    }
    return byId.values.toList();
  }
}
