import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../../domain/rules_config.dart';

/// 讀 `assets/config/app_defaults.yaml`。
///
/// 這份檔案是「調數字不用重新編譯」的設定集中地，內容跟保險機制的
/// 說明都寫在該檔案開頭，這裡只是解析。除了學習規則（見
/// [loadDefaultRulesConfig] 的說明）以外，其餘欄位都是唯一來源，
/// 讀不到、格式壞掉、缺欄位就直接讓例外往上炸，不做 try/catch 假裝
/// 沒事——App 早就有「出錯就出錯」的慣例，這裡沒理由特別客氣。
Future<YamlMap> _loadDoc() async {
  final raw = await rootBundle.loadString('assets/config/app_defaults.yaml');
  return loadYaml(raw) as YamlMap;
}

/// 給全新使用者（還沒存過設定）當 [RulesConfig] 預設值。
///
/// 這是目前唯一還留著 code 端保險預設值的部分：讀取沿用既有的
/// `RulesConfig.fromJson`（原本就是給使用者存在本機的舊設定做欄位
/// 補齊用），檔案讀不到、壞掉、或漏欄位都會照 `fromJson` 的邏輯退回
/// `lib/domain/rules_config.dart` 建構子裡寫死的值，不算額外成本才
/// 值得留。使用者已經存過設定之後就不會再讀到這裡。
Future<RulesConfig> loadDefaultRulesConfig() async {
  try {
    final doc = await _loadDoc();
    return RulesConfig.fromJson(Map<String, dynamic>.from(doc));
  } catch (_) {
    return const RulesConfig();
  }
}

/// 發音設定。唯一來源，沒有 code 端備份值。
class TtsDefaults {
  const TtsDefaults({required this.language, required this.pitch});
  final String language;
  final double pitch;
}

Future<TtsDefaults> loadTtsDefaults() async {
  final doc = await _loadDoc();
  return TtsDefaults(
    language: doc['ttsLanguage'] as String,
    pitch: (doc['ttsPitch'] as num).toDouble(),
  );
}

/// 啟動畫面要停留多久。唯一來源，沒有 code 端備份值。
Future<Duration> loadSplashHoldDuration() async {
  final doc = await _loadDoc();
  return Duration(milliseconds: doc['splashHoldMs'] as int);
}

/// 單字庫標籤下拉選單的自訂排序。唯一來源，沒有 code 端備份值——
/// 但跟發音／啟動畫面不同，這個讀失敗不會讓例外往上炸，是直接退回
/// [empty]（純字母序），因為排序偏好不影響資料對不對，壞掉最多就是
/// 排列比較普通，不值得為這個讓 App 打不開。
class LibraryTagOrder {
  const LibraryTagOrder({
    required this.adjacentGroups,
    required this.trailingOrder,
  });

  static const empty = LibraryTagOrder(adjacentGroups: [], trailingOrder: []);

  /// 要相黏在一起的標籤群組，群組內順序就是顯示順序。
  final List<List<String>> adjacentGroups;

  /// 要照這個順序排在一般標籤清單最後的標籤。
  final List<String> trailingOrder;
}

Future<LibraryTagOrder> loadLibraryTagOrder() async {
  try {
    final doc = await _loadDoc();
    final groups = (doc['libraryTagAdjacentGroups'] as List? ?? const [])
        .map((g) => (g as List).map((e) => e.toString()).toList())
        .toList();
    final trailing = (doc['libraryTagTrailingOrder'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return LibraryTagOrder(adjacentGroups: groups, trailingOrder: trailing);
  } catch (_) {
    return LibraryTagOrder.empty;
  }
}
