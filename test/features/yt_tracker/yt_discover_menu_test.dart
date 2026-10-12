import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

/// 2026-10-12 使用者要求：「挖掘新頻道」裡的頻道只是在等被分類或刪除，
/// 選單不需要置頂／一般／冷藏；其他分類照舊有。
void main() {
  Future<void> open(WidgetTester tester, String? categoryId) async {
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
          categoryId: categoryId,
          addedAt: DateTime(2026, 9, 1),
          reviewedAt: DateTime(2026, 9, 2),
        ),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: YtTrackerBrowsePage(
            initialCategoryIds: {categoryId ?? ytUncategorizedId},
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.longPress(find.text('頻道A'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('挖掘新頻道：選單沒有置頂／一般／冷藏，移動、編輯、刪除還在', (tester) async {
    await open(tester, ytDiscoverCategoryId);
    expect(find.text('置頂'), findsNothing);
    expect(find.text('移動'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);
  });

  testWidgets('一般分類：照舊有置頂', (tester) async {
    await open(tester, 'games');
    expect(find.text('置頂'), findsOneWidget);
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
