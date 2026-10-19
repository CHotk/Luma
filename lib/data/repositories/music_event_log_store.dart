import 'dart:convert';

import '../storage/key_value_store.dart';

/// 音樂的一筆異動（2026-10-19 使用者要求）：加了哪首、改了什麼、不喜歡…
class MusicEvent {
  const MusicEvent({
    required this.id,
    required this.at,
    required this.text,
    this.versionId,
  });

  final String id;
  final DateTime at;

  /// 寫給人看的一句話（「加入《晴天》（演唱・周杰倫）」）。
  final String text;

  /// 跟哪一首（版本）有關；歌手改名這種是 null。
  final String? versionId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'text': text,
    if (versionId != null) 'v': versionId,
  };

  static MusicEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = DateTime.tryParse(j['at'] as String? ?? '');
    if (t == null) return null;
    return MusicEvent(
      id: j['id'] as String? ?? t.toIso8601String(),
      at: t,
      text: j['text'] as String? ?? '',
      versionId: j['v'] as String?,
    );
  }
}

/// 音樂的異動紀錄：只會變多、一筆都不刪；跨裝置同步是聯集（照 id）。
class MusicEventLogStore {
  MusicEventLogStore(this._store);

  final KeyValueStore _store;

  static const _key = 'music.event_log.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'music_event_log.json';

  Future<List<MusicEvent>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    try {
      return decode(raw);
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<MusicEvent> log) => _store.write(_key, encode(log));

  static String encode(List<MusicEvent> log) =>
      jsonEncode([for (final e in log) e.toJson()]);

  static List<MusicEvent> decode(String raw) => [
    for (final e in (jsonDecode(raw) as List)) ?MusicEvent.fromJson(e),
  ];

  /// 聯集，舊到新。
  static List<MusicEvent> merge(List<MusicEvent> a, List<MusicEvent> b) => {
    for (final e in [...a, ...b]) e.id: e,
  }.values.toList()..sort((x, y) => x.at.compareTo(y.at));
}
