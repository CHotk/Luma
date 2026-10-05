import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/app_home/app_home_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全新裝置（什麼都沒存）：儀表板每一格都算得出來，不會整個壞掉', () async {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
    );
    addTearDown(container.dispose);
    final sub = container.listen(appHomeDashboardProvider, (_, _) {});
    addTearDown(sub.close);

    final d = await container.read(appHomeDashboardProvider.future);

    expect(d.enRoundsDone, 0);
    expect(d.enRoundsPerDay, greaterThan(0));
    expect(d.jpTodayCount, 0);
    expect(d.diaryToday, 0);
    expect(d.fitnessLast, isNull);
    expect(d.ytNewVideos, 0);
    expect(d.lastSyncedAt, isNull);
    expect(d.syncConfigured, isFalse);
  });

  testWidgets('手機寬度（360）畫得出來、不會爆版', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: AppHomeDashboard(),
            ),
          ),
        ),
      ),
    );
    // 資料要讀打包的設定檔（真的非同步），在假時鐘下等不到，讓它用真時間
    // 跑完再畫一次。轉圈動畫會讓 pumpAndSettle 永遠等不完，所以不用它。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(find.text('今天還沒寫'), findsOneWidget);
    expect(find.text('還沒打過卡'), findsOneWidget);
    expect(find.text('還沒設定雲端同步'), findsOneWidget);
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
