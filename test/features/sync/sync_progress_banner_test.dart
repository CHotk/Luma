import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/sync/sync_progress_banner.dart';

/// 2026-10-12 使用者要求：同步中跳去別的頁面，上方顯示即時進度。
void main() {
  testWidgets('同步中顯示幾／幾跟還在跑的項目，沒在同步就收起來', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SyncProgressBanner())),
      ),
    );
    expect(find.textContaining('同步中'), findsNothing);

    container.read(syncProgressProvider.notifier).state = const SyncProgress(
      total: 12,
      done: 5,
      running: ['YT 頻道追蹤', '交易紀錄'],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('同步中 5／12'), findsOneWidget);
    expect(find.text('YT 頻道追蹤、交易紀錄…'), findsOneWidget);

    container.read(syncProgressProvider.notifier).state = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('同步中'), findsNothing);
  });
}
