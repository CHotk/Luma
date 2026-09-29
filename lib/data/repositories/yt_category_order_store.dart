import 'dart:convert';

import '../storage/key_value_store.dart';

/// 使用者自己拖拉排出來的分類顯示順序（2026-09-29 使用者要求：YT 管理
/// 要能自己設定分類顯示順序，不要寫死）。存分類 id 的順序清單；沒設定
/// 過就是 null，[YtTrackerRepository.loadCategories] 退回原本「知識／
/// 學習／娛樂／影視／生活／幣圈」固定在前的預設順序。
///
/// 「看過但不喜歡」不在這份清單裡管——那個固定排最後是既有規則，不開放
/// 拖動，避免使用者不小心把它拖到前面又要另外處理。
class YtCategoryOrderStore {
  YtCategoryOrderStore(this._store);

  static const _key = 'yt_tracker.category_order.v1';

  final KeyValueStore _store;

  Future<List<String>?> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> save(List<String> orderedIds) =>
      _store.write(_key, jsonEncode(orderedIds));

  Future<void> clear() => _store.remove(_key);
}
