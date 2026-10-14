import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/settings/other_settings_page.dart';

/// 2026-10-14 使用者回報：播放清單頁的齒輪跑到首頁的設定；YT 設定裡也
/// 找不到「影片」要開哪個頻道。
void main() {
  testWidgets('從播放清單開設定：是 YT 的設定，最上面就有底部分頁列', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: const MaterialApp(
          home: OtherSettingsPage(fromLocation: '/yt-playlists'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('YT 頻道追蹤'), findsOneWidget);
    expect(find.text('底部分頁列'), findsOneWidget);
    expect(find.text('底部分頁列「影片」開的頻道'), findsOneWidget);
    expect(find.text('首頁樣式'), findsNothing);
    expect(tester.takeException(), isNull);
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
