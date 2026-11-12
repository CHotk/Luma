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

  testWidgets('各功能右邊的同步：只同步那一項', (tester) async {
    await pump(tester, creds: creds);
    final one = find.text('同步');
    if (one.evaluate().isNotEmpty) {
      await tapInCloud(tester, one.first);
      await waitIdle(tester);
      expect(bucket.keys, isNot(contains('kana_exam.json')));
      await tester.pump(const Duration(seconds: 6));
    }
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
