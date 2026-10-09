import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/usdt_twd_rate_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/crypto_watch/trade_ui.dart';
import 'package:lume/features/settings/other_settings_page.dart';
import 'package:lume/shared/widgets/open_settings.dart';

/// 2026-10-10 使用者要求：USDT 後面加上台幣換算，匯率預設 31、設定可改；
/// 同一次回報交易頁的齒輪打開是英文學習的設定。
void main() {
  test('台幣換算取整數、損益帶正負號', () {
    expect(fmtTwd(400, 31), '≈ NT\$12,400');
    expect(fmtTwd(-120, 31, signed: true), '≈ −NT\$3,720');
    expect(fmtTwd(12.5, 31.5, signed: true), '≈ +NT\$394');
    expect(fmtTwd(0, 31, signed: true), '≈ NT\$0');
  });

  test('匯率沒設定過是 31，存了讀得回來，亂掉的值退回預設', () async {
    final store = _MemoryStore();
    final s = UsdtTwdRateStore(store);
    expect(await s.load(), 31);
    await s.save(32.4);
    expect(await s.load(), 32.4);
    store.data['trade_log.usdt_twd_rate.v1'] = '-1';
    expect(await s.load(), 31);
    // 加同步之前存的是單純一個數字，照樣讀得到，當成很舊的設定。
    store.data['trade_log.usdt_twd_rate.v1'] = '32.5';
    final legacy = await s.loadRecord();
    expect(legacy!.rate, 32.5);
    expect(legacy.updatedAt, DateTime(2000));
  });

  test('匯率跨裝置同步：後改的贏，沒設定過的那台拿雲端的', () async {
    final bucket = <String, List<int>>{};
    http.Client cloud() => MockClient((req) async {
      final key = req.url.pathSegments.skip(1).join('/');
      String etag(List<int> b) => md5.convert(b).toString();
      switch (req.method) {
        case 'GET' || 'HEAD':
          final b = bucket[key];
          if (b == null) return http.Response('', 404);
          return req.method == 'GET'
              ? http.Response.bytes(b, 200, headers: {'etag': '"${etag(b)}"'})
              : http.Response('', 200, headers: {'etag': '"${etag(b)}"'});
        case 'PUT':
          bucket[key] = req.bodyBytes;
          return http.Response(
            '',
            200,
            headers: {'etag': '"${etag(req.bodyBytes)}"'},
          );
      }
      return http.Response('', 400);
    });
    R2SyncService service(KeyValueStore meta) => R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: cloud(),
      ),
      meta,
    );
    final phone = _MemoryStore(), pc = _MemoryStore();

    // 兩台都沒設定過：什麼都不傳。
    expect(await service(phone).syncUsdtTwdRate(UsdtTwdRateStore(phone)), (
      downloaded: 0,
      uploaded: 0,
    ));
    expect(bucket, isEmpty);

    // 手機改成 32.5 → 同步 → 電腦同步後也是 32.5。
    await UsdtTwdRateStore(phone).save(32.5);
    expect(
      (await service(phone).syncUsdtTwdRate(UsdtTwdRateStore(phone))).uploaded,
      1,
    );
    expect(
      (await service(pc).syncUsdtTwdRate(UsdtTwdRateStore(pc))).downloaded,
      1,
    );
    expect(await UsdtTwdRateStore(pc).load(), 32.5);

    // 電腦後來改成 30 → 手機同步後跟著變。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await UsdtTwdRateStore(pc).save(30);
    await service(pc).syncUsdtTwdRate(UsdtTwdRateStore(pc));
    await service(phone).syncUsdtTwdRate(UsdtTwdRateStore(phone));
    expect(await UsdtTwdRateStore(phone).load(), 30);
  });

  testWidgets('交易頁的齒輪進的是交易自己的設定，改匯率會存起來', (tester) async {
    final store = _MemoryStore();
    final router = GoRouter(
      initialLocation: '/crypto-watch',
      routes: [
        GoRoute(
          path: '/crypto-watch',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => openSettings(context),
              child: const Text('齒輪'),
            ),
          ),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const Text('英文學習設定')),
        GoRoute(
          path: '/settings/other',
          builder: (_, state) =>
              OtherSettingsPage(fromLocation: state.extra as String?),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('齒輪'));
    await tester.pumpAndSettle();
    expect(find.text('英文學習設定'), findsNothing);
    expect(find.text('USDT 換台幣匯率'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '32.5');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pump();
    expect(await UsdtTwdRateStore(store).load(), 32.5);
    // 匯率也最多小數第一位：打 31.25 → 31.3。
    await tester.enterText(find.byType(TextField), '31.25');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '31.3',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('USDT 換台幣匯率')),
    );
    expect(container.read(usdtTwdRateProvider), 32.5);
    expect(find.text('改回預設 31'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
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
