import 'dart:convert';

import '../../domain/models/i88.dart';
import '../export/device_label.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// i88（2026-11-03）：每一筆輸贏、每月目標兩份，各自整包 JSON 讀寫、各自同步。
/// 刪除用墓碑標記（不然刪掉的紀錄下次同步會被別台裝置復活）。
///
/// 2026-11-04 使用者：每個動作（新增、編輯、刪除、改每月目標）自動記一筆操作紀錄，
/// 只增不改不刪不裁剪，同步時兩邊聯集（跟記帳的操作紀錄各自獨立一份）。
class I88Repository {
  I88Repository(this._store);

  static const _entriesKey = 'i88.entries.v1';
  static const _settingsKey = 'i88.settings.v1';
  static const _logKey = 'i88.log.v1';
  static const targetId = 'monthly_target';

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

  // ── 操作紀錄 ─────────────────────────────────────────────

  Future<List<I88LogEntry>> logForUpload() =>
      _load(_logKey, I88LogEntry.fromJson);

  /// 給畫面用：新的在前。
  Future<List<I88LogEntry>> loadLog() async =>
      (await logForUpload())..sort((a, b) => b.at.compareTo(a.at));

  /// 記一筆操作。只往後加，沒有任何刪除或裁剪的路。
  Future<void> _log(
    String action,
    String summary, {
    String detail = '',
    String? refId,
  }) async {
    await _save(_logKey, [
      ...await logForUpload(),
      I88LogEntry(
        id: i88Id(),
        at: DateTime.now(),
        action: action,
        summary: summary,
        detail: detail,
        refId: refId,
        device: currentDeviceLabel(),
      ),
    ], (x) => x.toJson());
  }

  static String _money(int v) =>
      v == 0 ? '\$0' : '${v > 0 ? '贏' : '輸'} \$${v.abs()}';

  static String _day(DateTime t) => '${t.year}/${t.month}/${t.day}';

  static String _time(DateTime t) =>
      '${_day(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 「贏 $500（2026/11/5 備註）」。
  static String describe(I88Entry e) =>
      '${_money(e.amount)}（${_day(e.at)}${e.note.isEmpty ? '' : ' ${e.note}'}）';

  // ── 紀錄 ─────────────────────────────────────────────────

  Future<List<I88Entry>> entriesForUpload() =>
      _load(_entriesKey, I88Entry.fromJson);

  /// 給畫面用：已刪除的濾掉，新的在前面。
  Future<List<I88Entry>> loadEntries() async =>
      (await entriesForUpload()).where((e) => e.deletedAt == null).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  Future<I88Entry> add({
    required DateTime at,
    required int amount,
    String note = '',
  }) async {
    final e = I88Entry(
      id: i88Id(),
      at: at,
      amount: amount,
      note: note,
      updatedAt: DateTime.now(),
    );
    await _save(_entriesKey, [
      ...await entriesForUpload(),
      e,
    ], (x) => x.toJson());
    await _log('新增', describe(e), refId: e.id);
    return e;
  }

  Future<void> update(I88Entry e) async {
    final all = await entriesForUpload();
    final i = all.indexWhere((x) => x.id == e.id);
    if (i < 0) return;
    final old = all[i];
    all[i] = e.copyWith(updatedAt: DateTime.now());
    await _save(_entriesKey, all, (x) => x.toJson());
    String note(String n) => n.isEmpty ? '（空）' : n;
    final diff = [
      if (old.amount != e.amount)
        '金額：${_money(old.amount)} → ${_money(e.amount)}',
      if (old.at != e.at) '日期時間：${_time(old.at)} → ${_time(e.at)}',
      if (old.note != e.note) '備註：${note(old.note)} → ${note(e.note)}',
    ];
    await _log('編輯', describe(e), detail: diff.join('\n'), refId: e.id);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now();
    final all = await entriesForUpload();
    final gone = all.where((e) => e.id == id).firstOrNull;
    await _save(_entriesKey, [
      for (final e in all)
        e.id == id ? e.copyWith(updatedAt: now, deletedAt: now) : e,
    ], (x) => x.toJson());
    if (gone != null) await _log('刪除', describe(gone), refId: id);
  }

  // ── 每月目標 ─────────────────────────────────────────────

  Future<List<I88Setting>> settingsForUpload() =>
      _load(_settingsKey, I88Setting.fromJson);

  Future<int?> loadTarget() async {
    for (final s in await settingsForUpload()) {
      if (s.id == targetId) return s.value;
    }
    return null;
  }

  Future<void> setTarget(int value) async {
    final old = await loadTarget();
    final rest = (await settingsForUpload()).where((s) => s.id != targetId);
    await _save(_settingsKey, [
      ...rest,
      I88Setting(id: targetId, value: value, updatedAt: DateTime.now()),
    ], (x) => x.toJson());
    await _log(
      '改目標',
      '每月目標 \$$value',
      detail: old == null ? '' : '\$$old → \$$value',
    );
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

  Future<int> mergeEntriesFromCloud(List<I88Entry> incoming) => _merge(
    _entriesKey,
    incoming,
    I88Entry.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    deletedAtOf: (e) => e.deletedAt,
  );

  Future<int> mergeSettingsFromCloud(List<I88Setting> incoming) => _merge(
    _settingsKey,
    incoming,
    I88Setting.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
  );

  /// 操作紀錄：兩邊直接聯集（照 id），不刪、不裁。
  Future<int> mergeLogFromCloud(List<I88LogEntry> incoming) => _merge(
    _logKey,
    incoming,
    I88LogEntry.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
  );
}
