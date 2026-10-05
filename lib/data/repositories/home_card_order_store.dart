import 'dart:convert';

import '../storage/key_value_store.dart';

/// 英文／日文首頁卡片的顯示順序（2026-10-05 使用者要求：每張卡片的順序
/// 可以自己調，像 YT 分類順序那樣，而且要能多裝置同步）。
///
/// 跟 [YtCategoryOrderRecord] 同一套「單一設定值＋updatedAt」：整份順序
/// 是一個值，兩台裝置不一樣時比 updatedAt，新的贏（同步見
/// `R2SyncService.syncHomeCardOrder`）。存的是卡片 id 的順序，不是卡片
/// 本身，所以之後新加卡片、或某張卡片被設定隱藏，都不會壞——見
/// [applyHomeCardOrder]。
class HomeCardOrderRecord {
  const HomeCardOrderRecord({required this.order, required this.updatedAt});

  final List<String> order;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'order': order,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory HomeCardOrderRecord.fromJson(Map<String, dynamic> json) =>
      HomeCardOrderRecord(
        order: (json['order'] as List).cast<String>(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// [track] 是 `en`（英文首頁）或 `jp`（日文首頁），兩邊各存一份、雲端
/// 也各一個檔，互不影響。
class HomeCardOrderStore {
  HomeCardOrderStore(this._store, this.track);

  final KeyValueStore _store;
  final String track;

  String get _key => 'home.card_order.$track.v1';

  /// 雲端上的檔名。
  String get cloudKey => 'home_card_order_$track.json';

  Future<List<String>?> load() async => (await loadRecord())?.order;

  Future<HomeCardOrderRecord?> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    return HomeCardOrderRecord.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> save(List<String> orderedIds) => saveRecord(
    HomeCardOrderRecord(order: orderedIds, updatedAt: DateTime.now()),
  );

  Future<void> saveRecord(HomeCardOrderRecord record) =>
      _store.write(_key, jsonEncode(record.toJson()));
}

/// 把存起來的順序套到這版 App 實際有的卡片上：先照 [saved] 排（不認得的
/// id 跳過，例如之後拿掉的卡片），再把 [defaults] 裡 [saved] 沒提到的卡片
/// 依預設順序接在後面（之後新加的卡片不會因為舊的順序裡沒有它就消失）。
/// 從沒排過（[saved] 是 null）就是 [defaults] 原樣。
List<String> applyHomeCardOrder(List<String> defaults, List<String>? saved) {
  if (saved == null) return defaults;
  final known = defaults.toSet();
  final ordered = [
    for (final id in saved)
      if (known.contains(id)) id,
  ];
  final seen = ordered.toSet();
  return [
    ...ordered,
    for (final id in defaults)
      if (!seen.contains(id)) id,
  ];
}
