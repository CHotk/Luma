import 'dart:convert';

import '../storage/key_value_store.dart';

/// YouTube API 金鑰現在存 localStorage，但帶「隔天 00:00 就過期」的
/// 效期——不是永久留著（2026-09-23 使用者決定：原本堅持只存記憶體、
/// 關分頁就消失，後來覺得每次重整都要重貼太麻煩，改成存本機但每天
/// 都會自動失效，兩邊各退一步：不用一直重貼，但也不會無限期留著）。
///
/// 跟其他 repository 一樣包一層，不要讓畫面層直接戳 [KeyValueStore]。
class YtApiKeyStore {
  YtApiKeyStore(this._store);

  static const _key = 'yt_tracker.api_key.v1';

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

  /// 存金鑰，效期算到「明天 00:00」——不管現在幾點存的，最晚活到明天
  /// 凌晨，不是存進去那一刻起算滿 24 小時（2026-09-23 使用者原話：
  /// 「只存24h 超過00:00就銷毀」，取的是「過了 00:00 這個時間點」，
  /// 不是「滿 24 小時」這個時長）。
  Future<void> save(String key) async {
    final now = DateTime.now();
    final expiresAt = DateTime(now.year, now.month, now.day + 1);
    await _store.write(
      _key,
      jsonEncode({'key': key, 'expiresAt': expiresAt.toIso8601String()}),
    );
  }

  Future<void> clear() => _store.remove(_key);
}
