import 'dart:convert';

import '../storage/key_value_store.dart';

/// 使用者往左滑影片列選「隱藏」的影片 id 集合（2026-09-30 使用者要求：
/// 不想看到的影片可以滑掉隱藏，不是刪除——影片本身是即時打 API 抓的，
/// 沒有「刪除」這個概念，隱藏純粹是「這台裝置不想再看到它」的個人
/// 標記）。跟 `yt_video_watch_store.dart`（記錄看過沒）是兩個獨立概念，
/// 分開存：一支影片可以看過但沒隱藏、也可以隱藏但沒點開過。
class YtVideoHiddenStore {
  YtVideoHiddenStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_hidden.v1';

  Future<Set<String>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<bool> contains(String videoId) async =>
      (await loadAll()).contains(videoId);

  Future<void> hide(String videoId) async {
    final all = await loadAll();
    if (!all.add(videoId)) return;
    await _store.write(_key, jsonEncode(all.toList()));
  }

  Future<void> unhide(String videoId) async {
    final all = await loadAll();
    if (!all.remove(videoId)) return;
    await _store.write(_key, jsonEncode(all.toList()));
  }

  /// 多裝置同步用：跟雲端的集合做聯集（隱藏是「只增」的個人偏好，
  /// 不會自動取消，要取消得使用者自己按還原——目前還沒有還原入口，
  /// 先做聯集合併，跟其他「只增」清單同一套邏輯）。
  Future<int> mergeFromCloud(Set<String> cloud) async {
    if (cloud.isEmpty) return 0;
    final local = await loadAll();
    final fresh = cloud.difference(local);
    if (fresh.isEmpty) return 0;
    await _store.write(_key, jsonEncode({...local, ...fresh}.toList()));
    return fresh.length;
  }
}
