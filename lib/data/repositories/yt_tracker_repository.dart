import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;

import '../../domain/models/yt_tracker.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';

/// YT 頻道追蹤的分類／頻道管理。分類、頻道各存一份 JSON blob，跟
/// 其他功能同一套「整包讀出來、整包寫回去」的存法。
///
/// 影片資料（真的接了 YouTube Data API，見 `youtube_api_service.dart`）
/// 不算進這裡——那些是即時打 API 拿的，本來就不該存檔，這個
/// repository 只管分類／頻道這種需要留著的資料。
class YtTrackerRepository {
  YtTrackerRepository(this._store);

  static const _categoryKey = 'yt_tracker.categories.v1';
  static const _channelKey = 'yt_tracker.channels.v1';

  final KeyValueStore _store;

  /// 刪除是墓碑標記（soft delete），不是物理刪除——多裝置同步要靠它
  /// 才不會讓刪掉的東西被別台裝置復活（2026-09-24 加上同步，跟日記
  /// 同一套，見 [YtCategory.deletedAt]）。內部讀寫都走 `_loadXxxRaw`
  /// （含已刪除的），公開的 `loadCategories`／`loadChannels` 才把已刪除
  /// 的濾掉給 UI 用。
  Future<List<YtCategory>> _loadCategoriesRaw() async {
    final raw = await _store.read(_categoryKey);
    if (raw == null) return <YtCategory>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtCategory.fromJson)
        .toList();
  }

  Future<List<YtCategory>> loadCategories() async =>
      (await _loadCategoriesRaw()).where((c) => c.deletedAt == null).toList();

  Future<void> _writeCategories(List<YtCategory> all) => _store.write(
    _categoryKey,
    jsonEncode([for (final c in all) c.toJson()]),
  );

  Future<void> addCategory(YtCategory category) async {
    final all = [...await _loadCategoriesRaw(), category.stamped()];
    await _writeCategories(all);
  }

  Future<void> updateCategory(YtCategory category) async {
    final all = await _loadCategoriesRaw();
    final index = all.indexWhere((c) => c.id == category.id);
    if (index == -1) return;
    all[index] = category.stamped();
    await _writeCategories(all);
  }

  /// 刪除分類。底下的頻道不會被一起刪掉，改成「未分類」（[YtChannel.categoryId]
  /// 設為 null），使用者之後可以再重新分類。
  Future<void> deleteCategory(String id) async {
    final categories = await _loadCategoriesRaw();
    final index = categories.indexWhere((c) => c.id == id);
    if (index != -1) {
      categories[index] = categories[index].stamped(deleted: true);
      await _writeCategories(categories);
    }

    final channels = await _loadChannelsRaw();
    if (!channels.any((c) => c.categoryId == id)) return;
    await _writeChannels([
      for (final c in channels) c.categoryId == id ? c.withoutCategory() : c,
    ]);
  }

  Future<List<YtChannel>> _loadChannelsRaw() async {
    final raw = await _store.read(_channelKey);
    if (raw == null) return <YtChannel>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtChannel.fromJson)
        .toList();
  }

  Future<List<YtChannel>> loadChannels() async =>
      (await _loadChannelsRaw()).where((c) => c.deletedAt == null).toList();

  Future<void> _writeChannels(List<YtChannel> all) =>
      _store.write(_channelKey, jsonEncode([for (final c in all) c.toJson()]));

  Future<void> addChannel(YtChannel channel) async {
    final all = [...await _loadChannelsRaw(), channel.stamped()];
    await _writeChannels(all);
  }

  Future<void> updateChannel(YtChannel channel) async {
    final all = await _loadChannelsRaw();
    final index = all.indexWhere((c) => c.id == channel.id);
    if (index == -1) return;
    all[index] = channel.stamped();
    await _writeChannels(all);
  }

  Future<void> deleteChannel(String id) async {
    final all = await _loadChannelsRaw();
    final index = all.indexWhere((c) => c.id == id);
    if (index == -1) return;
    all[index] = all[index].stamped(deleted: true);
    await _writeChannels(all);
  }

  /// 把分類／頻道快照（見 [loadYtCategoriesSeed]／[loadYtChannelsSeed]）
  /// 併回本機，跟 [DiaryRepository.mergeSeed] 同一套邏輯（共用
  /// `seed_merge.dart` 的 [mergeSeedRecords]）。
  Future<void> mergeSeedCategories(List<YtCategory> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await _loadCategoriesRaw(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
      deletedAtOf: (e) => e.deletedAt,
    );
    await _writeCategories(merged);
  }

  Future<void> mergeSeedChannels(List<YtChannel> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await _loadChannelsRaw(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
      deletedAtOf: (e) => e.deletedAt,
    );
    await _writeChannels(merged);
  }

  /// 把 R2 雲端抓下來的分類／頻道併回本機（本機贏、刪除永遠贏、其餘比
  /// updatedAt 新舊，同 [DiaryRepository.mergeFromCloud]），回傳實際異動
  /// 幾筆。
  Future<int> mergeCategoriesFromCloud(List<YtCategory> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadCategoriesRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.syncedAt,
    );
    await _writeCategories(merged);
    return ytDiffCount(
      [for (final c in before) c.toJson()],
      [for (final c in merged) c.toJson()],
    );
  }

  Future<int> mergeChannelsFromCloud(List<YtChannel> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadChannelsRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.syncedAt,
    );
    await _writeChannels(merged);
    return ytDiffCount(
      [for (final c in before) c.toJson()],
      [for (final c in merged) c.toJson()],
    );
  }

  /// 給同步用——連刪除標記都要有。
  Future<List<YtCategory>> categoriesForUpload() => _loadCategoriesRaw();
  Future<List<YtChannel>> channelsForUpload() => _loadChannelsRaw();

  /// 匯出分類＋頻道給使用者存成真正的檔案，手動搬進 git 版控的
  /// `assets/data/yt_tracker_categories.json`／`yt_tracker_channels.json`，
  /// 跟其他功能的匯出同一個用途——手機跟電腦各自管理的分類/頻道存在
  /// 各自瀏覽器的 localStorage，不會自動合併，只能靠使用者手動搬。
  Future<({String text, int categoryCount, int channelCount})>
  exportJson() async {
    final categories = await loadCategories();
    final channels = await loadChannels();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert({
        'categories': [for (final c in categories) c.toJson()],
        'channels': [for (final c in channels) c.toJson()],
      }),
      categoryCount: categories.length,
      channelCount: channels.length,
    );
  }
}

/// 兩份 JSON 清單比對，新增或內容有變的算一筆（同
/// `diaryDiffCount` 的邏輯，用 `id` 對應）。
int ytDiffCount(
  List<Map<String, dynamic>> before,
  List<Map<String, dynamic>> after,
) {
  final beforeById = {for (final e in before) e['id']: e};
  var changed = 0;
  for (final e in after) {
    final prior = beforeById[e['id']];
    if (prior == null || !mapEquals(prior, e)) changed++;
  }
  return changed;
}
