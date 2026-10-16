import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

/// 音樂分類排序列右邊「🎤 歌手」：只列標成歌手的頻道（2026-10-16）。
Future<void> _pump(WidgetTester tester, String catName) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = _MemoryStore();
  await tester.runAsync(() async {
    final repo = YtTrackerRepository(store);
    await repo.addCategory(YtCategory(id: 'c', name: catName, colorValue: 0));
    final at = DateTime(2026, 9, 1);
    await repo.addChannel(
      YtChannel(
        id: 'a',
        name: '歌手甲',
        categoryId: 'c',
        addedAt: at,
        reviewedAt: at,
        artistAt: at,
      ),
    );
    await repo.addChannel(
      YtChannel(
        id: 'b',
        name: '翻唱乙',
        categoryId: 'c',
        addedAt: at,
        reviewedAt: at,
      ),
    );
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(
        home: YtTrackerBrowsePage(initialCategoryIds: {'c'}),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('音樂分類：按「🎤 歌手」只剩歌手頻道，再按回來', (tester) async {
    await _pump(tester, '音樂');
    expect(find.text('翻唱乙'), findsOneWidget);
    await tester.tap(find.text('🎤 歌手 1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('歌手甲'), findsOneWidget);
    expect(find.text('翻唱乙'), findsNothing);
    await tester.tap(find.text('🎤 歌手 1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('翻唱乙'), findsOneWidget);
  });

  testWidgets('不是音樂分類：沒有這顆', (tester) async {
    await _pump(tester, '遊戲');
    expect(find.textContaining('🎤 歌手'), findsNothing);
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
