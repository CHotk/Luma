import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_channel_page.dart';

// 2026-10-06：頻道頁整頁改成 CustomScrollView、影片清單捲到才建。這支
// 確認頁面能正常畫出來（簡介、篩選列、沒金鑰的提示），沒有 sliver
// 跟一般元件混用的版面錯誤。
void main() {
  testWidgets('頻道頁沒設定金鑰也能正常畫出來', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    await tester.runAsync(() async {
      await YtTrackerRepository(store).addChannel(
        YtChannel(
          id: 'a',
          name: '頻道A',
          categoryId: null,
          addedAt: DateTime(2026, 9, 1),
        ),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: YtTrackerChannelPage(channelId: 'a')),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('還沒有設定 API 金鑰'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    // 右側捲動條、回到最上面預設都開（2026-10-12）：捲動條在。
    expect(find.byType(Scrollbar), findsWidgets);
  });

  testWidgets('編輯頻道：改過名的，名稱右邊顯示原本的名字，點了改回來', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      final c = YtChannel(
        id: 'a',
        name: '頻道A',
        categoryId: null,
        addedAt: DateTime(2026, 9, 1),
      );
      await repo.addChannel(c);
      await repo.updateChannel(c.copyWith(name: '我取的名字'));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: YtTrackerChannelPage(channelId: 'a')),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    // 2026-10-12 編輯改成頻道頁直接點著改：按 ✏️ 進編輯，點名稱變輸入框。
    await tester.tap(find.byTooltip('編輯頻道'));
    await settle();
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('我取的名字').last);
    await settle();
    expect(find.text('（原本：頻道A）'), findsOneWidget);

    await tester.tap(find.text('（原本：頻道A）'));
    await settle();
    expect(find.widgetWithText(TextField, '頻道A'), findsOneWidget);
    // 改回原本的名字就不用再提示。
    expect(find.text('（原本：頻道A）'), findsNothing);

    // 改了一項，底部出儲存列；存了以後離開編輯、名稱真的改回去。
    expect(find.text('已改 1 項'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await settle();
    expect(find.text('完成'), findsNothing);
    final saved = await tester.runAsync(
      () => YtTrackerRepository(store).loadChannels(),
    );
    expect(saved!.single.name, '頻道A');
  });

  testWidgets('頻道頁搜尋（設計稿第 1 版）：點放大鏡鍵盤就跳出、打字就出結果，返回收起', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    await tester.runAsync(() async {
      await YtTrackerRepository(store).addChannel(
        YtChannel(
          id: 'a',
          name: '頻道A',
          categoryId: null,
          addedAt: DateTime(2026, 9, 1),
        ),
      );
      await YtVideoCacheStore(store).upsertVideos('a', [
        for (final (day, title) in [(1, '黑洞的祕密'), (2, '宇宙盡頭'), (3, '又是黑洞')])
          YoutubeVideo(
            videoId: 'v$day',
            title: title,
            publishedAt: DateTime(2026, 9, day),
            thumbnailUrl: '',
          ),
      ]);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: YtTrackerChannelPage(channelId: 'a')),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('搜尋這個頻道的影片'));
    await settle();
    // 點了鍵盤就跳出來（搜尋框拿到焦點）。
    expect(tester.testTextInput.isVisible, isTrue);
    // 注音還沒選字（組字中、有底線）不搜。
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ㄏㄟ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await settle();
    expect(find.textContaining('搜抓過的'), findsNothing);
    // 打字就搜，不用按 Enter。
    await tester.enterText(find.byType(TextField), '黑洞');
    await settle();
    expect(tester.takeException(), isNull);
    // 沒金鑰：只搜快取。
    expect(find.textContaining('搜抓過的 3 部'), findsOneWidget);
    expect(find.textContaining('黑洞的祕密', findRichText: true), findsOneWidget);
    expect(find.textContaining('又是黑洞', findRichText: true), findsOneWidget);
    expect(find.textContaining('宇宙盡頭', findRichText: true), findsNothing);

    await tester.tap(find.byTooltip('收起搜尋'));
    await settle();
    expect(find.byTooltip('收起搜尋').hitTestable(), findsNothing);
    expect(find.text('全部'), findsOneWidget);
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}
