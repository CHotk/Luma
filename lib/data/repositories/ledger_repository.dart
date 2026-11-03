import 'dart:convert';

import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 記帳（2026-11-03）：帳戶、交易、對帳點、預算四份，各自整包 JSON 讀寫、
/// 各自同步（照 id 合併、比 updatedAt、刪除永遠贏）。刪除一律蓋墓碑，
/// 不然刪掉的交易下次同步會被別台裝置復活。
class LedgerRepository {
  LedgerRepository(this._store);

  static const _accountsKey = 'ledger.accounts.v1';
  static const _txKey = 'ledger.transactions.v1';
  static const _cpKey = 'ledger.checkpoints.v1';
  static const _budgetKey = 'ledger.budgets.v1';

  final KeyValueStore _store;

  Future<List<T>> _load<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final raw = await _store.read(key);
    if (raw == null) return <T>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  Future<void> _save<T>(
    String key,
    List<T> all,
    Map<String, dynamic> Function(T) toJson,
  ) => _store.write(key, jsonEncode([for (final e in all) toJson(e)]));

  Future<List<LedgerAccount>> accountsForUpload() =>
      _load(_accountsKey, LedgerAccount.fromJson);
  Future<List<LedgerTx>> transactionsForUpload() =>
      _load(_txKey, LedgerTx.fromJson);
  Future<List<LedgerCheckpoint>> checkpointsForUpload() =>
      _load(_cpKey, LedgerCheckpoint.fromJson);
  Future<List<LedgerBudget>> budgetsForUpload() =>
      _load(_budgetKey, LedgerBudget.fromJson);

  Future<LedgerBook> loadBook() async => LedgerBook(
    accounts: await accountsForUpload(),
    txs: await transactionsForUpload(),
    checkpoints: await checkpointsForUpload(),
    budgets: await budgetsForUpload(),
  );

  // ── 帳戶 ─────────────────────────────────────────────────

  /// 新增帳戶，順便在 [openingAt] 存一個期初值的對帳點（銀行／現金是
  /// [opening] 餘額；信用卡是 [creditLimit] 跟當天的 [opening] 可用額度）。
  Future<LedgerAccount> addAccount({
    required String name,
    required LedgerAccountType type,
    required int opening,
    required DateTime openingAt,
    int? creditLimit,
  }) async {
    final now = DateTime.now();
    final all = await accountsForUpload();
    final order = all.fold(0, (m, a) => a.order > m ? a.order : m) + 1;
    final a = LedgerAccount(
      id: ledgerId(),
      name: name,
      type: type,
      creditLimit: type == LedgerAccountType.creditCard ? creditLimit : null,
      order: order,
      createdAt: now,
      updatedAt: now,
    );
    await _save(_accountsKey, [...all, a], (e) => e.toJson());
    await addCheckpoint(
      LedgerCheckpoint(
        id: ledgerId(),
        accountId: a.id,
        at: openingAt,
        balance: a.isCard ? null : opening,
        creditLimit: a.isCard ? creditLimit : null,
        available: a.isCard ? opening : null,
        note: '起始日期初值',
        updatedAt: now,
      ),
    );
    return a;
  }

  Future<void> updateAccount(LedgerAccount a) async {
    final all = await accountsForUpload();
    final i = all.indexWhere((e) => e.id == a.id);
    if (i < 0) return;
    all[i] = a.copyWith(updatedAt: DateTime.now());
    await _save(_accountsKey, all, (e) => e.toJson());
  }

  /// 刪帳戶：帳戶跟它的對帳點蓋墓碑；交易留著（帳戶名稱顯示「已刪除」）。
  Future<void> deleteAccount(String id) async {
    final now = DateTime.now();
    final all = await accountsForUpload();
    await _save(_accountsKey, [
      for (final a in all)
        a.id == id ? a.copyWith(updatedAt: now, deletedAt: now) : a,
    ], (e) => e.toJson());
    final cps = await checkpointsForUpload();
    await _save(_cpKey, [
      for (final c in cps)
        c.accountId == id && c.deletedAt == null
            ? c.copyWith(updatedAt: now, deletedAt: now)
            : c,
    ], (e) => e.toJson());
  }

  // ── 交易 ─────────────────────────────────────────────────

  Future<void> addTransactions(List<LedgerTx> txs) async {
    if (txs.isEmpty) return;
    final now = DateTime.now();
    await _save(_txKey, [
      ...await transactionsForUpload(),
      for (final t in txs)
        LedgerTx.fromJson({
          ...t.toJson(),
          'createdAt': ledgerTime(now),
          'updatedAt': ledgerTime(now),
        }),
    ], (e) => e.toJson());
  }

  Future<void> addTransaction(LedgerTx t) => addTransactions([t]);

  Future<void> updateTransaction(LedgerTx t) async {
    final all = await transactionsForUpload();
    final i = all.indexWhere((e) => e.id == t.id);
    if (i < 0) return;
    all[i] = t.copyWith(updatedAt: DateTime.now());
    await _save(_txKey, all, (e) => e.toJson());
  }

  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now();
    final all = await transactionsForUpload();
    await _save(_txKey, [
      for (final t in all)
        t.id == id ? t.copyWith(updatedAt: now, deletedAt: now) : t,
    ], (e) => e.toJson());
  }

  // ── 對帳點 ───────────────────────────────────────────────

  Future<void> addCheckpoint(LedgerCheckpoint c) async => _save(_cpKey, [
    ...await checkpointsForUpload(),
    c.copyWith(updatedAt: DateTime.now()),
  ], (e) => e.toJson());

  Future<void> updateCheckpoint(LedgerCheckpoint c) async {
    final all = await checkpointsForUpload();
    final i = all.indexWhere((e) => e.id == c.id);
    if (i < 0) return;
    all[i] = c.copyWith(updatedAt: DateTime.now());
    await _save(_cpKey, all, (e) => e.toJson());
  }

  /// 刪掉一次對帳（輸入錯了）；起始日那筆不能刪。
  Future<void> deleteCheckpoint(String id) async {
    final now = DateTime.now();
    final all = await checkpointsForUpload();
    await _save(_cpKey, [
      for (final c in all)
        c.id == id ? c.copyWith(updatedAt: now, deletedAt: now) : c,
    ], (e) => e.toJson());
  }

  // ── 預算 ─────────────────────────────────────────────────

  /// 存某個月的預算：總額＋各分類（0 或沒填＝不限制）。
  ///
  /// 預算的 id 固定是「月份|分類」，所以清掉時**存 0、不蓋墓碑**——同步
  /// 合併是「刪除永遠贏」，蓋了墓碑之後同一個 id 就再也設不回來。
  Future<void> setBudgets(
    String month,
    int total,
    Map<String, int> byCategory,
  ) async {
    final now = DateTime.now();
    final all = {for (final b in await budgetsForUpload()) b.id: b};
    void put(String? cat, int v) {
      final id = LedgerBudget.budgetId(month, cat);
      final old = all[id];
      final amount = v < 0 ? 0 : v;
      if (old == null && amount == 0 && cat != null) return;
      if (old != null && old.amount == amount) return;
      all[id] = LedgerBudget(
        month: month,
        category: cat,
        amount: amount,
        updatedAt: now,
      );
    }

    put(null, total);
    for (final c in ledgerExpenseCats.keys) {
      if (c == ledgerUncategorized) continue;
      put(c, byCategory[c] ?? 0);
    }
    await _save(_budgetKey, all.values.toList(), (e) => e.toJson());
  }

  // ── 同步：把雲端的併回本機，回傳實際異動幾筆 ─────────────

  Future<int> _merge<T>(
    String key,
    List<T> incoming,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson,
    String Function(T) idOf,
    DateTime Function(T) updatedAtOf,
    DateTime? Function(T) deletedAtOf,
  ) async {
    if (incoming.isEmpty) return 0;
    final before = await _load(key, fromJson);
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: idOf,
      priority: SeedMergePriority.local,
      deletedAtOf: deletedAtOf,
      updatedAtOf: updatedAtOf,
    );
    await _save(key, merged, toJson);
    return ytDiffCount(
      [for (final e in before) toJson(e)],
      [for (final e in merged) toJson(e)],
    );
  }

  Future<int> mergeAccountsFromCloud(List<LedgerAccount> incoming) => _merge(
    _accountsKey,
    incoming,
    LedgerAccount.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );

  Future<int> mergeTransactionsFromCloud(List<LedgerTx> incoming) => _merge(
    _txKey,
    incoming,
    LedgerTx.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );

  Future<int> mergeCheckpointsFromCloud(List<LedgerCheckpoint> incoming) =>
      _merge(
        _cpKey,
        incoming,
        LedgerCheckpoint.fromJson,
        (e) => e.toJson(),
        (e) => e.id,
        (e) => e.syncedAt,
        (e) => e.deletedAt,
      );

  Future<int> mergeBudgetsFromCloud(List<LedgerBudget> incoming) => _merge(
    _budgetKey,
    incoming,
    LedgerBudget.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );
}
