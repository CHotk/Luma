import 'dart:convert';

import '../storage/key_value_store.dart';

/// 使用者自己拖拉排出來的分類顯示順序（2026-09-29 使用者要求：YT 管理
/// 要能自己設定分類顯示順序，不要寫死）。存分類 id 的順序清單；沒設定
/// 過就是 null，[YtTrackerRepository.loadCategories] 退回原本「知識／
/// 學習／娛樂／影視／生活／幣圈」固定在前的預設順序。
///
/// 「看過但不喜歡」不在這份清單裡管——那個固定排最後是既有規則，不開放
/// 拖動，避免使用者不小心把它拖到前面又要另外處理。
///
/// 帶 `updatedAt` 的單一設定值（2026-09-30 使用者要求補上多裝置同步：
/// A 裝置調完順序、B 裝置同步卻看不到，就是因為原本這個 store 只存本機
/// 沒有時間戳，沒辦法跟雲端比新舊）——跟 `diary_password_store.dart` 的
/// [DiaryPasswordRecord] 同一套「單一設定值＋比 updatedAt 新舊」做法，
/// 不是清單型紀錄沒辦法用聯集合併。
class YtCategoryOrderRecord {
  const YtCategoryOrderRecord({required this.order, required this.updatedAt});

  final List<String> order;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'order': order,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory YtCategoryOrderRecord.fromJson(Map<String, dynamic> json) =>
      YtCategoryOrderRecord(
        order: (json['order'] as List).cast<String>(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class YtCategoryOrderStore {
  YtCategoryOrderStore(this._store);

  static const _key = 'yt_tracker.category_order.v1';

  final KeyValueStore _store;

  Future<List<String>?> load() async => (await loadRecord())?.order;

  Future<YtCategoryOrderRecord?> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    return YtCategoryOrderRecord.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> save(List<String> orderedIds) => saveRecord(
    YtCategoryOrderRecord(order: orderedIds, updatedAt: DateTime.now()),
  );

  Future<void> saveRecord(YtCategoryOrderRecord record) =>
      _store.write(_key, jsonEncode(record.toJson()));

  Future<void> clear() => _store.remove(_key);
}
