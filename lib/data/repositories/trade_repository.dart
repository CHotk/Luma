import 'dart:convert';

import '../../domain/models/trade_entry.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 交易&自律的「每一單」跟「每月月初資金」（2026-10-08）。
///
/// 整包 JSON 讀寫，刪除用墓碑標記，跟抽菸／喝酒記錄同一套多裝置同步做法。
class TradeRepository {
  TradeRepository(this._store);

  static const _tradesKey = 'trade_log.trades.v1';
  static const _capitalKey = 'trade_log.capital.v1';

  final KeyValueStore _store;

  // ── 交易 ─────────────────────────────────────────────────

  Future<List<TradeEntry>> _loadAllRaw() async {
    final raw = await _store.read(_tradesKey);
    if (raw == null) return <TradeEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(TradeEntry.fromJson)
        .toList();
  }

  Future<void> _write(List<TradeEntry> all) =>
      _store.write(_tradesKey, jsonEncode([for (final e in all) e.toJson()]));

  /// 給 UI 用：已刪除的濾掉，新開的在前面。
  Future<List<TradeEntry>> loadAll() async =>
      (await _loadAllRaw()).where((e) => e.deletedAt == null).toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  /// 給同步用：連刪除標記都要看得到。
  Future<List<TradeEntry>> allForUpload() => _loadAllRaw();

  Future<TradeEntry> add({
    required String symbol,
    required bool isLong,
    required double leverage,
    required double margin,
    required DateTime openedAt,
    DateTime? closedAt,
    double? pnl,
    String? note,
  }) async {
    final entry = TradeEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      symbol: symbol,
      isLong: isLong,
      leverage: leverage,
      margin: margin,
      openedAt: openedAt,
      closedAt: closedAt,
      pnl: pnl,
      note: note,
    ).stamped();
    await _write([...await _loadAllRaw(), entry]);
    return entry;
  }

  /// 平倉結算，回傳結算後的那一筆；找不到回傳 null。
  Future<TradeEntry?> close(String id, {required double pnl, DateTime? at}) =>
      _update(id, (e) => e.closed(pnl: pnl, at: at ?? DateTime.now()));

  /// 編輯整單，回傳改完的那一筆；找不到回傳 null。
  Future<TradeEntry?> edit(
    String id, {
    required String symbol,
    required bool isLong,
    required double leverage,
    required double margin,
    required DateTime openedAt,
    DateTime? closedAt,
    double? pnl,
    String? note,
  }) => _update(
    id,
    (e) => e.edited(
      symbol: symbol,
      isLong: isLong,
      leverage: leverage,
      margin: margin,
      openedAt: openedAt,
      closedAt: closedAt,
      pnl: pnl,
      note: note,
    ),
  );

  Future<void> delete(String id) =>
      _update(id, (e) => e.stamped(deleted: true));

  Future<TradeEntry?> _update(
    String id,
    TradeEntry Function(TradeEntry) change,
  ) async {
    final all = await _loadAllRaw();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    all[i] = change(all[i]);
    await _write(all);
    return all[i];
  }

  /// 把 R2 雲端抓下來的交易併回本機，回傳實際異動幾筆。
  Future<int> mergeFromCloud(List<TradeEntry> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadAllRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.syncedAt,
    );
    await _write(merged);
    return ytDiffCount(
      [for (final e in before) e.toJson()],
      [for (final e in merged) e.toJson()],
    );
  }

  // ── 月初資金 ─────────────────────────────────────────────

  Future<List<TradeMonthCapital>> _loadCapitalRaw() async {
    final raw = await _store.read(_capitalKey);
    if (raw == null) return <TradeMonthCapital>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(TradeMonthCapital.fromJson)
        .toList();
  }

  Future<void> _writeCapital(List<TradeMonthCapital> all) =>
      _store.write(_capitalKey, jsonEncode([for (final e in all) e.toJson()]));

  /// `yyyy-MM` → 月初資金。
  Future<Map<String, double>> loadCapitals() async => {
    for (final c in await _loadCapitalRaw()) c.id: c.amount,
  };

  Future<List<TradeMonthCapital>> capitalForUpload() => _loadCapitalRaw();

  Future<void> setCapital(DateTime month, double amount) async {
    final id = TradeMonthCapital.idOf(month);
    final all = (await _loadCapitalRaw()).where((c) => c.id != id).toList()
      ..add(
        TradeMonthCapital(id: id, amount: amount, updatedAt: DateTime.now()),
      );
    await _writeCapital(all);
  }

  Future<int> mergeCapitalFromCloud(List<TradeMonthCapital> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadCapitalRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      updatedAtOf: (e) => e.syncedAt,
    );
    await _writeCapital(merged);
    return ytDiffCount(
      [for (final e in before) e.toJson()],
      [for (final e in merged) e.toJson()],
    );
  }
}
