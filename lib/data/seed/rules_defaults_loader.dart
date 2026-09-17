import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../../domain/rules_config.dart';

/// 讀 `assets/config/rules_defaults.yaml`，給全新使用者（還沒存過設定）當預設值。
///
/// 為什麼要有這個檔案：這樣調整「一輪幾題、幾次算掌握」這類數字
/// 不用重新編譯 App，改完 YAML 直接部署就好。選 YAML 不選 JSON，是因為
/// JSON 沒辦法寫註解，這種每個數字都需要說明才看得懂的設定檔，
/// 沒有註解等於沒人敢改。
///
/// [RulesConfig] 建構子裡原本那組數字還留著當保險——這個檔案讀不到、
/// 格式壞掉、或漏了某個欄位，都會照 `RulesConfig.fromJson` 原本的邏輯
/// 一路 fallback 回那組寫死的值，不會因為這個檔案出包而整個掛掉。
Future<RulesConfig> loadDefaultRulesConfig() async {
  try {
    final raw = await rootBundle.loadString(
      'assets/config/rules_defaults.yaml',
    );
    final doc = loadYaml(raw) as YamlMap;
    return RulesConfig.fromJson(Map<String, dynamic>.from(doc));
  } catch (_) {
    return const RulesConfig();
  }
}
