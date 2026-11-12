import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_api_key_store.dart';
import 'package:lume/features/yt_tracker/yt_api_key_dialog.dart';

import '../../support/poke.dart';

/// API 金鑰對話框（2026-11-12 補到 95%）：剪貼簿像金鑰才秀「貼上並儲存」（AIza 39 字、
/// 寬鬆字元集、太短、有空白、網址、跟目前一樣、讀剪貼簿失敗）、儲存、空白當清除、
/// 清除金鑰、取消、顯示／隱藏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef hostRef;
  late BuildContext hostCtx;

  Future<MemoryStore> host(
    WidgetTester tester, {
    Object? clipboard,
    String? key,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          if (clipboard is Exception) throw clipboard;
          return clipboard == null ? null : {'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final store = MemoryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          ytApiKeyProvider.overrideWith((_) => key),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, ref, _) {
                hostRef = ref;
                hostCtx = c;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
    showYtApiKeyDialog(hostCtx, hostRef);
    await settle(tester, 3);
    return store;
  }

  const aiza = 'AIzaSyA1234567890abcdefghijklmnopqrstuv';

  for (final (clip, shows) in <(Object?, bool)>[
    (aiza, true),
    ('abcdefghij_klmnopqrst-uv', true),
    ('short_key', false),
    ('有 空白 的 一句 話 abcdefghijklmnop', false),
    ('https://www.youtube.com/@abc', false),
    ('a' * 80, false),
    ('', false),
    (null, false),
    (PlatformException(code: 'denied'), false),
  ]) {
    testWidgets('剪貼簿是「$clip」：${shows ? '秀' : '不秀'}貼上並儲存', (tester) async {
      await host(tester, clipboard: clip);
      expect(find.text('貼上並儲存'), shows ? findsOneWidget : findsNothing);
      expect(find.text('目前沒有儲存金鑰'), findsOneWidget);
      expect(find.text('清除金鑰'), findsNothing);
    });
  }

  testWidgets('剪貼簿跟目前存的一樣：不秀', (tester) async {
    await host(tester, clipboard: aiza, key: aiza);
    expect(find.text('貼上並儲存'), findsNothing);
    expect(find.text('目前有金鑰儲存中'), findsOneWidget);
  });

  testWidgets('貼上並儲存：存進去、關掉', (tester) async {
    final store = await host(tester, clipboard: aiza);
    await tester.tap(find.text('貼上並儲存'));
    await settle(tester);
    expect(find.text('YouTube API 金鑰'), findsNothing);
    expect(hostRef.read(ytApiKeyProvider), aiza);
    expect(await tester.runAsync(() => YtApiKeyStore(store).load()), aiza);
  });

  testWidgets('手動輸入：顯示／隱藏、前後空白去掉、儲存', (tester) async {
    await host(tester);
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(field().obscureText, isFalse);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(field().obscureText, isTrue);
    await tester.enterText(find.byType(TextField), '  我的金鑰  ');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(hostRef.read(ytApiKeyProvider), '我的金鑰');
  });

  testWidgets('有金鑰：欄位帶目前的；全刪掉按儲存＝清除；清除金鑰；取消不動', (tester) async {
    final store = await host(tester, key: 'OLD');
    expect(find.text('OLD'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(hostRef.read(ytApiKeyProvider), 'OLD');

    showYtApiKeyDialog(hostCtx, hostRef);
    await settle(tester, 3);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(hostRef.read(ytApiKeyProvider), isNull);

    hostRef.read(ytApiKeyProvider.notifier).state = 'AGAIN';
    await tester.runAsync(() => YtApiKeyStore(store).save('AGAIN'));
    showYtApiKeyDialog(hostCtx, hostRef);
    await settle(tester, 3);
    await tester.tap(find.text('清除金鑰'));
    await settle(tester);
    expect(hostRef.read(ytApiKeyProvider), isNull);
    expect(await tester.runAsync(() => YtApiKeyStore(store).load()), isNull);
  });
}
