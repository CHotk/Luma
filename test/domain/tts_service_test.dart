import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/services/tts_service.dart';

/// 發音（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：日文直接用系統語音（不試有道）；
/// 有道那段要真的播放器回應，測試環境的假播放器不會回，所以沒測；挑 Google 語音、
/// 沒有就不指定、指定失敗不會壞；空字串不念。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> tts;
  late List<MethodCall> player;
  late Object? voices;
  late bool failSetVoice;

  setUp(() {
    tts = [];
    player = [];
    voices = [
      {'name': 'Samantha', 'locale': 'en-US'},
      {'name': 'Google 日本語', 'locale': 'ja-JP'},
      {'name': 'Google US English', 'locale': 'en-US'},
    ];
    failSetVoice = false;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      c,
    ) async {
      tts.add(c);
      if (c.method == 'getVoices') return voices;
      if (c.method == 'setVoice' && failSetVoice) {
        throw PlatformException(code: 'no');
      }
      return 1;
    });
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (c) async {
        player.add(c);
        return null;
      });
    }
  });

  tearDown(() {
    for (final name in [
      'flutter_tts',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  TtsService make() =>
      TtsService(language: 'en-US', languageJa: 'ja-JP', pitch: 1.0);

  testWidgets('空字串不念', (tester) async {
    final s = make();
    await tester.pump();
    tts.clear();
    await s.speak('   ');
    expect(tts.where((c) => c.method == 'speak'), isEmpty);
  });

  testWidgets('日文：不試有道，直接用系統語音、挑 Google 日文語音', (tester) async {
    final s = make();
    await tester.pump();
    await s.speak('あ', japanese: true);
    expect(player, isEmpty);
    expect(
      tts.firstWhere((c) => c.method == 'setVoice').arguments,
      containsPair('name', 'Google 日本語'),
    );
    expect(tts.last.method, 'speak');
    expect(tts.last.arguments, 'あ');
  });

  testWidgets('語音清單同一種語言只查一次（快取）', (tester) async {
    final s = make();
    await tester.pump();
    await s.speak('あ', japanese: true);
    await s.speak('い', japanese: true);
    expect(tts.where((c) => c.method == 'getVoices'), hasLength(1));
    expect(tts.where((c) => c.method == 'speak'), hasLength(2));
  });

  testWidgets('沒有 Google 語音＝不指定；指定語音失敗也照念', (tester) async {
    voices = [
      {'name': 'Kyoko', 'locale': 'ja-JP'},
    ];
    final s = make();
    await tester.pump();
    await s.speak('い', japanese: true);
    expect(tts.where((c) => c.method == 'setVoice'), isEmpty);
    expect(tts.last.method, 'speak');

    voices = 'getVoices 不支援';
    final s2 = make();
    await tester.pump();
    await s2.speak('う', japanese: true);
    expect(tts.last.method, 'speak');

    voices = [
      {'name': 'Google 日本語', 'locale': 'ja-JP'},
    ];
    failSetVoice = true;
    final s3 = make();
    await tester.pump();
    await s3.speak('え', japanese: true);
    expect(tts.last.arguments, 'え');
  });
}
