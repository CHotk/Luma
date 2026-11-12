import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/features/music/music_add_from_yt.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// 從 YT 加歌（2026-11-12 補到 95%）：貼網址（有金鑰查到、查不到；沒金鑰用 oEmbed
/// 查到、查不到；查的時候壞掉）、不像網址、剪貼簿空的、清空、從 YT 管理挑（選頻道、
/// 頻道沒影片、回上一層、打歌名找）、帶歌名進來直接搜。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef ref;
  late BuildContext ctx;
  String? clip;

  Future<MemoryStore> host(WidgetTester tester, {String? key = 'KEY'}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' && clip != null
          ? {'text': clip}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final store = MemoryStore();
    await seedYt(tester, store);
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          ytApiKeyProvider.overrideWith((_) => key),
          musicDataProvider.overrideWith((_) => seedMusicData()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, r, _) {
                ref = r;
                ctx = c;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
    return store;
  }

  http.Client client({
    int oembed = 200,
    bool noVideo = false,
    bool boom = false,
  }) => MockClient((req) async {
    if (boom) throw Exception('沒網路');
    if (req.url.path == '/oembed') {
      return oembed == 200
          ? http.Response.bytes(
              utf8.encode(
                jsonEncode({'title': 'oEmbed 的標題', 'author_name': '上傳者'}),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )
          : http.Response('no', oembed);
    }
    if (noVideo && req.url.pathSegments.last == 'videos') {
      return http.Response('{"items":[]}', 200);
    }
    return FakeYoutube().client().send(req).then(http.Response.fromStream);
  });

  Future<void> open(WidgetTester tester, http.Client c, {String? search}) =>
      http.runWithClient(() async {
        showMusicAddFromYt(ctx, searchTitle: search);
        await settle(tester, 6);
      }, () => c);

  const url = 'https://www.youtube.com/watch?v=abcdefghijk';

  for (final (name, key, opts) in <(String, String?, Map<String, Object>)>[
    ('有金鑰查到', 'KEY', {}),
    ('有金鑰查不到', 'KEY', {'noVideo': true}),
    ('沒金鑰 oEmbed 查到', null, {}),
    ('沒金鑰 oEmbed 查不到', null, {'oembed': 404}),
    ('查的時候壞掉', 'KEY', {'boom': true}),
  ]) {
    testWidgets('剪貼簿是影片網址：$name', (tester) async {
      clip = url;
      await host(tester, key: key);
      final c = client(
        oembed: opts['oembed'] as int? ?? 200,
        noVideo: opts['noVideo'] as bool? ?? false,
        boom: opts['boom'] as bool? ?? false,
      );
      await open(tester, c);
      await http.runWithClient(() => settle(tester, 4), () => c);
      expect(tester.takeException(), isNull);
      // ＋ 打開加到音樂的面板再關掉。
      final plus = find.text('＋');
      if (plus.evaluate().isNotEmpty) {
        await tester.tap(plus.first);
        await settle(tester, 3);
        await closeOverlays(tester);
      }
      await tester.tap(find.byTooltip('清空'));
      await settle(tester, 2);
    });
  }

  testWidgets('不像網址、剪貼簿空的、按貼上', (tester) async {
    clip = '隨便的字';
    await host(tester);
    final c = client();
    await open(tester, c);
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 3);
    }, () => c);
    expect(find.text('這不像 YouTube 影片網址'), findsOneWidget);
    clip = null;
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 3);
    }, () => c);
    expect(find.textContaining('剪貼簿是空的'), findsOneWidget);
    clip = url;
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 6);
    }, () => c);
    expect(tester.takeException(), isNull);
  });

  testWidgets('從 YT 管理挑：選頻道、看影片、回上一層、打歌名找', (tester) async {
    clip = null;
    await host(tester);
    final c = client();
    await open(tester, c);
    await tester.tap(find.text('或從 YT 管理挑（選頻道、打歌名找）'));
    await settle(tester, 3);
    final ch = find.text('頻道a');
    if (ch.evaluate().isNotEmpty) {
      await tester.tap(ch.first);
      await settle(tester, 4);
      expect(find.textContaining('頻道a 的影片'), findsWidgets);
      final back = find.byIcon(Icons.arrow_back_rounded);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
        await settle(tester, 2);
      }
    }
    // 換分類 chip。
    for (final chip
        in tester.widgetList<Widget>(find.byType(ChoiceChip)).toList()) {
      (chip as ChoiceChip).onSelected?.call(true);
      await settle(tester, 1);
    }
    await tester.enterText(find.byType(TextField).last, '影片 1');
    await settle(tester, 4);
    expect(find.textContaining('影片 1'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, '');
    await settle(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('帶歌名進來：直接搜', (tester) async {
    clip = null;
    await host(tester);
    final c = client();
    await open(tester, c, search: '影片 2');
    expect(tester.takeException(), isNull);
    expect(await readClipboardText(), isNull);
  });
}
