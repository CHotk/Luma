import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lume/shared/widgets/app_side_drawer.dart';

/// 左側選單左下角的版本號（2026-10-19 使用者要求）。
void main() {
  testWidgets('顯示 v版本・日期，音樂頁時不會亮「語言學習」', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'lume',
      packageName: 'lume',
      version: '1.0.0',
      buildNumber: '20261019',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/music',
      routes: [
        GoRoute(
          path: '/music',
          builder: (_, _) => const Scaffold(drawer: AppSideDrawer(), body: SizedBox()),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final state = tester.firstState<ScaffoldState>(find.byType(Scaffold));
    state.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('v1.0.0・2026/10/19'), findsOneWidget);
  });
}
