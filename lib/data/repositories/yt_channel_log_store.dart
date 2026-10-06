import 'dart:convert';
import 'dart:math';

import '../storage/key_value_store.dart';

/// 頻道紀錄裡的一件事（2026-10-06 使用者要求：每個頻道要有 log，記哪天
/// 加進來、換分類、刪除、永久刪除、還原……）。「看了哪支影片」不存在
/// 這裡，看影片的時間戳本來就在 `YtVideoWatchStore`，顯示時再跟這個頻道
/// 的影片快取對起來，不重複存一份。
enum YtChannelEventType {
  /// 加進來。[YtChannelEvent.detail] 的 `category` 是當時的分類名稱，
  /// `via` 有值代表是「挖掘新頻道」挖到的（挖到的關鍵字／推薦來源），
  /// `revived` 是 `true` 代表是永久刪除過、手動新增時救回來的。
  added,

  /// 換分類，`from`／`to` 是當時的分類名稱。`reason` 有值代表不是使用者
  /// 自己搬的（例如原本的分類被刪掉了）。
  moved,

  /// 改名，`from`／`to` 是名稱。
  renamed,
  pinned,
  unpinned,
  cold,
  uncold,
  deleted,
  purged,
  restored,

  /// 從待評鑑分到一般（2026-10-06）。
  normal,
}

class YtChannelEvent {
  const YtChannelEvent({
    required this.id,
    required this.channelId,
    required this.at,
    required this.type,
    this.detail = const {},
  });

  /// 隨機 id，多裝置合併時用來去重（同一件事不會因為兩台都同步過就變兩筆）。
  final String id;
  final String channelId;
  final DateTime at;
  final YtChannelEventType type;
  final Map<String, String> detail;

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'at': at.toIso8601String(),
    'type': type.name,
    if (detail.isNotEmpty) 'detail': detail,
  };

  /// 不認得的事件類型（之後新版本加的）回傳 null，舊版本讀到就略過，
  /// 不會整份紀錄讀不出來。
  static YtChannelEvent? tryFromJson(Map<String, dynamic> json) {
    final type = YtChannelEventType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (type == null) return null;
    return YtChannelEvent(
      id: json['id'] as String,
      channelId: json['channelId'] as String,
      at: DateTime.parse(json['at'] as String),
      type: type,
      detail: {
        for (final MapEntry(:key, :value)
            in ((json['detail'] as Map?) ?? const {}).entries)
          '$key': '$value',
      },
    );
  }
}

/// 所有頻道的紀錄存成一份清單，只會新增、不會改也不會刪（跟英文作答
/// 紀錄同一個「只增不改」原則）。同步時兩邊依 id 取聯集。
class YtChannelLogStore {
  YtChannelLogStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.channel_log.v1';
  static final _random = Random();

  /// 產生一個不會撞的 id（時間＋亂數）。
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 32).toRadixString(36)}';

  Future<List<YtChannelEvent>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtChannelEvent.tryFromJson)
        .whereType<YtChannelEvent>()
        .toList();
  }

  Future<List<YtChannelEvent>> forChannel(String channelId) async => [
    for (final e in await loadAll())
      if (e.channelId == channelId) e,
  ];

  Future<void> addAll(List<YtChannelEvent> events) async {
    if (events.isEmpty) return;
    await _write([...await loadAll(), ...events]);
  }

  /// 雲端的紀錄併進來（依 id 去重），回傳實際多了幾筆。
  Future<int> mergeFromCloud(List<YtChannelEvent> cloud) async {
    final local = await loadAll();
    final known = {for (final e in local) e.id};
    final fresh = [
      for (final e in cloud)
        if (!known.contains(e.id)) e,
    ];
    if (fresh.isNotEmpty) await _write([...local, ...fresh]);
    return fresh.length;
  }

  Future<void> _write(List<YtChannelEvent> all) =>
      _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
}
