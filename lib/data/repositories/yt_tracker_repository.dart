import 'dart:convert';

import '../../domain/models/yt_tracker.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_category_order_store.dart';

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

  /// 指定幾個分類固定排在最前面（2026-09-29 使用者要求：知識、學習、
  /// 娛樂、影視、幣圈依序放最前面，其餘分類維持原順序接在後面），
  /// 「看過但不喜歡」固定排最後一個（2026-09-24 使用者要求）。
  static const _pinnedFirst = [
    'seed-knowledge',
    'seed-learning',
    'seed-entertainment',
    'seed-film',
    'seed-life',
    'seed-crypto',
  ];

  Future<List<YtCategory>> loadCategories() async {
    final all = (await _loadCategoriesRaw())
        .where((c) => c.deletedAt == null)
        .toList();
    final byId = {for (final c in all) c.id: c};
    final disliked = all.where((c) => c.id == ytDislikedCategoryId);

    // 使用者自己拖拉排過的順序優先（2026-09-29 使用者要求：YT 管理要能
    // 自己設定分類顯示順序），沒設定過才退回舊的寫死 pinned-first 預設。
    // 「看過但不喜歡」不在自訂順序管的範圍內，一律固定排最後。
    final customOrder = await YtCategoryOrderStore(_store).load();
    if (customOrder != null) {
      final ordered = [
        for (final id in customOrder)
          if (byId[id] != null && id != ytDislikedCategoryId) byId[id]!,
      ];
      final orderedIds = ordered.map((c) => c.id).toSet();
      // 自訂順序存下來之後才新增的分類，不在那份清單裡，接在後面，
      // 不會消失不見。
      final missing = all.where(
        (c) => c.id != ytDislikedCategoryId && !orderedIds.contains(c.id),
      );
      return [...ordered, ...missing, ...disliked];
    }

    final rest = all.where(
      (c) => !_pinnedFirst.contains(c.id) && c.id != ytDislikedCategoryId,
    );
    return [
      for (final id in _pinnedFirst)
        if (byId[id] != null) byId[id]!,
      ...rest,
      ...disliked,
    ];
  }

  Future<void> _writeCategories(List<YtCategory> all) =>
      _store.write(_categoryKey, jsonEncode([for (final c in all) c.toJson()]));

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

  /// 刪除分類。底下的頻道不會被一起刪掉，預設改成「未分類」
  /// （[YtChannel.categoryId] 設為 null），使用者之後可以再重新分類。
  ///
  /// [moveChannelsTo] 選填：指定的話頻道改搬去那個分類，不是變未分類
  /// ——例如合併兩個重複的分類，刪掉其中一個時把底下頻道直接搬到留著
  /// 的那個（2026-09-29 使用者要求）。呼叫端要自己保證這個 id 是還存在
  /// 的分類，這裡不驗證。
  Future<void> deleteCategory(String id, {String? moveChannelsTo}) async {
    final categories = await _loadCategoriesRaw();
    final index = categories.indexWhere((c) => c.id == id);
    if (index != -1) {
      categories[index] = categories[index].stamped(deleted: true);
      await _writeCategories(categories);
    }

    final channels = await _loadChannelsRaw();
    if (!channels.any((c) => c.categoryId == id)) return;
    await _writeChannels([
      for (final c in channels)
        c.categoryId == id ? c.copyWith(categoryId: moveChannelsTo) : c,
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

  /// 一次更新一批頻道（例如訂閱人數更新），只寫一次儲存。
  /// 一次更新一批頻道，目前只有背景訂閱人數更新在用這個。**故意不蓋
  /// `updatedAt`**——這是自動背景更新，不是使用者自己的操作，不該在
  /// 多裝置合併時贏過使用者在別台裝置做的置頂／搬分類／改名這些真正
  /// 的編輯（2026-09-30 使用者回報：A 裝置置頂＋調分類順序、同步，換 B
  /// 裝置同步卻沒看到——根因就是背景訂閱數更新把 `updatedAt` 蓋成
  /// 更新的時間，讓「只是剛好問過一次訂閱數」的那台裝置在合併時贏過
  /// 「真的做了操作」的那台，見 [YtCategoryOrderStore] 也補了同步）。
  Future<void> updateChannels(List<YtChannel> updated) async {
    if (updated.isEmpty) return;
    final all = await _loadChannelsRaw();
    final byId = {for (final c in updated) c.id: c};
    await _writeChannels([for (final c in all) byId[c.id] ?? c]);
  }

  Future<void> deleteChannel(String id) async {
    final all = await _loadChannelsRaw();
    final index = all.indexWhere((c) => c.id == id);
    if (index == -1) return;
    all[index] = all[index].stamped(deleted: true);
    await _writeChannels(all);
  }

  /// 垃圾桶列表用：只看已刪除（墓碑標記）的頻道（2026-09-29 使用者要求）。
  Future<List<YtChannel>> loadDeletedChannels() async =>
      (await _loadChannelsRaw()).where((c) => c.deletedAt != null).toList();

  /// 從垃圾桶還原：清掉墓碑標記，頻道恢復成原本的分類（分類如果也被刪掉
  /// 了，會退回未分類，跟 [withoutCategory] 那套邏輯是分開兩回事，這裡
  /// 不特別處理分類是否還存在，交給讀取端自然當成未分類顯示）。
  Future<void> restoreChannel(String id) async {
    final all = await _loadChannelsRaw();
    final index = all.indexWhere((c) => c.id == id);
    if (index == -1) return;
    all[index] = all[index].restored();
    await _writeChannels(all);
  }

  /// 從垃圾桶「永久刪除」：真的從本機清單移除，不是墓碑標記
  /// （2026-09-29 使用者要求）。**注意**：這只保證這台裝置看不到了——
  /// 如果雲端還留著這筆的墓碑、且還有別台裝置沒同步過這次清除，下次
  /// 同步合併時雲端那份還是會補回來（一樣是已刪除狀態，不會變回啟用，
  /// 只是又會出現在垃圾桶列表）。先同步過一輪讓所有裝置都知道刪除了，
  /// 再永久清除，比較不會遇到這個情況。
  Future<void> purgeChannel(String id) async {
    final all = await _loadChannelsRaw();
    all.removeWhere((c) => c.id == id);
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
    final before = await _loadChannelsRaw();
    final priorById = {for (final c in before) c.id: c};
    final seedMerged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
      deletedAtOf: (e) => e.deletedAt,
    );
    // 快照只帶基本資料；本機已經解析好的頻道 ID／上傳清單 ID／訂閱人數
    // 不能被快照蓋回空的，不然每次進首頁都要重新問 API（原本就會有這個
    // 問題，加訂閱人數後更明顯）。置頂時間也一樣要保留——快照本來就永遠
    // 不會有這欄，seed 優先合併的結果一定是 null，沒有這行patch的話，
    // 只要頻道剛好也是內建快照裡有的（大部分頻道都是），置頂完一進首頁
    // 觸發這個合併就會立刻被洗回沒置頂，看起來像「置頂沒有同步」，其實
    // 是本機自己把它抹掉了（2026-09-30 使用者回報抓到）。
    final merged = [
      for (final c in seedMerged)
        () {
          final prior = priorById[c.id];
          if (prior == null) return c;
          return c.copyWith(
            youtubeChannelId: c.youtubeChannelId.isEmpty
                ? prior.youtubeChannelId
                : null,
            uploadsPlaylistId: c.uploadsPlaylistId.isEmpty
                ? prior.uploadsPlaylistId
                : null,
            subscriberCount: c.subscriberCount ?? prior.subscriberCount,
            subscribersHidden: c.statsUpdatedAt == null
                ? prior.subscribersHidden
                : null,
            statsUpdatedAt: c.statsUpdatedAt ?? prior.statsUpdatedAt,
            pinnedAt: c.pinnedAt ?? prior.pinnedAt,
          );
        }(),
    ];
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
  // 不能用 mapEquals：它只比一層，筆畫座標之類巢狀清單每次都是新物件、
  // 永遠「不相等」，會讓沒動過的紀錄每次同步都算成上傳／下載 217 筆
  // （2026-09-24 使用者回報）。改比 JSON 字串。
  final beforeById = {for (final e in before) e['id']: jsonEncode(e)};
  var changed = 0;
  for (final e in after) {
    final prior = beforeById[e['id']];
    if (prior == null || prior != jsonEncode(e)) changed++;
  }
  return changed;
}
