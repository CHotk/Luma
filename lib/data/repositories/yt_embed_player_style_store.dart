import '../storage/key_value_store.dart';

/// 內嵌播放器要用哪種外層呈現方式（2026-09-30 使用者要求：一開始是
/// 正中央的 Dialog，改成下滑收合式，後來又想要可拖曳／可收合成小泡泡
/// 的浮動視窗——三種都留著，存成設定讓使用者自己選、能隨時切換切回去，
/// 不是做新的就把舊的換掉，也不是換了就沒得回頭）。
enum YtEmbedPlayerStyle {
  /// 最早的版本：正中央的 [Dialog]，整頁變暗蓋住底下內容。
  centeredDialog,

  /// 從下方滑出的面板，只佔下半螢幕，往下滑或點旁邊收合。
  bottomSheet,

  /// 可拖曳到任意位置、可收合成邊角小泡泡的浮動視窗，收合後影片在背景
  /// 繼續播放，不會被關掉。目前設為預設（2026-09-30 使用者要求）。
  floating;

  static YtEmbedPlayerStyle fromName(String? name) => switch (name) {
    'centeredDialog' => YtEmbedPlayerStyle.centeredDialog,
    'bottomSheet' => YtEmbedPlayerStyle.bottomSheet,
    _ => YtEmbedPlayerStyle.floating,
  };
}

class YtEmbedPlayerStyleStore {
  YtEmbedPlayerStyleStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.embed_player_style.v1';
  static const defaultStyle = YtEmbedPlayerStyle.floating;

  Future<YtEmbedPlayerStyle> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultStyle;
    return YtEmbedPlayerStyle.fromName(raw);
  }

  Future<void> save(YtEmbedPlayerStyle style) => _store.write(_key, style.name);
}
