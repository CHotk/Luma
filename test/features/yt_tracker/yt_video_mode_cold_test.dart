import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_include_cold_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

/// 2026-10-12 使用者要求：依影片顯示預設不抓冷藏頻道，設定裡可以打開。
void main() {
  test('設定預設不抓冷藏，存了會記住', () async {
    final store = _MemoryStore();
    expect(await YtVideoIncludeColdStore(store).load(), isFalse);
    await YtVideoIncludeColdStore(store).save(true);
    expect(await YtVideoIncludeColdStore(store).load(), isTrue);
  });

  testWidgets('分類裡只有冷藏頻道：依影片顯示提示去設定打開，打開後就會去抓', (
    tester,
  ) async {
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
    expect(find.text('這裡都是冷藏頻道'), findsOneWidget);

    container.read(ytVideoIncludeColdProvider.notifier).state = true;
    await _settle(tester);
    expect(find.text('這裡都是冷藏頻道'), findsNothing);
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
