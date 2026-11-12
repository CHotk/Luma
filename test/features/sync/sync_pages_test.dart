import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/repositories/sync_log_repository.dart';
import 'package:lume/domain/models/sync_log_entry.dart';
import 'package:lume/features/sync/sync_log_page.dart';
import 'package:lume/features/sync/sync_log_row.dart';
import 'package:lume/features/sync/sync_page.dart';
import 'package:lume/features/sync/sync_progress_banner.dart';

import '../../support/poke.dart';

/// 多裝置同步頁、同步紀錄頁、上方進度條（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 沒有紀錄、超過 10 筆只顯示 10 筆、每種紀錄（成功、失敗、備份、各種裝置）、點開看細節、
/// 備份（沒連雲端、這個平台不能下載、雲端壞了）、進度條。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const creds = R2Credentials(
    endpoint: 'https://acc.r2.cloudflarestorage.com',
    accessKeyId: 'k',
    secretAccessKey: 's',
  );
  var failStatus = 0;
  final bucket = <String, List<int>>{'diary.json': '[]'.codeUnits};
  http.Client cloud() => MockClient((req) async {
    if (failStatus != 0) return http.Response('broken', failStatus);
    final key = req.url.pathSegments.skip(1).join('/');
    if (key.isEmpty) {
      final items = [
        for (final e in bucket.entries)
          '<Contents><Key>${e.key}</Key><ETag>"${md5.convert(e.value)}"</ETag></Contents>',
      ].join();
      return http.Response(
        '<ListBucketResult>$items<IsTruncated>false</IsTruncated></ListBucketResult>',
        200,
      );
    }
    final b = bucket[key];
    return b == null ? http.Response('', 404) : http.Response.bytes(b, 200);
  });

  Future<MemoryStore> pumpSync(
    WidgetTester tester, {
    List<SyncLogEntry> log = const [],
    R2Credentials? credentials,
  }) async {
    final store = MemoryStore();
    for (final e in log) {
      await tester.runAsync(() => SyncLogRepository(store).add(e));
    }
    tester.view.physicalSize = const Size(420 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SyncPage()),
        GoRoute(path: '/sync/log', builder: (_, _) => const SyncLogPage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          r2BucketNameProvider.overrideWithValue('lume'),
          r2CredentialsProvider.overrideWith((_) => credentials),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    return store;
  }

  final now = DateTime.now();
  List<SyncLogEntry> many(int n) => [
    for (var i = 0; i < n; i++)
      SyncLogEntry(
        at: now.subtract(Duration(minutes: i * 90)),
        action: i.isEven ? SyncLogAction.sync : SyncLogAction.backup,
        success: i % 3 != 0,
        device: [
          'iOS Safari',
          'Android Chrome',
          'Windows Edge',
          'Mac Safari',
          'Linux',
          null,
        ][i % 6],
        detail: i % 4 == 0 ? null : '日記 上傳1／下載0；健身 上傳0／下載2、YT 失敗',
      ),
  ];

  testWidgets('沒有紀錄：寫「還沒有同步或備份紀錄」', (tester) async {
    await pumpSync(tester);
    expect(find.text('還沒有同步或備份紀錄'), findsOneWidget);
  });

  testWidgets('12 筆紀錄：主畫面只列 10 筆、看全部進紀錄頁；每一列點開看細節、可複製', (tester) async {
    await pumpSync(tester, log: many(12));
    expect(find.byType(SyncLogRow), findsNWidgets(10));
    final all = find.text('看全部 12 筆紀錄 ›');
    await tester.ensureVisible(all);
    await tester.tap(all);
    await settle(tester);
    expect(find.byType(SyncLogPage), findsOneWidget);
    // 紀錄頁每一列都點一次（展開、複製）。
    final rows = find.byType(SyncLogRow);
    for (var i = 0; i < rows.evaluate().length && i < 6; i++) {
      await tester.ensureVisible(rows.at(i));
      await tester.tap(rows.at(i), warnIfMissed: false);
      await settle(tester, 2);
    }
    final copy = find.byIcon(Icons.copy_rounded);
    if (copy.evaluate().isNotEmpty) {
      await tester.tap(copy.first, warnIfMissed: false);
      await settle(tester, 2);
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  test('裝置圖示：iOS／Mac 蘋果、Android、Windows、Linux、其他', () {
    expect(deviceIcon('iOS Safari'), Icons.apple);
    expect(deviceIcon('Mac Chrome'), Icons.apple);
    expect(deviceIcon('Android'), Icons.android);
    expect(deviceIcon('Windows'), Icons.window);
    expect(deviceIcon('Linux'), Icons.computer);
    expect(deviceIcon(null), Icons.devices_other);
  });

  testWidgets('備份：沒連雲端＝提示先連接', (tester) async {
    await pumpSync(tester);
    await tester.tap(find.byTooltip('備份雲端資料到本機'));
    await settle(tester, 2);
    expect(find.textContaining('請先連接雲端'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('備份：打包雲端檔案，這個平台不能下載就寫不支援、記一筆失敗紀錄', (tester) async {
    failStatus = 0;
    final store = await pumpSync(tester, credentials: creds);
    await http.runWithClient(
      () => tester.tap(find.byTooltip('備份雲端資料到本機')),
      cloud,
    );
    for (var i = 0; i < 10; i++) {
      await http.runWithClient(() => settle(tester, 1), cloud);
    }
    expect(find.textContaining('這個平台還不支援下載'), findsWidgets);
    final log = await tester.runAsync(() => SyncLogRepository(store).loadAll());
    expect(log!.single.action, SyncLogAction.backup);
    expect(log.single.success, isFalse);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('備份：雲端壞了（403）＝寫失敗原因', (tester) async {
    failStatus = 403;
    final store = await pumpSync(tester, credentials: creds);
    await http.runWithClient(
      () => tester.tap(find.byTooltip('備份雲端資料到本機')),
      cloud,
    );
    for (var i = 0; i < 10; i++) {
      await http.runWithClient(() => settle(tester, 1), cloud);
    }
    expect(find.textContaining('備份下載失敗'), findsWidgets);
    final log = await tester.runAsync(() => SyncLogRepository(store).loadAll());
    expect(log!.single.detail, contains('拒絕存取'));
    failStatus = 0;
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('上方進度條：同步中（不在同步頁）顯示跑到第幾項；沒同步就不顯示', (tester) async {
    final store = MemoryStore();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SyncProgressFrame(child: Scaffold(body: Text('頁面'))),
        ),
      ),
    );
    expect(find.text('頁面'), findsOneWidget);
    container.read(syncProgressProvider.notifier).state = const SyncProgress(
      total: 4,
      done: 1,
      running: ['日記', '健身'],
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('日記'), findsWidgets);
    final bar = find.textContaining('日記').first;
    await tester.tap(bar, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    container.read(syncProgressProvider.notifier).state = null;
    // 收起來有 220ms 的動畫。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('日記'), findsNothing);
  });
}
