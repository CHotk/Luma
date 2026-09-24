import 'dart:convert';

import '../storage/key_value_store.dart';

/// YouTube API 金鑰存 localStorage，帶效期 [validFor]，過了就自動失效
/// ——不是永久留著（2026-09-23 使用者決定：原本堅持只存記憶體、關分頁
/// 就消失，後來覺得每次重整都要重貼太麻煩，改成存本機但會自動失效，
/// 兩邊各退一步）。效期一開始是「隔天 00:00」，2026-09-24 使用者要求
/// 改成存一週。
///
/// 跟其他 repository 一樣包一層，不要讓畫面層直接戳 [KeyValueStore]。
class YtApiKeyStore {
  YtApiKeyStore(this._store);

  static const _key = 'yt_tracker.api_key.v1';

  /// 從存進去那一刻起算的有效時間。
  static const validFor = Duration(days: 7);

  final KeyValueStore _store;

  /// 讀金鑰。過期了就順便清掉、回傳 null——呼叫端不用自己再判斷一次
  /// 「這筆是不是已經過期了」。
  Future<String?> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final expiresAt = DateTime.parse(json['expiresAt'] as String);
    if (!DateTime.now().isBefore(expiresAt)) {
      await _store.remove(_key);
      return null;
    }
    return json['key'] as String;
  }

  /// 存金鑰，從現在起算 [validFor]（一週）後失效。
  Future<void> save(String key) async {
    final expiresAt = DateTime.now().add(validFor);
    await _store.write(
      _key,
      jsonEncode({'key': key, 'expiresAt': expiresAt.toIso8601String()}),
    );
  }

  Future<void> clear() => _store.remove(_key);
}
