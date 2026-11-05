import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/i88_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// i88 要多裝置同步：兩台裝置（各自的本機儲存）透過同一個假的雲端 bucket，
/// 輸贏紀錄、刪除、編輯、每月目標都要兩邊對得上。
void main() {
  test('兩台裝置互相同步：輸贏紀錄、刪除、編輯、每月目標都帶得過去', () async {
    final bucket = <String, List<int>>{};
    http.Client cloud() => MockClient((req) async {
      final key = req.url.pathSegments.skip(1).join('/');
      String etag(List<int> b) => md5.convert(b).toString();
      switch (req.method) {
        case 'GET':
          final b = bucket[key];
          return b == null
              ? http.Response('', 404)
              : http.Response.bytes(b, 200, headers: {'etag': '"${etag(b)}"'});
        case 'HEAD':
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
    Future<void> sync(_MemoryStore s) => service(s).syncI88(I88Repository(s));

    // 手機：贏 1,200、輸 500、設目標。
    final p = I88Repository(phone);
    final win = await p.add(at: DateTime(2026, 11, 2, 21), amount: 1200);
    final lose = await p.add(
      at: DateTime(2026, 11, 3, 22),
      amount: -500,
      note: '輸',
    );
    await p.setTarget(30000);
    await sync(phone);

    // 電腦：同步後都有。
    await sync(pc);
    final c = I88Repository(pc);
    var list = await c.loadEntries();
    expect(list.map((e) => e.amount).toSet(), {1200, -500});
    expect(await c.loadTarget(), 30000);

    // 電腦：改金額、刪掉輸的、改目標。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.update(
      list.firstWhere((e) => e.id == win.id).copyWith(amount: 1500),
    );
    await c.delete(lose.id);
    await c.setTarget(40000);
    await sync(pc);

    // 手機：同步後看到改動、刪除、新目標。
    await sync(phone);
    list = await p.loadEntries();
    expect(list.map((e) => e.id), [win.id]);
    expect(list.single.amount, 1500);
    expect(await p.loadTarget(), 40000);

    // 操作紀錄：兩邊動作都在（新增 2、改目標 2、編輯 1、刪除 1），而且兩台一樣多、一筆都沒少。
    await sync(pc);
    final logP = await p.loadLog(), logC = await c.loadLog();
    expect(logP.length, 6);
    expect(logC.map((e) => e.id).toSet(), logP.map((e) => e.id).toSet());
    expect(logP.map((e) => e.action).where((a) => a == '新增').length, 2);
    expect(logP.any((e) => e.action == '刪除'), isTrue);
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
