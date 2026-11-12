import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_playlist_actions.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// 播放清單的動作與表單（2026-11-12 補到 95%）：加、拿掉、插回、移到最前、新建、改名、
/// 刪除（稍後觀看不能刪）、存到稍後觀看（重複會說）、「存到…」表單、取名對話框、
/// 選「影片」分頁要開哪個頻道（分類、搜尋、找不到）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  YtPlaylistItem item(String id) => YtPlaylistItem(
    video: YoutubeVideo(
      videoId: id,
      title: '影片 $id',
      publishedAt: DateTime(2026, 10, 1),
      thumbnailUrl: '',
    ),
    channelName: '頻道',
    addedAt: DateTime(2026, 10, 1),
  );

  late WidgetRef hostRef;
  late BuildContext hostContext;

  Future<MemoryStore> host(WidgetTester tester, {bool seed = false}) async {
    final store = MemoryStore();
    if (seed) await seedYt(tester, store);
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostRef = ref;
                hostContext = context;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
    return store;
  }

  List<YtPlaylist> all() => hostRef.read(ytPlaylistsProvider);

  testWidgets('動作：加（重複不加）、拿掉、插回、移到最前、新建、改名、刪除', (tester) async {
    final store = await host(tester);
    final a = YtPlaylistActions(hostRef);
    await tester.runAsync(() async {
      expect(await a.add(YtPlaylist.laterId, item('x')), isTrue);
      expect(await a.add(YtPlaylist.laterId, item('x')), isFalse);
      expect(await a.add('不存在', item('x')), isFalse);
      await a.add(YtPlaylist.laterId, item('y'));
      await a.add(YtPlaylist.laterId, item('z'));
      // 最新加的在最前面。
      expect(a.byId(YtPlaylist.laterId)!.items.map((i) => i.videoId), [
        'z',
        'y',
        'x',
      ]);
      expect(await a.remove(YtPlaylist.laterId, 'y'), 1);
      expect(await a.remove(YtPlaylist.laterId, 'y'), -1);
      expect(await a.remove('不存在', 'y'), -1);
      // 插回原位；位置超出範圍會夾住；已經在了不重複。
      await a.insertAt(YtPlaylist.laterId, item('y'), 1);
      await a.insertAt(YtPlaylist.laterId, item('w'), 99);
      await a.insertAt(YtPlaylist.laterId, item('v'), -5);
      await a.insertAt(YtPlaylist.laterId, item('x'), 0);
      expect(a.byId(YtPlaylist.laterId)!.items.map((i) => i.videoId), [
        'v',
        'z',
        'y',
        'x',
        'w',
      ]);
      await a.moveToTop(YtPlaylist.laterId, 'w');
      await a.moveToTop(YtPlaylist.laterId, '沒有');
      expect(a.byId(YtPlaylist.laterId)!.items.first.videoId, 'w');

      final id = await a.create('  新清單  ', first: item('q'));
      expect(a.byId(id)!.name, '新清單');
      expect(a.byId(id)!.items.single.videoId, 'q');
      // 同一微秒建兩份會拿到一樣的 id，隔一下。
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final empty = await a.create('空的');
      expect(a.byId(empty)!.items, isEmpty);
      await a.rename(id, ' 改名 ');
      expect(a.byId(id)!.name, '改名');
      await a.delete(id);
      expect(a.byId(id), isNull);
      expect(all().firstWhere((p) => p.id == id).deletedAt, isNotNull);
      // 稍後觀看不能刪。
      await a.delete(YtPlaylist.laterId);
      expect(a.byId(YtPlaylist.laterId), isNotNull);
    });
    // 有寫回本機。
    final saved = await tester.runAsync(() => YtPlaylistStore(store).loadAll());
    expect(saved!.any((p) => p.name == '空的'), isTrue);
  });

  testWidgets('存到稍後觀看：第一次存、可以復原；再存說已經在了', (tester) async {
    await host(tester);
    final it = item('x');
    await tester.runAsync(() => saveToWatchLater(hostContext, hostRef, it));
    await tester.pump();
    expect(find.text('已存到「稍後觀看」'), findsOneWidget);
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, '復原'))
        .onPressed!();
    await settle(tester);
    expect(YtPlaylistActions(hostRef).byId(YtPlaylist.laterId)!.items, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => saveToWatchLater(hostContext, hostRef, it));
    await tester.runAsync(() => saveToWatchLater(hostContext, hostRef, it));
    await tester.pump();
    expect(find.text('已經在「稍後觀看」了'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('「存到…」表單：勾、取消勾、新建（空名字不建、按 Enter 也能建）、完成', (tester) async {
    await host(tester);
    final it = item('x');
    showSaveToPlaylistSheet(hostContext, hostRef, it);
    await settle(tester);
    expect(find.text('添加到播放清單'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await settle(tester);
    expect(
      YtPlaylistActions(hostRef).byId(YtPlaylist.laterId)!.contains('x'),
      isTrue,
    );
    await tester.tap(find.byType(CheckboxListTile).first);
    await settle(tester);
    expect(
      YtPlaylistActions(hostRef).byId(YtPlaylist.laterId)!.contains('x'),
      isFalse,
    );
    await tester.tap(find.text('新增播放清單'));
    await settle(tester);
    // 空名字按建立不會建。
    await tester.tap(find.text('建立'));
    await settle(tester);
    expect(YtPlaylistStore.visible(all()), hasLength(1));
    await tester.enterText(find.byType(TextField), '追劇');
    await tester.tap(find.text('建立'));
    await settle(tester);
    expect(find.text('追劇'), findsOneWidget);
    expect(find.text('新增播放清單'), findsOneWidget);
    await tester.tap(find.text('新增播放清單'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '第二份');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    final names = YtPlaylistStore.visible(all()).map((p) => p.name);
    expect(names, containsAll(['追劇', '第二份']));
    // 新建的會順便存進去。
    expect(
      YtPlaylistStore.visible(
        all(),
      ).where((p) => p.name == '追劇').single.contains('x'),
      isTrue,
    );
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(find.text('添加到播放清單'), findsNothing);
  });

  testWidgets('取名對話框：好、取消、空白當沒填、Enter 送出、改名帶原本的名字', (tester) async {
    await host(tester);
    Future<String?> ask(Future<void> Function() act, {String init = ''}) async {
      final f = askPlaylistName(hostContext, initial: init, title: '取名');
      await settle(tester);
      await act();
      await settle(tester);
      return f;
    }

    expect(
      await ask(() async {
        await tester.enterText(find.byType(TextField), ' 好名字 ');
        await tester.tap(find.text('好'));
      }),
      '好名字',
    );
    expect(await ask(() => tester.tap(find.text('取消'))), isNull);
    expect(
      await ask(() async {
        await tester.enterText(find.byType(TextField), '   ');
        await tester.tap(find.text('好'));
      }),
      isNull,
    );
    expect(
      await ask(() async {
        await tester.enterText(find.byType(TextField), '按Enter');
        await tester.testTextInput.receiveAction(TextInputAction.done);
      }),
      '按Enter',
    );
    expect(
      await ask(() async {
        expect(find.text('舊名'), findsOneWidget);
        await tester.tap(find.text('好'));
      }, init: '舊名'),
      '舊名',
    );
  });

  testWidgets('選「影片」分頁的頻道：分類切換、置頂與一般、搜尋、找不到、清掉搜尋、選了會存', (tester) async {
    await host(tester, seed: true);
    late Future<String?> f;
    await tester.runAsync(() async {
      f = pickVideoTabChannel(hostContext, hostRef);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(find.text('「影片」分頁要開哪個頻道'), findsOneWidget);
    // 投資分類：a 置頂、b 冷藏與 r 待評鑑不列。
    expect(find.textContaining('置頂 · 1'), findsOneWidget);
    expect(find.text('頻道b'), findsNothing);
    expect(find.text('頻道r'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '音樂'));
    await settle(tester);
    expect(find.text('頻道m'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '未分類'));
    await settle(tester);
    expect(find.text('頻道n'), findsOneWidget);
    // 搜尋不管分類，冷藏的也找得到。
    await tester.enterText(find.byType(TextField), '頻道B');
    await settle(tester);
    expect(find.text('頻道b'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '沒這個');
    await settle(tester);
    expect(find.text('找不到「沒這個」'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await settle(tester);
    expect(find.byType(ChoiceChip), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, '投資'));
    await settle(tester);
    await tester.tap(find.text('頻道a'));
    await settle(tester);
    final picked = await tester.runAsync(() => f);
    expect(picked, 'a');
    expect(hostRef.read(ytDisplayPrefsProvider).videoTabChannelId, 'a');

    // 再開一次：停在目前選的頻道那個分類、有打勾；關掉不選回 null。
    await tester.runAsync(() async {
      f = pickVideoTabChannel(hostContext, hostRef);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    Navigator.of(hostContext).pop();
    await settle(tester);
    expect(await tester.runAsync(() => f), isNull);
  });

  testWidgets('選頻道：一個可選的都沒有就沒有分類可切', (tester) async {
    await host(tester);
    late Future<String?> f;
    await tester.runAsync(() async {
      f = pickVideoTabChannel(hostContext, hostRef);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('這個分類沒有置頂或一般的頻道'), findsOneWidget);
    Navigator.of(hostContext).pop();
    await settle(tester);
    expect(await tester.runAsync(() => f), isNull);
  });
}
