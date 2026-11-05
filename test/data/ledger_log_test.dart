import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';

/// 記帳操作紀錄（2026-11-03 使用者：每個動作都存一份 log，只會變大、永遠不刪）。
void main() {
  LedgerTx tx(String id, int amount, String acct, {String merchant = '便當'}) =>
      LedgerTx(
        id: id,
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 11, 5, 12),
        amount: amount,
        accountId: acct,
        category: '餐飲',
        merchant: merchant,
      );

  test('每個動作都記一筆，而且只增不減（連刪除也是多一筆）', () async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book = await repo.loadBook(); // 建預設帳戶
    final cash = book.accounts.firstWhere(
      (a) => a.type == LedgerAccountType.cash,
    );
    var n = (await repo.loadLog()).length;
    Future<LedgerLogEntry> last() async => (await repo.loadLog()).first;
    Future<void> step(String action, Future<void> Function() act) async {
      await act();
      final log = await repo.loadLog();
      expect(log.length, greaterThan(n), reason: action);
      n = log.length;
      expect((await last()).action, action);
    }

    await Future<void>.delayed(const Duration(milliseconds: 2));
    final t = tx('t1', 120, cash.id);
    await step('新增', () => repo.addTransaction(t));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step('編輯', () => repo.updateTransaction(t.copyWith(amount: 150)));
    expect((await last()).detail, contains('金額：\$120 → \$150'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step(
      '標記旗幟',
      () => repo.updateTransaction(t.copyWith(amount: 150, flagged: true)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step(
      '取消標記',
      () => repo.updateTransaction(t.copyWith(amount: 150, flagged: false)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final pf = t.copyWith(
      amount: 150,
      paidFor: () => const PaidFor(amount: 75, people: '小美'),
    );
    await step('編輯', () => repo.updateTransaction(pf));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step(
      '他給了',
      () => repo.updateTransaction(
        pf.copyWith(paidFor: () => pf.paidFor!.copyWith(settled: true)),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step('預算', () => repo.setBudgets('2026-11', 30000, {'餐飲': 6000}));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step(
      '對帳／填餘額',
      () => repo.addCheckpoint(
        LedgerCheckpoint(
          id: 'c1',
          accountId: cash.id,
          at: DateTime(2026, 11, 5, 13),
          balance: 1000,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step('刪除', () => repo.deleteTransaction('t1'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await step(
      '匯入',
      () => repo.addTransactions([
        LedgerTx(
          id: 't2',
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, 6),
          amount: 10,
          accountId: cash.id,
          category: '餐飲',
          merchant: '糖果',
          source: 'paste',
          raw: '現金｜2026/11/06 00:00｜餐飲｜糖果｜10',
        ),
      ]),
    );
    expect((await last()).detail, contains('原文：'));
    // 沒有任何刪除 log 的路：前面每一筆都還在。
    final all = await repo.loadLog();
    expect(all.map((e) => e.action), containsAll(['新增', '編輯', '刪除', '他給了']));
    expect(all.map((e) => e.id).toSet().length, all.length);
  });

  test('操作紀錄多裝置同步：兩邊聯集、不會少', () async {
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
    final p = LedgerRepository(phone), c = LedgerRepository(pc);
    final bp = await p.loadBook();
    await p.addTransaction(tx('a', 100, bp.accounts.first.id, merchant: '手機'));
    await sync(phone);
    await sync(pc);
    final bc = await c.loadBook();
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await c.addTransaction(tx('b', 200, bc.accounts.first.id, merchant: '電腦'));
    await sync(pc);
    await sync(phone);
    final a = await p.loadLog(), b = await c.loadLog();
    expect(a.map((e) => e.summary).join(), contains('手機'));
    expect(a.map((e) => e.summary).join(), contains('電腦'));
    expect(a.length, b.length, reason: '兩邊紀錄一樣多');
    expect(a.map((e) => e.id).toSet(), b.map((e) => e.id).toSet());
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
