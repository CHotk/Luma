import 'dart:convert';

import '../storage/key_value_store.dart';

/// YouTube API 金鑰存 localStorage，帶效期 [validFor]，過了就自動失效
/// ——不是永久留著（2026-09-23 使用者決定：原本堅持只存記憶體、關分頁
/// 就消失，後來覺得每次重整都要重貼太麻煩，改成存本機但會自動失效，
/// 兩邊各退一步）。效期一開始是「隔天 00:00」，2026-09-24 使用者要求
/// 改成存一週，2026-11-13 使用者要求改成預設存三個月（90 天）。
///
/// 跟其他 repository 一樣包一層，不要讓畫面層直接戳 [KeyValueStore]。
class YtApiKeyStore {
  YtApiKeyStore(this._store);

  static const _key = 'yt_tracker.api_key.v1';

  /// 從存進去那一刻起算的有效時間。
  static const validFor = Duration(days: 90);

  /// 舊版（只存 expiresAt）當初的效期，用來推回存進去的時間。
  static const _oldValidFor = Duration(days: 7);

  final KeyValueStore _store;

  /// 讀金鑰。過期了就順便清掉、回傳 null——呼叫端不用自己再判斷一次
  /// 「這筆是不是已經過期了」。
  Future<String?> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    // 效期一律從「存進去的時間」＋現在的 [validFor] 算：效期改長之後，之前存的
    // 金鑰也跟著延長，不用重貼。舊格式沒有 savedAt，用當時一週的效期推回去。
    final savedAt = json['savedAt'] is String
        ? DateTime.parse(json['savedAt'] as String)
        : DateTime.parse(json['expiresAt'] as String).subtract(_oldValidFor);
    final expiresAt = savedAt.add(validFor);
    if (!DateTime.now().isBefore(expiresAt)) {
      await _store.remove(_key);
      return null;
    }
    return json['key'] as String;
  }

  /// 存金鑰，從現在起算 [validFor]（三個月）後失效。
  Future<void> save(String key) async {
    final now = DateTime.now();
    await _store.write(
      _key,
      jsonEncode({
        'key': key,
        'savedAt': now.toIso8601String(),
        'expiresAt': now.add(validFor).toIso8601String(),
      }),
    );
  }

  Future<void> clear() => _store.remove(_key);
}
