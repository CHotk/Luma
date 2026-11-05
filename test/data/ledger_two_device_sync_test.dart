import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';

/// 記帳要多裝置同步：兩台裝置（各自的本機儲存）透過同一個假的雲端 bucket
/// 同步，帳戶、交易、對帳點、預算、刪除、編輯都要兩邊對得上。
void main() {
  test('兩台裝置互相同步：帳戶、交易、對帳、預算、刪除、編輯都帶得過去', () async {
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

    // 手機：開始記帳（活存＋信用卡，另一個戶頭沒填餘額）、記兩筆、對一次帳、設預算。
    await LedgerRepository(
      phone,
    ).addAccount(name: '郵局', type: LedgerAccountType.bank);
    final start = DateTime(2026, 10, 1);
    final repo = LedgerRepository(phone);
    final bank = await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 45000,
      openingAt: start,
    );
    final card = await repo.addAccount(
      name: '中信信用卡',
      type: LedgerAccountType.creditCard,
      opening: 87600,
      openingAt: start,
      creditLimit: 100000,
    );
    final lunch = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 10, 9, 12),
      amount: 1000,
      accountId: card.id,
      category: '餐飲',
      merchant: '鼎泰豐',
      paidFor: const PaidFor(amount: 600, people: '小美'),
    );
    final rent = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 10, 2, 9),
      amount: 12000,
      accountId: bank.id,
      category: '居家',
    );
    await repo.addTransactions([lunch, rent]);
    await repo.addCheckpoint(
      LedgerCheckpoint(
        id: ledgerId(),
        accountId: bank.id,
        at: DateTime(2026, 10, 24, 20),
        balance: 45000 - 12000 - 630,
      ),
    );
    await repo.setBudgets('2026-10', 30000, {'餐飲': 6000});
    await sync(phone);

    // 電腦：同步後全部都有、算出來一樣。
    await sync(pc);
    var b = await LedgerRepository(pc).loadBook();
    expect(b.accounts.map((a) => a.name), ['郵局', '中信活存', '中信信用卡', '台新卡']);
    expect(b.stateOf(b.accounts.first), isNull);
    expect(b.txs, hasLength(2));
    expect(b.stateOf(b.account(bank.id)!)!.miss, 630);
    expect(b.monthStats(2026, 10).spend, 12400);
    expect(b.budgetOf(2026, 10).byCategory['餐飲'], 6000);

    // 電腦：刪掉房租、小美還錢、餐飲預算拿掉、帳戶改名。
    final pcRepo = LedgerRepository(pc);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pcRepo.deleteTransaction(rent.id);
    await pcRepo.addTransaction(
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.repayment,
        occurredAt: DateTime(2026, 10, 14),
        amount: 600,
        accountId: bank.id,
        linkedId: lunch.id,
      ),
    );
    await pcRepo.setBudgets('2026-10', 30000, {'餐飲': 0});
    await pcRepo.updateAccount(b.account(bank.id)!.copyWith(name: '中信活儲'));
    await sync(pc);

    // 手機：同步後看到刪除、還錢、預算拿掉、改名。
    await sync(phone);
    b = await LedgerRepository(phone).loadBook();
    expect(b.txs.map((t) => t.id), isNot(contains(rent.id)));
    expect(b.oweTotal, 0);
    expect(b.budgetOf(2026, 10).byCategory, isEmpty);
    expect(b.account(bank.id)!.name, '中信活儲');

    // 預算拿掉之後同一個月同一個分類還能再設回來（不能被墓碑卡住）。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await LedgerRepository(phone).setBudgets('2026-10', 30000, {'餐飲': 5000});
    await sync(phone);
    await sync(pc);
    b = await LedgerRepository(pc).loadBook();
    expect(b.budgetOf(2026, 10).byCategory['餐飲'], 5000);
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
