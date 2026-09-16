import 'package:flutter_tts/flutter_tts.dart';

/// 單字／句子發音。同一份呼叫方式全平台通用：Web 背後是瀏覽器的
/// SpeechSynthesis，Android/iOS 是系統原生 TTS 引擎（`flutter_tts` 自己
/// 依平台切換，這裡不用分支）。目前只唸英文，中文（`word.zh`）不會唸，
/// 這個 App 唸發音要解決的是「背錯英文怎麼唸」，不是中文報讀。
class TtsService {
  TtsService() {
    _tts.setLanguage('en-US');
    // 語速用引擎預設值就好，不要刻意調慢（使用者 2026-09-16 決定）。
    _tts.setPitch(1.0);
    // 排隊播放到真正念完才算這次呼叫結束，配合 speak() 裡的 stop()，
    // 連續點按時新的發音會立刻蓋掉前一個，不會兩句疊在一起念。
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _tts.stop();
    await _tts.speak(trimmed);
  }
}
