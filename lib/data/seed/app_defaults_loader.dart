import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../../domain/jp_review_config.dart';
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
  const TtsDefaults({
    required this.language,
    required this.languageJa,
    required this.pitch,
  });
  final String language;

  /// 日文軌道（50音練習／考試）發音用的語言代碼，見
  /// `lib/domain/services/tts_service.dart` 的說明。
  final String languageJa;
  final double pitch;
}

Future<TtsDefaults> loadTtsDefaults() async {
  final doc = await _loadDoc();
  return TtsDefaults(
    language: doc['ttsLanguage'] as String,
    languageJa: doc['ttsLanguageJa'] as String,
    pitch: (doc['ttsPitch'] as num).toDouble(),
  );
}

/// 啟動畫面要停留多久。唯一來源，沒有 code 端備份值。
Future<Duration> loadSplashHoldDuration() async {
  final doc = await _loadDoc();
  return Duration(milliseconds: doc['splashHoldMs'] as int);
}

/// 給日文首頁當 [JpReviewConfig] 預設值。
///
/// 跟 [loadDefaultRulesConfig] 同一種保險政策：讀不到、壞掉、缺欄位
/// 都會退回 `lib/domain/jp_review_config.dart` 建構子裡寫死的值，
/// 因為這也是首頁核心數字（進度環、下一輪清單）的一部分，跟排序
/// 偏好那種壞了無所謂的設定不一樣。
Future<JpReviewConfig> loadJpReviewConfig() async {
  try {
    final doc = await _loadDoc();
    return JpReviewConfig.fromJson(Map<String, dynamic>.from(doc));
  } catch (_) {
    return const JpReviewConfig();
  }
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

/// 手寫練習重播「下載該次筆跡」編 GIF 用的參數。跟 [loadJpReviewConfig]
/// 同一種保險政策：讀不到、壞掉就退回這裡建構子的預設值，不會讓這個
/// 小功能拖累其他畫面（2026-09-18 使用者要求：GIF 相關設定移到專門
/// 設定檔）。
class KanaGifDefaults {
  const KanaGifDefaults({
    this.frameIntervalMs = 30,
    this.maxFrames = 150,
    this.size = 320,
    this.numColors = 64,
  });

  /// 每一格間隔幾毫秒，愈小愈流暢，檔案愈大、編碼愈久。
  final int frameIntervalMs;

  /// 格數上限，避免寫很久的字格數／檔案大小／編碼時間跟著無限增加。
  final int maxFrames;

  /// 輸出的正方形邊長（像素）。
  final int size;

  /// 色盤大小，這種近似單色的畫面不需要到 256 色。
  final int numColors;
}

Future<KanaGifDefaults> loadKanaGifDefaults() async {
  try {
    final doc = await _loadDoc();
    return KanaGifDefaults(
      frameIntervalMs: doc['kanaGifFrameIntervalMs'] as int,
      maxFrames: doc['kanaGifMaxFrames'] as int,
      size: doc['kanaGifSize'] as int,
      numColors: doc['kanaGifNumColors'] as int,
    );
  } catch (_) {
    return const KanaGifDefaults();
  }
}

/// R2 bucket 名稱。唯一來源，沒有 code 端備份值——讀不到、格式壞掉
/// 就是設定檔本身有問題，該直接讓例外往上炸，不要悄悄退回一個寫死的
/// 值假裝沒事：那樣的話改了設定檔以為換了 bucket，實際上因為某個
/// 原因讀取失敗，App 還是偷偷連到舊的（或錯的）bucket，比直接炸掉
/// 更難察覺（2026-09-23 使用者糾正：讀不到就該讓它壞，不要用寫死的
/// 值蓋過去）。
Future<String> loadR2BucketName() async {
  final doc = await _loadDoc();
  return doc['r2BucketName'] as String;
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
