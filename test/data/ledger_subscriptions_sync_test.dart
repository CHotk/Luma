import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 每月訂閱要跟記帳一起多裝置同步（新增、編輯、停用、刪除都帶得過去），
/// 而且每個動作都進記帳的操作紀錄。
void main() {
  test('兩台裝置同步訂閱：新增、編輯、停用、刪除都對得上，操作紀錄每個動作一筆', () async {
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
    Future<void> sync(_MemoryStore s) =>
        service(s).syncLedger(LedgerRepository(s));

    final a = LedgerRepository(phone);
    final netflix = await a.addSubscription(
      name: 'Netflix',
      amount: 390,
      day: 12,
    );
    final spotify = await a.addSubscription(
      name: 'Spotify',
      amount: 149,
      day: 3,
      note: '家庭方案',
    );
    await sync(phone);
    await sync(pc);

    final b = LedgerRepository(pc);
    var list = await b.loadSubscriptions();
    expect(list.map((s) => s.name), ['Spotify', 'Netflix']); // 3 號、12 號
    expect(list.first.note, '家庭方案');

    // 電腦：改金額、停用 Spotify。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.updateSubscription(list.last.copyWith(amount: 490));
    await b.updateSubscription(list.first.copyWith(active: false));
    await sync(pc);
    await sync(phone);
    list = await a.loadSubscriptions();
    expect(list.map((s) => s.name), ['Netflix', 'Spotify']); // 停用的排後面
    expect(list.first.amount, 490);
    expect(list.last.active, isFalse);

    // 手機：刪掉 Netflix（墓碑），電腦同步後不會又長回來。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.deleteSubscription(netflix.id);
    await sync(phone);
    await sync(pc);
    list = await b.loadSubscriptions();
    expect(list.map((s) => s.id), [spotify.id]);
    await sync(pc);
    await sync(phone);
    expect((await a.loadSubscriptions()).map((s) => s.id), [spotify.id]);

    // 操作紀錄：新增 2、編輯 1（金額）、停用 1、刪除 1，兩邊聯集都看得到。
    final log = await a.loadLog();
    final actions = log.map((e) => e.action).toList();
    expect(actions.where((x) => x == '新增扣款').length, 2);
    expect(actions.where((x) => x == '編輯扣款').length, 1);
    expect(actions.where((x) => x == '停用扣款').length, 1);
    expect(actions.where((x) => x == '刪除扣款').length, 1);
    final edit = log.firstWhere((e) => e.action == '編輯扣款');
    expect(edit.detail, contains('金額：\$390 → \$490'));
    final stop = log.firstWhere((e) => e.action == '停用扣款');
    expect(stop.summary, contains('Spotify'));
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
