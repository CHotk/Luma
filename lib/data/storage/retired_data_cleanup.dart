import 'key_value_store.dart';

/// 已經移除的功能留在本機的資料，開機時清掉。
///
/// 看盤次數（`crypto_watch.*`）2026-10-10 整個移除，使用者接著要求舊資料
/// 也要刪。每台裝置的資料在自己的瀏覽器儲存空間裡，只能由 App 開起來時
/// 自己刪；雲端那份在同步時刪（見 `R2SyncService.deleteRetiredCloudFiles`）。
const _retiredPrefixes = ['crypto_watch.'];

/// 列不出全部 key 的儲存後端也要刪得到，所以已知的 key 另外直接點名。
const _retiredKeys = [
  'crypto_watch.entries.v1',
  'r2_sync.meta.crypto_watch.json',
];

/// 刪掉已移除功能的本機資料，回傳刪了幾個 key（沒有就是 0，可以重複呼叫）。
Future<int> removeRetiredLocalData(KeyValueStore store) async {
  final keys = <String>{};
  for (final k in _retiredKeys) {
    if (await store.read(k) != null) keys.add(k);
  }
  if (store is ListableKeyValueStore) {
    for (final k in (await store.readAll()).keys) {
      if (_retiredPrefixes.any(k.startsWith)) keys.add(k);
    }
  }
  for (final k in keys) {
    await store.remove(k);
  }
  return keys.length;
}
