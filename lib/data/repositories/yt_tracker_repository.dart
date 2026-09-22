import 'dart:convert';

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

  Future<List<YtCategory>> loadCategories() async {
    final raw = await _store.read(_categoryKey);
    if (raw == null) return <YtCategory>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtCategory.fromJson)
        .toList();
  }

  Future<void> _writeCategories(List<YtCategory> all) => _store.write(
    _categoryKey,
    jsonEncode([for (final c in all) c.toJson()]),
  );

  Future<void> addCategory(YtCategory category) async {
    final all = [...await loadCategories(), category];
    await _writeCategories(all);
  }

  Future<void> updateCategory(YtCategory category) async {
    final all = await loadCategories();
    final index = all.indexWhere((c) => c.id == category.id);
    if (index == -1) return;
    all[index] = category;
    await _writeCategories(all);
  }

  /// 刪除分類。底下的頻道不會被一起刪掉，改成「未分類」（[YtChannel.categoryId]
  /// 設為 null），使用者之後可以再重新分類。
  Future<void> deleteCategory(String id) async {
    final categories = await loadCategories()..removeWhere((c) => c.id == id);
    await _writeCategories(categories);

    final channels = await loadChannels();
    if (!channels.any((c) => c.categoryId == id)) return;
    final updated = [
      for (final c in channels)
        c.categoryId == id
            ? YtChannel(
                id: c.id,
                name: c.name,
                categoryId: null,
                avatarEmoji: c.avatarEmoji,
                avatarImageUrl: c.avatarImageUrl,
                url: c.url,
                addedAt: c.addedAt,
              )
            : c,
    ];
    await _writeChannels(updated);
  }

  Future<List<YtChannel>> loadChannels() async {
    final raw = await _store.read(_channelKey);
    if (raw == null) return <YtChannel>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtChannel.fromJson)
        .toList();
  }

  Future<void> _writeChannels(List<YtChannel> all) =>
      _store.write(_channelKey, jsonEncode([for (final c in all) c.toJson()]));

  Future<void> addChannel(YtChannel channel) async {
    final all = [...await loadChannels(), channel];
    await _writeChannels(all);
  }

  Future<void> updateChannel(YtChannel channel) async {
    final all = await loadChannels();
    final index = all.indexWhere((c) => c.id == channel.id);
    if (index == -1) return;
    all[index] = channel;
    await _writeChannels(all);
  }

  Future<void> deleteChannel(String id) async {
    final all = await loadChannels()..removeWhere((c) => c.id == id);
    await _writeChannels(all);
  }

  /// 把分類／頻道快照（見 [loadYtCategoriesSeed]／[loadYtChannelsSeed]）
  /// 併回本機，跟 [DiaryRepository.mergeSeed] 同一套邏輯（共用
  /// `seed_merge.dart` 的 [mergeSeedRecords]）。
  Future<void> mergeSeedCategories(List<YtCategory> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await loadCategories(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
    );
    await _writeCategories(merged);
  }

  Future<void> mergeSeedChannels(List<YtChannel> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await loadChannels(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
    );
    await _writeChannels(merged);
  }

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
