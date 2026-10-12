import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/app/theme/colors.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

/// 2026-10-12 使用者要求：從分類點頻道進去，返回分類時剛剛點的那張卡片
/// 要有藍色外框。
void main() {
  testWidgets('點進頻道再返回，剛剛點的那張卡片有藍框', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      await repo.addCategory(
        const YtCategory(id: 'games', name: '遊戲', colorValue: 0),
      );
      for (final (id, name) in [('a', '頻道A'), ('b', '頻道B')]) {
        await repo.addChannel(
          YtChannel(
            id: id,
            name: name,
            categoryId: 'games',
            addedAt: DateTime(2026, 9, 1),
            reviewedAt: DateTime(2026, 9, 2),
          ),
        );
      }
    });
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const YtTrackerBrowsePage(initialCategoryIds: {'games'}),
        ),
        GoRoute(
          path: '/yt-tracker/channel/:id',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.pop(),
              child: const Text('返回'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: router),
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

    bool outlined(String name) => tester
        .widgetList<Container>(
          find.ancestor(of: find.text(name), matching: find.byType(Container)),
        )
        .any((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.border is Border &&
              (d.border! as Border).top.color == AppColors.accent;
        });

    await settle();
    expect(outlined('頻道A'), isFalse);
    expect(outlined('頻道B'), isFalse);

    await tester.tap(find.text('頻道B'));
    await settle();
    await tester.tap(find.text('返回'));
    await settle();

    expect(outlined('頻道B'), isTrue);
    expect(outlined('頻道A'), isFalse);
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
