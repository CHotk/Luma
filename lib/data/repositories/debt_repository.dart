import 'dart:convert';

import '../../domain/models/debt.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 負債每月還款表（2026-10-08）：債務、繳款紀錄、設定（月收入）三份，
/// 各自整包 JSON 讀寫、各自同步。刪除都用墓碑標記；繳款紀錄是 log，
/// 一筆都不真的刪掉。
class DebtRepository {
  DebtRepository(this._store);

  static const _debtsKey = 'debt.debts.v1';
  static const _paymentsKey = 'debt.payments.v1';
  static const _settingsKey = 'debt.settings.v1';
  static const incomeId = 'income';

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

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ── 債務 ─────────────────────────────────────────────────

  Future<List<Debt>> debtsForUpload() => _load(_debtsKey, Debt.fromJson);

  Future<List<Debt>> loadDebts() async =>
      (await debtsForUpload()).where((d) => d.deletedAt == null).toList();

  Future<Debt> addDebt(Debt draft) async {
    final d = Debt.fromJson({
      ...draft.toJson(),
      'id': _newId(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _save(_debtsKey, [...await debtsForUpload(), d], (e) => e.toJson());
    return d;
  }

  Future<void> updateDebt(Debt d) async {
    final all = await debtsForUpload();
    final i = all.indexWhere((e) => e.id == d.id);
    if (i < 0) return;
    all[i] = d.copyWith(updatedAt: DateTime.now());
    await _save(_debtsKey, all, (e) => e.toJson());
  }

  /// 刪除債務，連同它的繳款紀錄一起蓋墓碑。
  Future<void> deleteDebt(String id) async {
    final now = DateTime.now();
    final all = await debtsForUpload();
    final i = all.indexWhere((e) => e.id == id);
    if (i >= 0) {
      all[i] = all[i].copyWith(updatedAt: now, deletedAt: now);
      await _save(_debtsKey, all, (e) => e.toJson());
    }
    final pays = await paymentsForUpload();
    await _save(_paymentsKey, [
      for (final p in pays)
        p.debtId == id && p.deletedAt == null ? p.deleted() : p,
    ], (e) => e.toJson());
  }

  // ── 繳款紀錄 ─────────────────────────────────────────────

  Future<List<DebtPayment>> paymentsForUpload() =>
      _load(_paymentsKey, DebtPayment.fromJson);

  Future<List<DebtPayment>> loadPayments() async =>
      (await paymentsForUpload()).where((p) => p.deletedAt == null).toList();

  Future<DebtPayment> addPayment({
    required String debtId,
    required DateTime date,
    required double amount,
    int? period,
  }) async {
    final p = DebtPayment(
      id: _newId(),
      debtId: debtId,
      period: period,
      date: date,
      amount: amount,
      updatedAt: DateTime.now(),
    );
    await _save(_paymentsKey, [
      ...await paymentsForUpload(),
      p,
    ], (e) => e.toJson());
    return p;
  }

  /// 取消一筆已繳（按錯時用）：蓋墓碑，不真的刪。
  Future<void> cancelPayment(String id) async {
    final all = await paymentsForUpload();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    all[i] = all[i].deleted();
    await _save(_paymentsKey, all, (e) => e.toJson());
  }

  // ── 設定 ─────────────────────────────────────────────────

  Future<List<DebtSetting>> settingsForUpload() =>
      _load(_settingsKey, DebtSetting.fromJson);

  Future<double?> loadIncome() async {
    for (final s in await settingsForUpload()) {
      if (s.id == incomeId) return s.value;
    }
    return null;
  }

  Future<void> setIncome(double value) async {
    final all = (await settingsForUpload()).where((s) => s.id != incomeId);
    await _save(_settingsKey, [
      ...all,
      DebtSetting(id: incomeId, value: value, updatedAt: DateTime.now()),
    ], (e) => e.toJson());
  }

  // ── 同步：把雲端的併回本機，回傳實際異動幾筆 ─────────────

  Future<int> _merge<T>(
    String key,
    List<T> incoming,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson,
    String Function(T) idOf,
    DateTime Function(T) updatedAtOf, {
    DateTime? Function(T)? deletedAtOf,
  }) async {
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

  Future<int> mergeDebtsFromCloud(List<Debt> incoming) => _merge(
    _debtsKey,
    incoming,
    Debt.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    deletedAtOf: (e) => e.deletedAt,
  );

  Future<int> mergePaymentsFromCloud(List<DebtPayment> incoming) => _merge(
    _paymentsKey,
    incoming,
    DebtPayment.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    deletedAtOf: (e) => e.deletedAt,
  );

  Future<int> mergeSettingsFromCloud(List<DebtSetting> incoming) => _merge(
    _settingsKey,
    incoming,
    DebtSetting.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
  );
}
