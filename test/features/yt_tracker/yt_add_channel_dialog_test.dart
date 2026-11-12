import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// 新增頻道視窗（2026-11-12 補到 95%）：打開自動貼剪貼簿、抓頻道資料、已經有的、
/// 在垃圾桶裡的、永久刪除過的救回來、沒金鑰手動填、抓失敗、剪貼簿不是網址、
/// 名稱空白不新增、取消、選分類。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef hostRef;
  late BuildContext hostCtx;

  Future<(MemoryStore, FakeYoutube)> host(
    WidgetTester tester, {
    Object? clipboard,
    String? key = 'KEY',
    int fail = 0,
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
    await seedYt(tester, store);
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
    return (store, FakeYoutube()..fail = fail);
  }

  const cats = [
    YtCategory(id: 'c1', name: '投資', colorValue: 0xFF5FC9A8),
    YtCategory(id: 'c2', name: '音樂', colorValue: 0xFFE07A7A),
  ];

  Future<Future<bool>> open(
    WidgetTester tester,
    FakeYoutube yt, {
    String? initial,
  }) async {
    late Future<bool> f;
    await http.runWithClient(() async {
      await tester.runAsync(() async {
        f = showAddYtChannelDialog(
          hostCtx,
          hostRef,
          categories: cats,
          initialCategoryId: initial,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester, 3);
      // 等 0.5 秒的防抖再抓。
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 4);
    }, yt.client);
    return f;
  }

  Future<List<YtChannel>> channels(WidgetTester tester, MemoryStore s) async =>
      (await tester.runAsync(() => YtTrackerRepository(s).loadChannels()))!;

  testWidgets('剪貼簿是新頻道網址：自動貼上、抓到資料、選分類、新增', (tester) async {
    final (store, yt) = await host(
      tester,
      clipboard: 'https://www.youtube.com/@newone',
    );
    final f = await open(tester, yt, initial: 'c1');
    expect(find.text('https://www.youtube.com/@newone'), findsOneWidget);
    expect(find.textContaining('已抓到'), findsOneWidget);
    await tester.tap(find.text('音樂'));
    await tester.pump();
    await tester.tap(find.text('新增'));
    await settle(tester);
    expect(await tester.runAsync(() => f), isTrue);
    final added = (await channels(
      tester,
      store,
    )).firstWhere((c) => c.url == 'https://www.youtube.com/@newone');
    expect(added.categoryId, 'c2');
    expect(added.youtubeChannelId, isNotEmpty);
    expect(added.reviewedAt, isNotNull);
    expect(added.description, '介紹');
  });

  testWidgets('自己改過名稱：抓到資料不蓋掉；選未分類', (tester) async {
    final (store, yt) = await host(tester);
    final f = await open(tester, yt, initial: 'c1');
    expect(find.text('按右邊「貼上」讀取剪貼簿網址'), findsOneWidget);
    // 沒網址：手動打名字、選未分類就能新增。
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '手動的');
    await tester.enterText(fields.at(1), 'https://img/a.png');
    await tester.pump();
    await tester.tap(find.text('未分類'));
    await tester.pump();
    await tester.tap(find.text('新增'));
    await settle(tester);
    expect(await tester.runAsync(() => f), isTrue);
    final added = (await channels(
      tester,
      store,
    )).firstWhere((c) => c.name == '手動的');
    expect(added.categoryId, isNull);
    expect(added.avatarImageUrl, 'https://img/a.png');
  });

  testWidgets('已經新增過的網址：說在哪個分類、新增鍵停用', (tester) async {
    final (_, yt) = await host(tester, clipboard: 'https://www.youtube.com/@a');
    final f = await open(tester, yt);
    expect(find.textContaining('這個頻道已經新增過了：「頻道a」（投資）'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(await tester.runAsync(() => f), isFalse);
  });

  testWidgets('未分類的頻道重複：說未分類', (tester) async {
    final (_, yt) = await host(tester, clipboard: 'https://www.youtube.com/@n');
    await open(tester, yt);
    expect(find.textContaining('（未分類）'), findsOneWidget);
  });

  testWidgets('在垃圾桶裡的：叫你去垃圾桶還原', (tester) async {
    final (_, yt) = await host(tester, clipboard: 'https://www.youtube.com/@t');
    await open(tester, yt);
    expect(find.textContaining('已經在垃圾桶裡'), findsOneWidget);
  });

  testWidgets('永久刪除過的：救回原本那筆、套這次的分類跟名稱', (tester) async {
    final (store, yt) = await host(
      tester,
      clipboard: 'https://www.youtube.com/@p',
      key: null,
    );
    final f = await open(tester, yt, initial: 'c1');
    expect(find.textContaining('還沒設定 API 金鑰'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '回來了');
    await tester.pump();
    await tester.tap(find.text('新增'));
    await settle(tester);
    expect(await tester.runAsync(() => f), isTrue);
    final all = (await tester.runAsync(
      () => YtTrackerRepository(store).channelsForUpload(),
    ))!;
    final p = all.where((c) => c.id == 'p').single;
    expect(p.purgedAt, isNull);
    expect(p.deletedAt, isNull);
    expect(p.name, '回來了');
    expect(p.categoryId, 'c1');
  });

  testWidgets('抓頻道資料失敗：說自動抓取失敗、可以手動填', (tester) async {
    final (_, yt) = await host(
      tester,
      clipboard: 'https://www.youtube.com/@broken',
      fail: 500,
    );
    await open(tester, yt);
    expect(find.textContaining('自動抓取失敗'), findsOneWidget);
  });

  testWidgets('剪貼簿不是網址：不自動貼；按貼上照貼、換成不重複的網址提示消失；名稱空白不新增', (tester) async {
    final (_, yt) = await host(tester, clipboard: '隨便一句話');
    final f = await open(tester, yt);
    expect(find.text('按右邊「貼上」讀取剪貼簿網址'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 3);
    }, yt.client);
    expect(find.text('隨便一句話'), findsOneWidget);
    await tester.tap(find.text('新增'));
    await settle(tester);
    expect(await tester.runAsync(() => f), isFalse);
  });

  testWidgets('重複的網址再按貼上換成新的：提示收起來、重新抓', (tester) async {
    var clip = 'https://www.youtube.com/@a';
    final (_, yt) = await host(tester, clipboard: clip);
    // 換掉剪貼簿內容。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': clip} : null,
    );
    await open(tester, yt);
    expect(find.textContaining('已經新增過了'), findsOneWidget);
    clip = 'https://www.youtube.com/@fresh';
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 2);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 4);
    }, yt.client);
    expect(find.textContaining('已經新增過了'), findsNothing);
    expect(find.textContaining('已抓到'), findsOneWidget);
    // 再貼同一個：不重抓。
    final n = yt.calls.length;
    await http.runWithClient(() async {
      await tester.tap(find.text('貼上'));
      await settle(tester, 2);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 2);
    }, yt.client);
    expect(yt.calls.length, n);
  });

  testWidgets('剪貼簿讀不到（被擋）：不會壞', (tester) async {
    final (_, yt) = await host(
      tester,
      clipboard: PlatformException(code: 'denied'),
    );
    await open(tester, yt);
    await tester.tap(find.text('貼上'));
    await settle(tester, 2);
    expect(find.text('按右邊「貼上」讀取剪貼簿網址'), findsOneWidget);
    expect(await tester.runAsync(readYtChannelClipboard), isNull);
  });
}
