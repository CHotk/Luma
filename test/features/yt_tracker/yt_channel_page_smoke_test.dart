import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
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
