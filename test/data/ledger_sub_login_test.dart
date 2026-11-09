import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 每月扣款的繳款登入帳號／密碼：只存本機，不在同步用的那份扣款資料裡、也不進操作紀錄。
void main() {
  test('帳號密碼存、改、清空；不出現在同步用資料跟操作紀錄', () async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final s = await repo.addSubscription(
      name: '電信費',
      amount: 599,
      day: 5,
      payUrl: 'pay.example.com',
    );
    expect(await repo.loadSubLogins(), isEmpty);

    await repo.saveSubLogin(s.id, 'me@ex.com', 'Pa\$\$w0rd');
    var all = await repo.loadSubLogins();
    expect(all[s.id]!.user, 'me@ex.com');
    expect(all[s.id]!.pass, 'Pa\$\$w0rd');

    // 同步用的扣款資料、操作紀錄都沒有密碼。
    final subs = await repo.subscriptionsForUpload();
    expect(
      jsonEncode([for (final e in subs) e.toJson()]),
      isNot(contains('w0rd')),
    );
    final log = await repo.logForUpload();
    expect(
      jsonEncode([for (final e in log) e.toJson()]),
      isNot(contains('w0rd')),
    );

    // 改帳號、只留密碼。
    await repo.saveSubLogin(s.id, '', 'new-pass');
    all = await repo.loadSubLogins();
    expect(all[s.id]!.user, '');
    expect(all[s.id]!.pass, 'new-pass');

    // 兩個都空 = 移掉。
    await repo.saveSubLogin(s.id, '', '');
    expect(await repo.loadSubLogins(), isEmpty);
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
