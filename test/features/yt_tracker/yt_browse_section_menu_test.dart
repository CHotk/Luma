import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

Future<_MemoryStore> _pump(
  WidgetTester tester, {
  List<YtChannel> channels = const [],
}) async {
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
    for (final c in channels) {
      await repo.addChannel(c);
    }
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

  // 2026-10-06 使用者要求：置頂區也照當下的排序方式排，不是最後置頂的
  // 排最前面。預設排序是加入順序，所以先加、先置頂的 B 要在 C 前面。
  testWidgets('置頂區照目前的排序方式排，不是照置頂時間新到舊', (tester) async {
    _bigView(tester);
    await _pump(
      tester,
      channels: [
        YtChannel(
          id: 'b',
          name: '頻道B',
          categoryId: 'games',
          addedAt: DateTime(2026, 9, 2),
          pinnedAt: DateTime(2026, 10, 1),
          reviewedAt: DateTime(2026, 10, 1),
        ),
        YtChannel(
          id: 'c',
          name: '頻道C',
          categoryId: 'games',
          addedAt: DateTime(2026, 9, 3),
          pinnedAt: DateTime(2026, 10, 5),
          reviewedAt: DateTime(2026, 10, 5),
        ),
      ],
    );
    final b = tester.getTopLeft(find.text('頻道B'));
    final c = tester.getTopLeft(find.text('頻道C'));
    expect(b.dy < c.dy || (b.dy == c.dy && b.dx < c.dx), isTrue);
  });

  // 2026-10-06 使用者要求：區塊標題捲動時黏在頂端，不跟著捲走。
  testWidgets('往下捲很遠，「待評鑑」標題還黏在上面看得到', (tester) async {
    _bigView(tester);
    await _pump(
      tester,
      channels: [
        for (var i = 0; i < 40; i++)
          YtChannel(
            id: 'p$i',
            name: '待評鑑頻道$i',
            categoryId: 'games',
            addedAt: DateTime(2026, 9, 2),
          ),
      ],
    );
    final header = find.textContaining('待評鑑 ·');
    final before = tester.getTopLeft(header).dy;
    await tester.drag(find.text('待評鑑頻道10'), const Offset(0, -600));
    await _settle(tester);
    expect(header, findsOneWidget);
    expect(tester.getTopLeft(header).dy, closeTo(before, 40));
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
