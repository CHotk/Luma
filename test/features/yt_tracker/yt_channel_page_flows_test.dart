import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/features/yt_tracker/yt_channel_avatar.dart';
import 'package:lume/features/yt_tracker/yt_channel_edit_header.dart';
import 'package:lume/features/yt_tracker/yt_tracker_channel_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 頻道頁的流程（2026-11-12 補到 95%）：編輯（沒改直接完成、改了取消要問、
/// 名稱空白不存、存好）、換頭像（不用圖片、貼網址、重新抓：成功／失敗／沒金鑰／
/// 網址沒 @）、往下捲載入更早（全部、影片、Shorts、直播；API 壞掉）、搜尋
/// （打字搜、注音不搜、Enter 記最近、清掉、收起）、回到頂端鈕（點、拖）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  Future<(MemoryStore, FakeYoutube)> open(
    WidgetTester tester, {
    String id = 'a',
    int fail = 0,
    bool apiKey = true,
    Size size = const Size(390, 860),
  }) async {
    final store = MemoryStore();
    await seedYt(tester, store, apiKey: apiKey);
    final yt = FakeYoutube()..fail = fail;
    await http.runWithClient(() async {
      await pumpPage(
        tester,
        store,
        () => YtTrackerChannelPage(channelId: id),
        size: size,
        overrides: [
          ytApiKeyProvider.overrideWith((_) => apiKey ? 'KEY' : null),
        ],
      );
      await settle(tester, 8);
    }, yt.client);
    return (store, yt);
  }

  Future<void> run(
    WidgetTester tester,
    FakeYoutube yt,
    Future<void> Function() f,
  ) => http.runWithClient(f, yt.client);

  Finder inHeader(String text) => find.descendant(
    of: find.byType(YtChannelEditHeader),
    matching: find.text(text),
  );

  Future<void> done(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
  }

  testWidgets('編輯：沒改直接完成；改了取消先問（繼續改／放棄）；名稱空白不存；存好', (tester) async {
    final (store, yt) = await open(tester);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      expect(find.byType(YtChannelEditHeader), findsOneWidget);
      await tester.tap(find.text('完成'));
      await settle(tester, 3);
      expect(find.byType(YtChannelEditHeader), findsNothing);

      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await tester.tap(inHeader('頻道a'));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byType(YtChannelEditHeader),
          matching: find.byType(TextField),
        ),
        '改過的',
      );
      await tester.pump();
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
      expect(find.text('有改過的東西還沒存'), findsOneWidget);
      await tester.tap(find.text('繼續改'));
      await settle(tester, 3);
      expect(find.byType(YtChannelEditHeader), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
      await tester.tap(find.text('放棄'));
      await settle(tester, 3);
      expect(find.byType(YtChannelEditHeader), findsNothing);

      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await tester.tap(inHeader('頻道a'));
      await tester.pump();
      final field = find.descendant(
        of: find.byType(YtChannelEditHeader),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '   ');
      await tester.pump();
      await tester.tap(find.text('完成'));
      await settle(tester, 3);
      expect(find.text('名稱不能空白'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, 4);
      await tester.enterText(field, ' 新名字 ');
      await tester.pump();
      await tester.tap(find.text('完成'));
      await settle(tester, 4);
    });
    expect(find.text('已儲存'), findsOneWidget);
    final a = (await tester.runAsync(
      () => YtTrackerRepository(store).loadChannels(),
    ))!.firstWhere((c) => c.id == 'a');
    expect(a.name, '新名字');
    await done(tester);
  });

  Future<void> avatarSheet(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(YtChannelEditHeader),
        matching: find.byType(YtChannelAvatar),
      ),
    );
    await settle(tester, 3);
    expect(find.text('從頻道網址重新抓'), findsOneWidget);
  }

  testWidgets('換頭像：貼網址、不用圖片、重新抓成功', (tester) async {
    final (store, yt) = await open(tester);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await avatarSheet(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'https://img/new.png',
      );
      await tester.pump();
      await tester.tap(find.text('用這張'));
      await settle(tester, 3);
      await avatarSheet(tester);
      await tester.tap(find.text('不用圖片'));
      await settle(tester, 3);
      await avatarSheet(tester);
      await tester.tap(find.text('從頻道網址重新抓'));
      await settle(tester, 6);
      expect(find.text('已抓到頭像，記得按儲存'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, 4);
      // 關掉表單不選：什麼都不變。
      await avatarSheet(tester);
      await closeOverlays(tester);
      await tester.tap(find.text('完成'));
      await settle(tester, 4);
    });
    final a = (await tester.runAsync(
      () => YtTrackerRepository(store).loadChannels(),
    ))!.firstWhere((c) => c.id == 'a');
    expect(a.avatarImageUrl, isNotNull);
    await done(tester);
  });

  testWidgets('換頭像重新抓：API 壞掉說抓不到', (tester) async {
    final (_, yt) = await open(tester, fail: 403);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await avatarSheet(tester);
      await tester.tap(find.text('從頻道網址重新抓'));
      await settle(tester, 6);
    });
    expect(find.text('頭像抓不到'), findsOneWidget);
    await done(tester);
  });

  testWidgets('換頭像重新抓：沒金鑰、網址沒有 @ 帳號', (tester) async {
    final (_, yt) = await open(tester, apiKey: false);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await avatarSheet(tester);
      await tester.tap(find.text('從頻道網址重新抓'));
      await settle(tester, 3);
      expect(find.text('要先設定 API 金鑰才能抓頭像'), findsOneWidget);
    });
    await done(tester);
  });

  testWidgets('換頭像重新抓：網址沒有 @ 帳號', (tester) async {
    final (_, yt) = await open(tester);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('編輯頻道'));
      await settle(tester, 3);
      await tester.tap(inHeader('https://www.youtube.com/@a'));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byType(YtChannelEditHeader),
          matching: find.byType(TextField),
        ),
        'https://example.com/x',
      );
      await tester.pump();
      await avatarSheet(tester);
      await tester.tap(find.text('從頻道網址重新抓'));
      await settle(tester, 3);
      expect(find.text('頻道網址裡找不到 @帳號，先改網址'), findsOneWidget);
    });
    await done(tester);
  });

  Future<void> scrollToEnd(WidgetTester tester, FakeYoutube yt) async {
    for (var i = 0; i < 6; i++) {
      await run(tester, yt, () async {
        await tester.flingFrom(
          const Offset(195, 640),
          const Offset(0, -3000),
          4000,
        );
        await settle(tester, 4);
      });
    }
  }

  for (final fail in [0, 403]) {
    testWidgets('往下捲載入更早：全部、影片、Shorts、直播${fail == 0 ? '' : '（API 壞掉）'}', (
      tester,
    ) async {
      final (_, yt) = await open(tester, fail: fail);
      await scrollToEnd(tester, yt);
      for (final tab in ['影片', 'Shorts', '直播', '全部']) {
        await run(tester, yt, () async {
          await tester.flingFrom(
            const Offset(195, 400),
            const Offset(0, 3000),
            4000,
          );
          await settle(tester, 3);
          final t = find.text(tab);
          if (t.evaluate().isNotEmpty) {
            await tester.tap(t.first, warnIfMissed: false);
            await settle(tester, 6);
          }
        });
        await scrollToEnd(tester, yt);
        final retry = find.text('重試');
        if (retry.evaluate().isNotEmpty) {
          await run(tester, yt, () async {
            await tester.tap(retry.first, warnIfMissed: false);
            await settle(tester, 4);
          });
        }
      }
      expect(tester.takeException(), isNull);
      if (fail == 0) {
        expect(
          yt.calls.any((u) => u.queryParameters['pageToken'] == 'P2'),
          isTrue,
        );
      }
      await done(tester);
    });
  }

  testWidgets('回到頂端：捲下去才出現，點了回頂端；拖到左邊放開會吸邊並記住', (tester) async {
    final (_, yt) = await open(tester);
    await scrollToEnd(tester, yt);
    final top = find.byIcon(Icons.vertical_align_top_rounded);
    if (top.evaluate().isNotEmpty) {
      await tester.drag(top, const Offset(-300, -100));
      await settle(tester, 4);
      await tester.tap(top, warnIfMissed: false);
      await settle(tester, 4);
    }
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('搜尋：打字搜、注音不搜、Enter 記最近、清掉、收起', (tester) async {
    final (_, yt) = await open(tester);
    await run(tester, yt, () async {
      await tester.tap(find.byTooltip('搜尋這個頻道的影片'));
      await settle(tester, 3);
      final field = find.byType(TextField).last;
      await tester.enterText(field, 'ㄅ');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(field, '影片 1');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester, 4);
      expect(find.textContaining('找到'), findsWidgets);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 4);
      await tester.enterText(field, '沒有這種影片');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 4);
      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 3);
      // 最近搜尋點一下再搜一次。
      final recent = find.text('影片 1');
      if (recent.evaluate().isNotEmpty) {
        await tester.tap(recent.first, warnIfMissed: false);
        await settle(tester, 4);
      }
      // 收起搜尋。
      final close = find.byTooltip('收起搜尋');
      if (close.evaluate().isNotEmpty) {
        await tester.tap(close.first);
        await settle(tester, 3);
      } else {
        await tester.binding.handlePopRoute();
        await settle(tester, 3);
      }
    });
    expect(tester.takeException(), isNull);
    await done(tester);
  });
}
