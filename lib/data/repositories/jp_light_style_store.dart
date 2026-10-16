import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 五十音櫻花樹用哪種畫法（2026-10-16 使用者要求：保留原本那一版，但預設
/// 用 ChatGPT 產圖的那一版，設計稿
/// `design-history/已選擇完成/點亮/2026-10-16_日文櫻花點亮重新設計五版.html` 第 6 版）。
enum JpLightStyle {
  /// ChatGPT 產的圖疊起來：黃昏背景＋樹＋花團＋飄花瓣。預設。
  gpt,

  /// 原本程式畫的樹枝＋圓形花苞（2026-10-15 設計稿第 4 版）。
  classic;

  static JpLightStyle fromName(String? name) =>
      name == 'classic' ? JpLightStyle.classic : JpLightStyle.gpt;
}

class JpLightStyleStore {
  JpLightStyleStore(this._store);

  final KeyValueStore _store;

  static const _key = 'jp_light.style.v1';
  static const defaultStyle = JpLightStyle.gpt;

  /// 雲端上的檔名。
  static const cloudKey = 'jp_light_style.json';

  /// 跨裝置同步，見 [StampedSettingStore]。
  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<JpLightStyle> load() async =>
      JpLightStyle.fromName(await record.loadValue());

  Future<void> save(JpLightStyle style) => record.saveValue(style.name);
}
