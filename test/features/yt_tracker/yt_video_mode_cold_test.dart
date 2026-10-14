import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_display_prefs_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

/// 2026-10-12 使用者要求：依影片顯示預設不抓冷藏頻道，設定裡可以打開。
void main() {
  test('設定預設：不抓冷藏、捲動條跟回到最上面都開；存了會記住', () async {
    final store = _MemoryStore();
    final d = await YtDisplayPrefsStore(store).load();
    expect(d.videoIncludeCold, isFalse);
    expect(d.videoIncludePending, isFalse);
    expect(d.showScrollbar, isTrue);
    expect(d.showBackToTop, isTrue);
    expect(await YtDisplayPrefsStore(store).loadRecord(), isNull);
    await YtDisplayPrefsStore(store).save(d.copyWith(videoIncludeCold: true));
    expect((await YtDisplayPrefsStore(store).load()).videoIncludeCold, isTrue);
  });

  test('早上只存本機的「抓冷藏」舊開關會帶進來', () async {
    final store = _MemoryStore()
      ..data['yt_tracker.video_include_cold.v1'] = 'true';
    expect((await YtDisplayPrefsStore(store).load()).videoIncludeCold, isTrue);
  });

  testWidgets('分類裡只有冷藏頻道：依影片顯示提示去設定打開，打開後就會去抓', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      await repo.addCategory(
        const YtCategory(id: 'games', name: '遊戲', colorValue: 0),
      );
      await repo.addChannel(
        YtChannel(
          id: 'a',
          name: '頻道A',
          categoryId: 'games',
          addedAt: DateTime(2026, 9, 1),
          coldAt: DateTime(2026, 10, 1),
        ),
      );
      // 待評鑑：沒置頂、沒冷藏、沒評鑑過。
      await repo.addChannel(
        YtChannel(
          id: 'b',
          name: '頻道B',
          categoryId: 'games',
          addedAt: DateTime(2026, 9, 1),
        ),
      );
    });
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        ytApiKeyProvider.overrideWith((ref) => 'test-key'),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: YtTrackerBrowsePage(initialCategoryIds: {'games'}),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('依影片顯示'));
    await _settle(tester);
    expect(find.text('這裡都是冷藏或待評鑑的頻道'), findsOneWidget);

    container.read(ytDisplayPrefsProvider.notifier).state = YtDisplayPrefs
        .defaults
        .copyWith(videoIncludeCold: true);
    await _settle(tester);
    // 冷藏打開了，但待評鑑的還沒——頻道A 會抓，畫面不再是空的。
    expect(find.text('這裡都是冷藏或待評鑑的頻道'), findsNothing);

    container.read(ytDisplayPrefsProvider.notifier).state = YtDisplayPrefs
        .defaults
        .copyWith(videoIncludePending: true);
    await _settle(tester);
    // 只開待評鑑：頻道B 會抓。
    expect(find.text('這裡都是冷藏或待評鑑的頻道'), findsNothing);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
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
