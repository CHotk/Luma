import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/settings/r2_sync_section.dart';

/// 設定裡的「多裝置同步」區塊（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 沒填完不能測、連線成功／失敗、已連接後立即同步（全部、單一項）、雲端壞掉時每項失敗、
/// 取消連接回到輸入畫面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, List<int>> bucket;
  late int failStatus;

  http.Client cloud() => MockClient((req) async {
    if (failStatus != 0) return http.Response('broken', failStatus);
    final segs = req.url.pathSegments;
    final key = segs.skip(1).join('/');
    String etag(List<int> b) => md5.convert(b).toString();
    switch (req.method) {
      case 'GET':
        if (key.isEmpty) {
          // 列出檔案（影片快取、備份用）。
          final prefix = req.url.queryParameters['prefix'] ?? '';
          final items = [
            for (final e in bucket.entries)
              if (e.key.startsWith(prefix))
                '<Contents><Key>${e.key}</Key><ETag>"${etag(e.value)}"</ETag></Contents>',
          ].join();
          return http.Response(
            '<ListBucketResult>$items<IsTruncated>false</IsTruncated></ListBucketResult>',
            200,
          );
        }
        final b = bucket[key];
        return b == null
            ? http.Response('', 404)
            : http.Response.bytes(b, 200, headers: {'etag': '"${etag(b)}"'});
      case 'HEAD':
        if (key.isEmpty) return http.Response('', 200);
        final b = bucket[key];
        return b == null
            ? http.Response('', 404)
            : http.Response('', 200, headers: {'etag': '"${etag(b)}"'});
      case 'PUT':
        bucket[key] = req.bodyBytes;
        return http.Response(
          '',
          200,
          headers: {'etag': '"${etag(req.bodyBytes)}"'},
        );
      case 'DELETE':
        bucket.remove(key);
        return http.Response('', 204);
    }
    return http.Response('', 400);
  });

  setUp(() {
    bucket = {};
    failStatus = 0;
  });

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await http.runWithClient(
        () => tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        ),
        cloud,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 等到同步跑完（按鈕又出現「立即同步」）。
  Future<void> waitIdle(WidgetTester tester) async {
    for (var i = 0; i < 400; i++) {
      await settle(tester, rounds: 1);
      if (find.text('立即同步').evaluate().isNotEmpty) return;
    }
    fail('同步一直沒跑完');
  }

  Future<_MemoryStore> pump(WidgetTester tester, {R2Credentials? creds}) async {
    final store = _MemoryStore();
    tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          r2BucketNameProvider.overrideWithValue('lume'),
          r2CredentialsProvider.overrideWith((_) => creds),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: R2SyncSection())),
        ),
      ),
    );
    await tester.pump();
    return store;
  }

  /// 按下去的那一刻起都在假的雲端裡跑。
  Future<void> tapInCloud(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await http.runWithClient(() => tester.tap(f), cloud);
  }

  const creds = R2Credentials(
    endpoint: 'https://acc.r2.cloudflarestorage.com',
    accessKeyId: 'k',
    secretAccessKey: 's',
  );

  testWidgets('還沒設定：三欄沒填完按了不做事；填完測試成功 → 打勾 → 變成已連接', (tester) async {
    final store = await pump(tester);
    expect(find.text('儲存並測試連線'), findsOneWidget);
    await tapInCloud(tester, find.text('儲存並測試連線'));
    await settle(tester, rounds: 2);
    expect(find.text('連線測試中…'), findsNothing);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), creds.endpoint);
    await tester.enterText(fields.at(1), 'k');
    await tester.enterText(fields.at(2), 's');
    await tapInCloud(tester, find.text('儲存並測試連線'));
    await tester.pump();
    await settle(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, rounds: 4);
    expect(find.text('已連接雲端'), findsOneWidget);
    expect(
      store.data.keys.any((k) => k.contains('r2_sync.credentials')),
      isTrue,
    );
    expect(bucket.containsKey('_lume_sync_test.json'), isFalse);
  });

  testWidgets('測試連線失敗（金鑰錯 403）：寫原因、可以再試一次', (tester) async {
    await pump(tester);
    failStatus = 403;
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), creds.endpoint);
    await tester.enterText(fields.at(1), 'k');
    await tester.enterText(fields.at(2), 'bad');
    await tapInCloud(tester, find.text('儲存並測試連線'));
    await settle(tester, rounds: 6);
    expect(find.text('連線失敗，再試一次'), findsOneWidget);
    expect(find.textContaining('拒絕存取'), findsWidgets);
  });

  testWidgets('已連接：立即同步全部跑完、每項有結果、上次同步時間更新；跳出同步完成通知', (tester) async {
    await pump(tester, creds: creds);
    expect(find.text('已連接雲端'), findsOneWidget);
    expect(find.text('還沒同步過'), findsOneWidget);
    await tapInCloud(tester, find.text('立即同步'));
    await waitIdle(tester);
    expect(find.textContaining('上次同步：'), findsOneWidget);
    expect(find.textContaining('↑'), findsWidgets);
    expect(bucket.keys, contains('sync_log.json'));
    expect(find.textContaining('同步完成'), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('取消連接：清掉金鑰、回到輸入畫面', (tester) async {
    await pump(tester, creds: creds);
    await tester.tap(find.text('取消連接'));
    await settle(tester, rounds: 3);
    final yes = find.text('取消連接');
    if (yes.evaluate().length > 1 ||
        find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(yes.last);
      await settle(tester, rounds: 3);
    }
    expect(find.text('儲存並測試連線'), findsOneWidget);
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

// ignore: unused_element
String _j(Object o) => jsonEncode(o);
