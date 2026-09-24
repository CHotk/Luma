import 'package:flutter_tts/flutter_tts.dart';

/// 單字／句子／假名發音。全 App 共用同一顆 [FlutterTts] 實例，不要每個
/// 畫面或每個語言各自建一個——見 `providers.dart` 的 `ttsServiceProvider`
/// 說明：Web 上兩個實例會搶著註冊瀏覽器 SpeechSynthesis 事件，聲音會
/// 怪怪的。所以英文、日文兩個語言共用同一顆，[speak] 每次呼叫前臨時
/// 切換語言，不是分開建兩個 `TtsService`。
///
/// 語言／音調不寫死在這裡，由 `assets/config/app_defaults.yaml`
/// （`ttsLanguage`／`ttsLanguageJa`／`ttsPitch`）唯一決定，見
/// `ttsServiceProvider`。
class TtsService {
  TtsService({
    required String language,
    required this.languageJa,
    required double pitch,
  }) : _defaultLanguage = language {
    _tts.setLanguage(language);
    _tts.setPitch(pitch);
    // 排隊播放到真正念完才算這次呼叫結束，配合 speak() 裡的 stop()，
    // 連續點按時新的發音會立刻蓋掉前一個，不會兩句疊在一起念。
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts = FlutterTts();
  final String _defaultLanguage;

  /// 日文軌道（50音手寫練習／考試）發音用的語言代碼。
  final String languageJa;

  /// 瀏覽器一個語言底下常常有好幾種語音可選，`flutter_tts` 在 Web 上
  /// 光靠 `setLanguage` 只會挑清單裡第一個符合的語音，不一定是音質好
  /// 的那個——這是英文發音聽起來機械音很重的原因（2026-09-24 使用者
  /// 回報）。這裡額外找一個名字帶 "Google" 的語音（Chrome 內建的
  /// Google 語音，例如「Google US English」「Google 日本語」，音質
  /// 明顯比瀏覽器/系統預設的自然），找到就用 `setVoice` 指定它；找不到
  /// （沒有網路、非 Chrome、或原生平台的 TTS 引擎不支援列語音）就照
  /// 原本 `setLanguage` 選到的語音，不強求。每個語言只查一次，結果
  /// 快取起來，不用每次講話都重新掃一次語音清單。
  final Map<String, Map<String, String>?> _preferredVoiceCache = {};

  Future<void> speak(String text, {bool japanese = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final language = japanese ? languageJa : _defaultLanguage;
    await _tts.stop();
    await _tts.setLanguage(language);
    await _applyPreferredVoice(language);
    await _tts.speak(trimmed);
  }

  Future<void> _applyPreferredVoice(String language) async {
    if (!_preferredVoiceCache.containsKey(language)) {
      _preferredVoiceCache[language] = await _findGoogleVoice(language);
    }
    final voice = _preferredVoiceCache[language];
    if (voice == null) return;
    try {
      await _tts.setVoice(voice);
    } catch (_) {
      // 這台裝置的引擎不支援指定語音（或語音清單在這之間變了），
      // 忽略就好，畫面不該因為挑不到最佳語音就整個壞掉。
    }
  }

  Future<Map<String, String>?> _findGoogleVoice(String language) async {
    try {
      final voices = await _tts.getVoices as List;
      for (final raw in voices) {
        final map = Map<String, dynamic>.from(raw as Map);
        final locale = (map['locale'] ?? '').toString();
        final name = (map['name'] ?? '').toString();
        if (locale.toLowerCase().startsWith(language.toLowerCase()) &&
            name.toLowerCase().contains('google')) {
          return {'name': name, 'locale': locale};
        }
      }
    } catch (_) {
      // getVoices 在這個平台不支援就當作沒有偏好語音，不算錯誤。
    }
    return null;
  }
}
