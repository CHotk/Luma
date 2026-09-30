import '../storage/key_value_store.dart';

/// 內嵌播放器要用哪種外層呈現方式（2026-09-30 使用者要求：先做了下滑
/// 收合式，後來又想要可拖曳／可收合成小泡泡的浮動視窗，兩種都留著，
/// 存成設定讓使用者自己選、能隨時切換，不是做新的就把舊的換掉）。
enum YtEmbedPlayerStyle {
  /// 從下方滑出的面板，只佔下半螢幕，往下滑或點旁邊收合。
  bottomSheet,

  /// 可拖曳到任意位置、可收合成邊角小泡泡的浮動視窗，收合後影片在背景
  /// 繼續播放，不會被關掉。
  floating;

  static YtEmbedPlayerStyle fromName(String? name) => switch (name) {
    'floating' => YtEmbedPlayerStyle.floating,
    _ => YtEmbedPlayerStyle.bottomSheet,
  };
}

class YtEmbedPlayerStyleStore {
  YtEmbedPlayerStyleStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.embed_player_style.v1';
  static const defaultStyle = YtEmbedPlayerStyle.bottomSheet;

  Future<YtEmbedPlayerStyle> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultStyle;
    return YtEmbedPlayerStyle.fromName(raw);
  }

  Future<void> save(YtEmbedPlayerStyle style) =>
      _store.write(_key, style.name);
}
