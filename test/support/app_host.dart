import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/app.dart';
import 'package:lume/app/app_bottom_nav.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/app/router.dart';
import 'package:lume/data/seed/app_defaults_loader.dart';
import 'package:lume/shared/nav_bar_hiders.dart';
import 'package:lume/shared/widgets/sakura_petals.dart';

import 'poke.dart';
import 'yt_fake.dart';

/// 把整個 App（[LumeApp]，真的路由、底部分頁列、音樂播放器那層）開起來。
/// 塞好一份 YT 資料；回傳本機儲存跟 ProviderContainer（改設定用）。
Future<(MemoryStore, ProviderContainer)> openWholeApp(
  WidgetTester tester, {
  Size size = const Size(390, 860),
  List<Override> overrides = const [],
}) async {
  sakuraPetalsEnabled = false;
  // 全域的：上一個測試留下來的對話框計數跟藏分頁列的計數歸零。
  navBarRouteObserver.popups.value = 0;
  navBarHiders.value = 0;
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final store = MemoryStore();
  await seedYt(tester, store);
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      libraryTagOrderProvider.overrideWithValue(LibraryTagOrder.empty),
      r2BucketNameProvider.overrideWithValue('b'),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const LumeApp()),
  );
  await settle(tester, 6);
  return (store, container);
}

/// 換到 [path]（整個 App 的路由），畫面跑一下。
Future<void> goPath(WidgetTester tester, String path, {Object? extra}) async {
  appRouter.go(path, extra: extra);
  await settle(tester, 5);
}
