// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: uri_does_not_exist
import 'dart:indexed_db' as idb;

import 'key_value_store.dart';

/// 網頁版的儲存後端：IndexedDB。
///
/// 原本用 shared_preferences，網頁上底層是 localStorage，整個網域只有
/// 約 5MB。多裝置同步之後，五十音練習的筆畫、YT 影片快取、雲端抓回來的
/// 紀錄都要存本機，手機上很快就爆 `QuotaExceededError`、同步失敗
/// （2026-09-24 使用者回報）。IndexedDB 的容量是磁碟等級的，量級差很多。
///
/// 做法：啟動時把整個 object store 讀進記憶體（讀取維持同步速度，跟
/// 原本「整包讀寫」的使用方式一樣），寫入時同時寫記憶體跟 IndexedDB。
///
/// 已經**拿掉**舊的 localStorage 搬家跟「IndexedDB 開不起來就退回
/// localStorage」的備援（2026-09-24 使用者要求：資料都在雲端、不怕
/// 沒搬到，也不需要備援）。IndexedDB 開不起來就直接丟例外。
Future<KeyValueStore> openPlatformStore() => _IndexedDbStore.open();

class _IndexedDbStore implements KeyValueStore {
  _IndexedDbStore._(this._db, this._cache);

  static const _dbName = 'lume';
  static const _storeName = 'kv';

  final idb.Database _db;
  final Map<String, String> _cache;

  static Future<_IndexedDbStore> open() async {
    final factory = html.window.indexedDB;
    if (factory == null) throw StateError('IndexedDB unavailable');
    final db = await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (e) {
        final request = e.target as idb.Request;
        (request.result as idb.Database).createObjectStore(_storeName);
      },
    );
    final cache = <String, String>{};
    final txn = db.transaction(_storeName, 'readonly');
    final cursors = txn.objectStore(_storeName).openCursor(autoAdvance: true);
    await for (final cursor in cursors) {
      final value = cursor.value;
      if (value is String) cache[cursor.key as String] = value;
    }
    await txn.completed;
    return _IndexedDbStore._(db, cache);
  }

  Future<void> _put(String key, String value) async {
    final txn = _db.transaction(_storeName, 'readwrite');
    txn.objectStore(_storeName).put(value, key);
    await txn.completed;
  }

  @override
  Future<String?> read(String key) async => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    await _put(key, value);
    _cache[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    final txn = _db.transaction(_storeName, 'readwrite');
    txn.objectStore(_storeName).delete(key);
    await txn.completed;
    _cache.remove(key);
  }
}
