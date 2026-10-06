import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

Future<_MemoryStore> _pump(WidgetTester tester) async {
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
      ),
    );
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(
        home: YtTrackerBrowsePage(initialCategoryIds: {'games'}),
      ),
    ),
  );
  await _settle(tester);
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('長按選單按一次「置頂」就生效', (tester) async {
    _bigView(tester);
    final store = await _pump(tester);
    expect(find.textContaining('待評鑑 ·'), findsOneWidget);

    await tester.longPress(find.text('頻道A'));
    await _settle(tester);
    await tester.tap(find.text('置頂'));
    await _settle(tester);

    expect(find.textContaining('已置頂 ·'), findsOneWidget);
    final saved = await tester.runAsync(
      () => YtTrackerRepository(store).loadChannels(),
    );
    expect(saved!.single.pinnedAt, isNotNull);
  });

  testWidgets('長按不放滑到「一般」放開，一次就從待評鑑搬到一般', (tester) async {
    _bigView(tester);
    await _pump(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('頻道A')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    final target = tester.getCenter(find.text('一般'));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    expect(find.textContaining('一般 ·'), findsOneWidget);
    expect(find.textContaining('待評鑑 ·'), findsNothing);
  });
}

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
