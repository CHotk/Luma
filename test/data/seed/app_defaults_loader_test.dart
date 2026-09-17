import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/seed/app_defaults_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app_defaults.yaml 的學習規則真的被讀進來，不是掉進 fallback', () async {
    final rules = await loadDefaultRulesConfig();
    expect(rules.confirmRight, 4);
    expect(rules.recoveryRatio, 5);
    expect(rules.roundSize, 10);
  });

  test('app_defaults.yaml 的發音設定真的被讀進來', () async {
    final tts = await loadTtsDefaults();
    expect(tts.language, 'en-US');
    expect(tts.pitch, 1.0);
  });

  test('app_defaults.yaml 的啟動畫面停留時間真的被讀進來', () async {
    final hold = await loadSplashHoldDuration();
    expect(hold, const Duration(milliseconds: 1600));
  });

  test('app_defaults.yaml 的日文複習排程參數真的被讀進來', () async {
    final config = await loadJpReviewConfig();
    expect(config.dailyKanaTarget, 5);
    expect(config.dailyMinutesTarget, 10);
    expect(config.masteryPracticeCount, 3);
    expect(config.reviewStaleDays, 7);
  });
}
