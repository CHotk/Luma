import 'dart:convert';
import 'dart:math';

import '../../domain/models/tally.dart';
import '../export/device_label.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 簡單記帳的存檔（2026-10-19）：帳本、每一筆、異動紀錄各一個清單，整包
/// JSON 讀寫；帳本跟每一筆刪除用墓碑標記（照 id 合併、比 updatedAt、刪除
/// 永遠贏），異動紀錄只增不刪，跨裝置聯集。獨立一份，不跟其他記錄共用。
class TallyRepository {
  TallyRepository(this._store);

  static const booksKey = 'tally.books.v1';
  static const itemsKey = 'tally.items.v1';
  static const eventsKey = 'tally.events.v1';

  final KeyValueStore _store;
  static final _rng = Random.secure();

  /// 測試換掉用；正式是瀏覽器／系統標籤。
  static String Function() deviceLabel = currentDeviceLabel;

  static String newId() =>
      List.generate(32, (_) => _rng.nextInt(16).toRadixString(16)).join();

  Future<List<T>> _read<T>(
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

  Future<void> _write<T>(
    String key,
    List<T> all,
    Map<String, dynamic> Function(T) toJson,
  ) => _store.write(key, jsonEncode([for (final e in all) toJson(e)]));

  // ── 給同步用：連刪除標記都要看得到 ──────────────────────────
  Future<List<TallyBook>> booksForUpload() =>
      _read(booksKey, TallyBook.fromJson);
  Future<List<TallyItem>> itemsForUpload() =>
      _read(itemsKey, TallyItem.fromJson);
  Future<List<TallyEvent>> eventsForUpload() =>
      _read(eventsKey, TallyEvent.fromJson);

  // ── 給畫面用 ──────────────────────────────────────────────
  Future<List<TallyBook>> books() async =>
      (await booksForUpload()).where((b) => b.deletedAt == null).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// 一個帳本的每一筆，舊的在前（算累計結餘用）。
  Future<List<TallyItem>> items([String? bookId]) async =>
      (await itemsForUpload())
          .where(
            (i) =>
                i.deletedAt == null && (bookId == null || i.bookId == bookId),
          )
          .toList()
        ..sort((a, b) {
          final c = a.at.compareTo(b.at);
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });

  /// 異動紀錄，新的在前。
  Future<List<TallyEvent>> events([String? bookId]) async =>
      (await eventsForUpload())
          .where((e) => bookId == null || e.bookId == bookId)
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  /// 一個帳本現在的結餘（＋ 減 −）。
  Future<int> balance(String bookId) async {
    var sum = 0;
    for (final i in await items(bookId)) {
      sum += i.signed;
    }
    return sum;
  }

  Future<String> _bookName(String bookId) async =>
      (await booksForUpload()).where((b) => b.id == bookId).firstOrNull?.name ??
      '';

  Future<void> _log(
    TallyAction action,
    String bookId,
    String text, {
    String? bookName,
    String? itemId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    int? balanceBefore,
    int? balanceAfter,
    Map<String, dynamic>? extra,
  }) async {
    final all = await eventsForUpload();
    all.add(
      TallyEvent(
        id: newId(),
        at: DateTime.now(),
        action: action,
        bookId: bookId,
        bookName: bookName ?? await _bookName(bookId),
        text: text,
        device: deviceLabel(),
        itemId: itemId,
        before: before,
        after: after,
        balanceBefore: balanceBefore,
        balanceAfter: balanceAfter,
        extra: extra,
      ),
    );
    await _write(eventsKey, all, (e) => e.toJson());
  }

  Future<void> _putBook(TallyBook b) async {
    final all = await booksForUpload();
    final i = all.indexWhere((x) => x.id == b.id);
    i < 0 ? all.add(b) : all[i] = b;
    await _write(booksKey, all, (e) => e.toJson());
  }

  Future<void> _putItem(TallyItem it) async {
    final all = await itemsForUpload();
    final i = all.indexWhere((x) => x.id == it.id);
    i < 0 ? all.add(it) : all[i] = it;
    await _write(itemsKey, all, (e) => e.toJson());
  }

  Future<TallyBook> addBook(String name) async {
    final now = DateTime.now();
    final b = TallyBook(
      id: newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await _putBook(b);
    await _log(TallyAction.bookCreate, b.id, '新增帳本「$name」', after: b.toJson());
    return b;
  }

  Future<void> renameBook(TallyBook b, String name) async {
    if (name == b.name) return;
    final nb = b.copyWith(name: name, updatedAt: DateTime.now());
    await _putBook(nb);
    await _log(
      TallyAction.bookRename,
      b.id,
      '帳本改名：「${b.name}」→「$name」',
      before: b.toJson(),
      after: nb.toJson(),
    );
  }

  Future<void> deleteBook(TallyBook b) async {
    final now = DateTime.now();
    final bal = await balance(b.id);
    final nb = b.copyWith(updatedAt: now, deletedAt: now);
    await _putBook(nb);
    await _log(
      TallyAction.bookDelete,
      b.id,
      '刪除帳本「${b.name}」（當時結餘 ${tallySigned(bal)}）',
      before: b.toJson(),
      after: nb.toJson(),
      balanceBefore: bal,
      balanceAfter: bal,
    );
  }

  Future<TallyItem> addItem({
    required String bookId,
    required bool plus,
    required int amount,
    required String note,
    required DateTime at,
  }) async {
    final now = DateTime.now();
    final it = TallyItem(
      id: newId(),
      bookId: bookId,
      plus: plus,
      amount: amount,
      note: note,
      at: at,
      createdAt: now,
      updatedAt: now,
    );
    final bal = await balance(bookId);
    await _putItem(it);
    await _log(
      TallyAction.itemCreate,
      bookId,
      '新增 ${tallyItemLabel(it)}',
      itemId: it.id,
      after: it.toJson(),
      balanceBefore: bal,
      balanceAfter: bal + it.signed,
    );
    return it;
  }

  Future<void> editItem(
    TallyItem old, {
    required bool plus,
    required int amount,
    required String note,
    required DateTime at,
  }) async {
    final it = old.copyWith(
      plus: plus,
      amount: amount,
      note: note,
      at: at,
      updatedAt: DateTime.now(),
    );
    if (old.plus == plus &&
        old.amount == amount &&
        old.note == note &&
        old.at == at) {
      return;
    }
    final bal = await balance(old.bookId);
    await _putItem(it);
    await _log(
      TallyAction.itemUpdate,
      old.bookId,
      '修改 ${tallyItemLabel(old)} → ${tallyItemLabel(it)}',
      itemId: it.id,
      before: old.toJson(),
      after: it.toJson(),
      balanceBefore: bal,
      balanceAfter: bal - old.signed + it.signed,
    );
  }

  Future<void> deleteItem(TallyItem it) async {
    final now = DateTime.now();
    final bal = await balance(it.bookId);
    final dead = it.copyWith(updatedAt: now, deletedAt: now);
    await _putItem(dead);
    await _log(
      TallyAction.itemDelete,
      it.bookId,
      '刪除 ${tallyItemLabel(it)}',
      itemId: it.id,
      before: it.toJson(),
      after: dead.toJson(),
      balanceBefore: bal,
      balanceAfter: bal - it.signed,
    );
  }

  /// 匯出 PDF 也記一筆（2026-10-19 使用者要求）：檔名、圖上有幾筆、當時結餘、
  /// 怎麼存的（分享／下載）、有沒有成功。
  Future<void> logExport(
    String bookId, {
    required String filename,
    required int itemCount,
    required int balance,
    required bool ok,
    int? pages,
    String? error,
  }) => _log(
    TallyAction.exportPdf,
    bookId,
    ok
        ? '匯出 PDF $filename（$itemCount 筆，結餘 ${tallySigned(balance)}）'
        : '匯出 PDF 失敗：${error ?? '這個裝置不能存檔'}',
    balanceBefore: balance,
    balanceAfter: balance,
    extra: {
      'filename': filename,
      'itemCount': itemCount,
      'pages': ?pages,
      'ok': ok,
      'error': ?error,
    },
  );

  // ── 把 R2 雲端抓下來的併回本機，回傳實際異動幾筆 ─────────────
  Future<int> _merge<T>(
    String key,
    List<T> incoming,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson,
    String Function(T) idOf,
    DateTime? Function(T) deletedAtOf,
    DateTime Function(T) updatedAtOf,
  ) async {
    if (incoming.isEmpty) return 0;
    final before = await _read(key, fromJson);
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: idOf,
      priority: SeedMergePriority.local,
      deletedAtOf: deletedAtOf,
      updatedAtOf: updatedAtOf,
    );
    await _write(key, merged, toJson);
    return ytDiffCount(
      [for (final e in before) toJson(e)],
      [for (final e in merged) toJson(e)],
    );
  }

  Future<int> mergeBooksFromCloud(List<TallyBook> incoming) => _merge(
    booksKey,
    incoming,
    TallyBook.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.deletedAt,
    (e) => e.updatedAt,
  );

  Future<int> mergeItemsFromCloud(List<TallyItem> incoming) => _merge(
    itemsKey,
    incoming,
    TallyItem.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.deletedAt,
    (e) => e.updatedAt,
  );

  /// 異動紀錄只增不改，照 id 聯集。
  Future<int> mergeEventsFromCloud(List<TallyEvent> incoming) => _merge(
    eventsKey,
    incoming,
    TallyEvent.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (_) => null,
    (e) => e.at,
  );
}
