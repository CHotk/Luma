import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_tracker_home_page.dart';

/// 2026-10-14 使用者要求：新增頻道、挖掘新頻道、新增分類收進同一顆 ＋，
/// 點了先問要做哪個。
void main() {
  testWidgets('YT 首頁：＋ 先問新增頻道／挖掘／新增分類', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: const MaterialApp(home: YtTrackerHomePage()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 上面只剩一顆 ＋，挖掘跟新增分類不再各自一顆。
    expect(find.byTooltip('新增'), findsOneWidget);
    expect(find.byTooltip('挖掘新頻道'), findsNothing);
    expect(find.byTooltip('新增分類'), findsNothing);

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    expect(find.text('新增頻道'), findsOneWidget);
    expect(find.text('挖掘新頻道'), findsOneWidget);
    expect(find.text('新增分類'), findsWidgets);

    await tester.tap(find.text('自己開一個分類資料夾'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
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
