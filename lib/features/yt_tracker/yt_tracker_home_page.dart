import 'dart:convert' show utf8, JsonEncoder;
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/notifications/test_notification_action.dart';
import '../../data/repositories/yt_tracker_repository.dart';
import '../../data/services/channel_discovery_service.dart';
import '../../data/seed/seed_merge.dart';
import '../../data/seed/yt_tracker_seed_loader.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/text/zh_normalize.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';

/// YT 頻道追蹤首頁：分類資料夾格子（設計稿 06/07/08 定案，見
/// `design-history/Yt頻道訂閱管理/`）。
///
/// 這是「管理」導向的功能，不是「看動態牆」——使用者原話：訂閱太多人、
/// 不是為了照 YouTube 那樣逛訂閱的人，是想先分類、想不知道看誰的時候
/// 能照分類找。所以首頁不是影片清單，是分類資料夾（2026-09-22 使用者
/// 要求）。「依影片顯示」真的接了 YouTube Data API（2026-09-22），但
/// 金鑰存本機一週，不進 Git，沒金鑰時在需要它的頁面點按鈕才會跳輸入
/// 視窗（見 `yt_api_key_dialog.dart`），不會一進首頁就跳。
class YtTrackerHomePage extends ConsumerStatefulWidget {
  const YtTrackerHomePage({super.key});

  @override
  ConsumerState<YtTrackerHomePage> createState() => _YtTrackerHomePageState();
}

class _YtTrackerHomePageState extends ConsumerState<YtTrackerHomePage> {
  late Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _future;

  /// 搜尋框（2026-09-24 使用者要求：放在「全部」上面，直接搜尋頻道）。
  /// 有輸入文字時，分類格子換成符合的頻道清單。
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
    // 不再一進頁面就自動跳金鑰輸入視窗（2026-09-24 使用者要求：手機一進來
    // 就跳出貼上選項很煩、而且貼了也沒真的貼進去，先拿掉）。需要金鑰的
    // 「依影片顯示」跟頻道詳情頁，沒金鑰時自己會顯示「設定 API 金鑰」按鈕。
  }

  /// 打開這頁那一瞬間先把分類／頻道快照（見 `yt_tracker_seed_loader.dart`）
  /// 併回本機，跟 `diary_page.dart` 的 `_loadWithSeedMerge` 同一套。
  Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final categorySeed = await loadYtCategoriesSeed();
    if (categorySeed.isNotEmpty) await repo.mergeSeedCategories(categorySeed);
    final channelSeed = await loadYtChannelsSeed();
    if (channelSeed.isNotEmpty) await repo.mergeSeedChannels(channelSeed);
    final categories = await repo.loadCategories();
    final channels = await repo.loadChannels();
    return (categories: categories, channels: channels);
  }

  void _reload() => setState(() => _future = _load());

  bool _digging = false;

  /// 挖掘前的選項（2026-09-24 使用者要求）：App 內分類可複選（不選＝全部）、
  /// 更多熱門主題（不限 App 內有的分類）可複選、自訂關鍵字、要不要參考
  /// App 內頻道的推薦。取消回傳 null。
  Future<({Set<String> categoryIds, List<String> keywords, bool useSeeds})?>
  _showDigOptions(List<YtCategory> categories) {
    final picked = <String>{};
    final pickedTopics = <String>{};
    var useSeeds = true;
    final keywordController = TextEditingController();
    final selectable = [
      for (final c in categories)
        if (c.id != _discoverCategoryId && c.id != ytUncategorizedId) c,
    ];
    return showDialog<
      ({Set<String> categoryIds, List<String> keywords, bool useSeeds})
    >(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('挖掘新頻道', style: TextStyle(color: AppColors.ink)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App 內的分類（不選＝全部）', style: AppText.note),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in selectable)
                      FilterChip(
                        label: Text(c.name),
                        selected: picked.contains(c.id),
                        onSelected: (v) => setDialogState(() {
                          if (v) {
                            picked.add(c.id);
                          } else {
                            picked.remove(c.id);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Text('更多主題（不限 App 內有的分類，可複選）', style: AppText.note),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _discoverTopics)
                      FilterChip(
                        label: Text(t),
                        selected: pickedTopics.contains(t),
                        onSelected: (v) => setDialogState(() {
                          if (v) {
                            pickedTopics.add(t);
                          } else {
                            pickedTopics.remove(t);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  controller: keywordController,
                  decoration: const InputDecoration(
                    labelText: '自訂關鍵字（選填）',
                    hintText: '例如：露營裝備',
                  ),
                  style: const TextStyle(color: AppColors.ink),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: useSeeds,
                  onChanged: (v) => setDialogState(() => useSeeds = v),
                  title: const Text(
                    '參考 App 內頻道的推薦',
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
                  subtitle: Text(
                    useSeeds
                        ? '從你已追蹤的頻道推薦區找，省配額、口味相近'
                        : '不看 App 內頻道，只用關鍵字搜尋，範圍廣但較雜、配額用較多',
                    style: AppText.note,
                  ),
                ),
                Text('一次挖 10 個 App 裡沒有的頻道，已刪除過的不會再出現。', style: AppText.note),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                categoryIds: {...picked},
                keywords: [
                  ...pickedTopics,
                  if (keywordController.text.trim().isNotEmpty)
                    keywordController.text.trim(),
                ],
                useSeeds: useSeeds,
              )),
              child: const Text('開始挖掘'),
            ),
          ],
        ),
      ),
    );
  }

  /// 挖掘新頻道（2026-09-24 使用者要求）：一次挖 10 個 App 裡沒有的頻道，
  /// 放進「挖掘新頻道」分類，自己再看要不要移到別的分類或刪掉。挖掘流程
  /// 見 [ChannelDiscoveryService]。
  Future<void> _digNewChannels() async {
    if (_digging) return;
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) {
      await showYtApiKeyDialog(context, ref);
      return;
    }
    final categories0 = await ref
        .read(ytTrackerRepositoryProvider)
        .loadCategories();
    if (!mounted) return;
    final options = await _showDigOptions(categories0);
    if (options == null || !mounted) return;
    _digging = true;
    final status = ValueNotifier<String>('準備中…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DigProgressDialog(status: status),
    );
    try {
      final repo = ref.read(ytTrackerRepositoryProvider);
      final categories = await repo.loadCategories();
      final channels = await repo.loadChannels();
      // 已知頻道要包含已刪除的：刪掉的就是不要的，不會再被挖出來。
      final known = await repo.channelsForUpload();
      final chosen = options.categoryIds;
      final pickedCategories = [
        for (final c in categories)
          if (c.id != _discoverCategoryId &&
              c.id != ytUncategorizedId &&
              (chosen.isEmpty || chosen.contains(c.id)))
            c,
      ];
      final found = await ChannelDiscoveryService(apiKey).discover(
        existing: known,
        // 選了類型就只拿那些分類裡的頻道當種子。
        seeds: !options.useSeeds
            ? const []
            : chosen.isEmpty
            ? channels
            : channels.where((c) => chosen.contains(c.categoryId)).toList(),
        keywords: [for (final c in pickedCategories) c.name],
        priorityKeywords: options.keywords,
        onProgress: (t) => status.value = t,
      );
      for (final d in found) {
        await repo.addChannel(
          YtChannel(
            id: 'found-${d.channelId}',
            name: d.title,
            categoryId: _discoverCategoryId,
            avatarImageUrl: d.avatarUrl,
            url: d.url,
            description: d.description,
            addedAt: DateTime.now(),
            youtubeChannelId: d.channelId,
            uploadsPlaylistId: d.uploadsPlaylistId,
            subscriberCount: d.subscriberCount,
            statsUpdatedAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _reload();
      showAppNotice(
        context,
        found.isEmpty
            ? '這次沒挖到符合條件的新頻道，再按一次試試'
            : '挖到 ${found.length} 個新頻道，放在「挖掘新頻道」分類',
      );
    } catch (e, stack) {
      AppLog.add('[YT] 挖掘新頻道失敗：$e\n$stack', isError: true);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showAppNotice(context, '挖掘失敗：$e', isError: true);
      }
    } finally {
      _digging = false;
      status.dispose();
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final imageController = TextEditingController();
    var colorValue = ytCategoryColors.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('新增分類', style: TextStyle(color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '分類名稱',
                  hintText: '例如：遊戲實況',
                  counterText: '',
                ),
                style: const TextStyle(color: AppColors.ink),
              ),
              const SizedBox(height: Gap.xs),
              TextField(
                controller: imageController,
                decoration: const InputDecoration(labelText: '底圖網址（選填）'),
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ytCategoryColors)
                    _ColorDot(
                      color: Color(c),
                      selected: c == colorValue,
                      onTap: () => setDialogState(() => colorValue = c),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ytAccent,
                foregroundColor: AppColors.ytAccentInk,
              ),
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    if (saved != true || name.isEmpty) return;
    await ref
        .read(ytTrackerRepositoryProvider)
        .addCategory(
          YtCategory(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            colorValue: colorValue,
            imageUrl: imageController.text.trim(),
          ),
        );
    if (!mounted) return;
    _reload();
  }

  Future<void> _showEditCategoryDialog(YtCategory category) async {
    final controller = TextEditingController(text: category.name);
    final imageController = TextEditingController(text: category.imageUrl);
    var colorValue = category.colorValue;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('編輯分類', style: TextStyle(color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '分類名稱',
                  counterText: '',
                ),
                style: const TextStyle(color: AppColors.ink),
              ),
              const SizedBox(height: Gap.xs),
              TextField(
                controller: imageController,
                decoration: const InputDecoration(labelText: '底圖網址（選填）'),
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ytCategoryColors)
                    _ColorDot(
                      color: Color(c),
                      selected: c == colorValue,
                      onTap: () => setDialogState(() => colorValue = c),
                    ),
                ],
              ),
              // 刪除是破壞性動作：跟一般的「取消／儲存」分開，獨立放在
              // 內容最底下、紅色外框全寬按鈕（一般手機 App 的慣例），不跟
              // 底部按鈕列擠在一起，也不用紅色實心搶過主要動作
              // （2026-09-24 使用者要求重新配置）。
              const SizedBox(height: Gap.lg),
              const Divider(height: 1, color: AppColors.glassEdge),
              const SizedBox(height: Gap.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'delete'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('刪除分類'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.bad,
                    side: BorderSide(
                      color: AppColors.bad.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 底部按鈕列照慣例：次要的「取消」在左（純文字），主要的「儲存」
          // 在最右（實心強調色，用藍色不是紅色——紅色留給刪除）。
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    final repo = ref.read(ytTrackerRepositoryProvider);
    if (action == 'save') {
      final name = controller.text.trim();
      if (name.isEmpty) return;
      await repo.updateCategory(
        YtCategory(
          id: category.id,
          name: name,
          colorValue: colorValue,
          imageUrl: imageController.text.trim(),
        ),
      );
      if (!mounted) return;
      _reload();
    } else if (action == 'delete') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('刪除這個分類？', style: TextStyle(color: AppColors.ink)),
          content: Text('底下的頻道不會被刪除，會變成未分類。', style: AppText.bodyDim),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('刪除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await repo.deleteCategory(category.id);
      if (!mounted) return;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: 'YT 頻道追蹤',
                  showBack: false,
                  actions: [
                    Consumer(
                      builder: (context, ref, _) {
                        final hasKey =
                            (ref.watch(ytApiKeyProvider) ?? '').isNotEmpty;
                        return IconButton(
                          onPressed: () => showYtApiKeyDialog(context, ref),
                          icon: Icon(
                            hasKey ? Icons.vpn_key : Icons.vpn_key_outlined,
                            size: 20,
                          ),
                          color: hasKey ? AppColors.ok : AppColors.ink2,
                          tooltip: hasKey ? 'API 金鑰已儲存' : '設定 API 金鑰',
                        );
                      },
                    ),
                    // 測試通知／匯出收進「⋮」選單，不要跟金鑰狀態、新增
                    // 分類這兩個常用項目擠在同一排——四顆小圖示疊在頂部列
                    // 本來就已經很擠，使用者反應找不到測試通知按鈕，很可能
                    // 就是這排太擠，眼睛掃過去沒認出來（2026-09-23）。收進
                    // 選單後項目有文字標籤，比一顆顆小圖示更好辨識。
                    IconButton(
                      onPressed: _digNewChannels,
                      icon: const Icon(Icons.travel_explore_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '挖掘新頻道',
                    ),
                    PopupMenuButton<_YtHomeMenuAction>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '更多',
                      onSelected: (action) {
                        switch (action) {
                          case _YtHomeMenuAction.testNotification:
                            testNotification(context);
                          case _YtHomeMenuAction.export:
                            _showExportDialog(context, ref);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _YtHomeMenuAction.testNotification,
                          child: Row(
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Text('測試通知'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _YtHomeMenuAction.export,
                          child: Row(
                            children: [
                              Icon(Icons.ios_share_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('匯出分類／頻道'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: _showAddCategoryDialog,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 20,
                      ),
                      color: AppColors.ink2,
                      tooltip: '新增分類',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final categories = snap.data!.categories;
                      final channels = snap.data!.channels;
                      final unassigned = channels
                          .where((c) => c.categoryId == null)
                          .toList();
                      // 「未分類」不是真的存在的分類，是頻道沒選分類（或
                      // 分類被刪掉）的統稱——之前只能從「全部頻道」找，
                      // 首頁完全看不到它們存在，補一張跟真分類長得一樣
                      // 但沒有編輯/刪除功能的卡片（2026-09-22 使用者
                      // 要求：未分類頻道首頁也要看得到）。
                      final uncategorized = unassigned.isEmpty
                          ? null
                          : const YtCategory(
                              id: ytUncategorizedId,
                              name: '未分類',
                              colorValue: 0xFF74738A,
                            );
                      // 格子順序：一般分類 → 未分類 → 「看過但不喜歡」固定最後一個
                      // （2026-09-24 使用者要求）。
                      final gridCats = [
                        ...categories.where(
                          (c) => c.id != ytDislikedCategoryId,
                        ),
                        ?uncategorized,
                        ...categories.where(
                          (c) => c.id == ytDislikedCategoryId,
                        ),
                      ];
                      final gridCount = gridCats.length;
                      final q = _query.trim().toLowerCase();
                      final categoryNameById = {
                        for (final c in categories) c.id: c.name,
                      };
                      final matches = q.isEmpty
                          ? const <YtChannel>[]
                          : channels
                                // 只比對頻道名稱：網址（含分享連結的 ?si= 亂碼）跟簡介
                                // 也比對的話，打一個字母會冒出一堆名字不含它的頻道。
                                .where((c) => zhContains(c.name, q))
                                .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '搜尋頻道',
                              hintStyle: const TextStyle(
                                fontSize: 14,
                                color: AppColors.ink3,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: AppColors.ink2,
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      color: AppColors.ink2,
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                              filled: true,
                              fillColor: AppColors.glassFill,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  Radii.button,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.glassEdge,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  Radii.button,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.accentGlassEdge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          Expanded(
                            child: q.isNotEmpty
                                ? _SearchResults(
                                    channels: matches,
                                    categoryNameById: categoryNameById,
                                    onOpen: (c) => context
                                        .push('/yt-tracker/channel/${c.id}')
                                        .then((_) => _reload()),
                                  )
                                : gridCount == 0
                                ? _EmptyState(onAdd: _showAddCategoryDialog)
                                : CustomScrollView(
                                    slivers: [
                                      // 「全部」獨佔整行、放第一個（2026-09-24 使用者
                                      // 要求）：不是真的分類，就是不篩選、看所有頻道，
                                      // 用 all.png 當底圖，沒有編輯／刪除。整行比一般
                                      // 分類卡寬很多，底圖建議 1800×600（3:1）。
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: AspectRatio(
                                            aspectRatio: 3,
                                            child: _CategoryCard(
                                              category: const YtCategory(
                                                id: '__all__',
                                                name: '全部',
                                                colorValue: 0xFF7EA6FF,
                                                imageUrl:
                                                    'assets/images/yt_tracker/all.png',
                                              ),
                                              channels: channels,
                                              maxAvatars: 7,
                                              count: channels.length,
                                              onTap: () => context
                                                  .push(
                                                    '/yt-tracker/browse',
                                                    extra: <String>{},
                                                  )
                                                  .then((_) => _reload()),
                                              onLongPress: null,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 2,
                                              mainAxisSpacing: 10,
                                              crossAxisSpacing: 10,
                                              childAspectRatio: 1.5,
                                            ),
                                        delegate: SliverChildBuilderDelegate(
                                          childCount: gridCount,
                                          (_, i) {
                                            final cat = gridCats[i];
                                            final isUncategorized =
                                                cat.id == ytUncategorizedId;
                                            final catChannels = isUncategorized
                                                ? unassigned
                                                : channels
                                                      .where(
                                                        (c) =>
                                                            c.categoryId ==
                                                            cat.id,
                                                      )
                                                      .toList();
                                            return _CategoryCard(
                                              category: cat,
                                              channels: catChannels,
                                              maxAvatars: 3,
                                              count: catChannels.length,
                                              onTap: () => context
                                                  .push(
                                                    '/yt-tracker/browse',
                                                    extra: {cat.id},
                                                  )
                                                  .then((_) => _reload()),
                                              onLongPress: isUncategorized
                                                  ? null
                                                  : () =>
                                                        _showEditCategoryDialog(
                                                          cat,
                                                        ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: Gap.md),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _YtHomeMenuAction { testNotification, export }

/// 挖掘時可以直接勾選的熱門主題（不限 App 內有的分類），拿來當搜尋關鍵字。
const _discoverTopics = [
  '科技',
  '投資理財',
  '心理學',
  '歷史',
  '科普',
  '露營',
  '旅遊',
  '攝影',
  '烹飪食譜',
  '健身',
  '美妝保養',
  '寵物',
  '手作 DIY',
  '動漫',
  '電影解說',
  '語言學習',
  '房地產',
  '親子育兒',
  '醫療健康',
  '職場成長',
];

/// 「挖掘新頻道」分類的固定 ID（見 `yt_tracker_categories.json`）。
const _discoverCategoryId = 'seed-discover';

/// 挖掘進行中的等待視窗，顯示目前進度文字。
class _DigProgressDialog extends StatelessWidget {
  const _DigProgressDialog({required this.status});

  final ValueNotifier<String> status;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('挖掘新頻道中', style: TextStyle(color: AppColors.ink)),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, text, _) => Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: AppText.bodyDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 搜尋結果清單：頭像、名字、分類（跟訂閱人數），點了直接進頻道詳情。
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.channels,
    required this.categoryNameById,
    required this.onOpen,
  });

  final List<YtChannel> channels;
  final Map<String, String> categoryNameById;
  final void Function(YtChannel) onOpen;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(child: Text('找不到符合的頻道', style: AppText.bodyDim));
    }
    return ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.glassEdge),
      itemBuilder: (context, i) {
        final c = channels[i];
        final category = categoryNameById[c.categoryId] ?? '未分類';
        return InkWell(
          onTap: () => onOpen(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                YtChannelAvatar(channel: c, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.subscriberLabel == null
                            ? category
                            : '$category・${c.subscriberLabel}',
                        style: AppText.note,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('還沒有任何分類', style: AppText.bodyDim),
          const SizedBox(height: Gap.xs),
          Text('先建一個分類，之後才能把頻道分進去', style: AppText.note),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增分類'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ytAccent,
              foregroundColor: AppColors.ytAccentInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分類底圖可能是使用者手動貼的遠端網址，也可能是專案內建的 asset
/// （`assets/images/yt_tracker/...`，2026-09-23 使用者把自己準備的底圖
/// 直接丟進專案，不是連結）——用路徑開頭判斷該用哪個 widget 讀圖，不用
/// 另外加一個布林欄位增加資料結構複雜度。
class _CategoryImage extends StatelessWidget {
  const _CategoryImage({required this.url, required this.errorBuilder});

  final String url;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover, errorBuilder: errorBuilder);
    }
    return Image.network(url, fit: BoxFit.cover, errorBuilder: errorBuilder);
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.category,
    required this.channels,
    required this.maxAvatars,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final YtCategory category;
  final List<YtChannel> channels;

  /// 底下那排小頭像最多顯示幾個（2026-09-24 使用者要求：「全部」7 個、
  /// 其他分類 3 個，從全部頻道隨機抓；超過就在最後多顯示「⋯」）。
  final int maxAvatars;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  // 亂數種子固定在這張卡的生命週期內，重繪不會頭像一直跳；重新進首頁才重抽。
  final int _seed = Random().nextInt(1 << 30);

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final count = widget.count;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final all = widget.channels;
    final channels = (all.toList()..shuffle(Random(_seed)))
        .take(widget.maxAvatars)
        .toList();
    final hasMore = all.length > widget.maxAvatars;
    final hasImage = category.imageUrl.isNotEmpty;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.card),
          color: category.color.withValues(alpha: 0.12),
          border: Border.all(color: category.color.withValues(alpha: 0.4)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 有底圖才鋪，沒有就照舊用純色調子當底
            // （2026-09-22 使用者要求：卡片可以貼圖好看一點）。
            if (hasImage)
              _CategoryImage(
                url: category.imageUrl,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            if (hasImage)
              // 底圖上蓋一層深色漸層，不然文字/頭像疊在圖片上會看不清楚。
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasImage ? Colors.white : AppColors.ink,
                    ),
                  ),
                  Text(
                    '$count 個頻道',
                    style: hasImage
                        ? const TextStyle(fontSize: 11, color: Colors.white70)
                        : AppText.note,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (final c in channels)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: YtChannelAvatar(channel: c, radius: 11),
                        ),
                      // 超過顯示上限才出現：黑底「+N」（N＝沒顯示的頻道數）。原本後面還有
                      // 「⋯」，有 +N 之後多餘，2026-09-24 使用者要求拿掉。
                      if (hasMore) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '+${all.length - channels.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 匯出的範圍：只匯出這台裝置 localStorage 裡的，還是連專案已經打包
/// 好的分類／頻道快照一起，跟 `diary_page.dart` 的 `_ExportScope`
/// 同一個用途。
enum _ExportScope { localOnly, withSeed }

Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(ytTrackerRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final YtTrackerRepository repo;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  _ExportScope _scope = _ExportScope.localOnly;
  late Future<({String text, int categoryCount, int channelCount})> _future;

  @override
  void initState() {
    super.initState();
    _future = _build(_scope);
  }

  Future<({String text, int categoryCount, int channelCount})> _build(
    _ExportScope scope,
  ) async {
    if (scope == _ExportScope.localOnly) {
      return widget.repo.exportJson();
    }
    final mergedCategories = mergeSeedRecords(
      local: await widget.repo.loadCategories(),
      seed: await loadYtCategoriesSeed(),
      idOf: (e) => e.id,
      // 本機為準，同一套理由：要的是「補齊這台裝置漏掉、但專案快照裡
      // 已經有」的，不是拿快照蓋掉這台裝置剛新增的。
      priority: SeedMergePriority.local,
    );
    final mergedChannels = mergeSeedRecords(
      local: await widget.repo.loadChannels(),
      seed: await loadYtChannelsSeed(),
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
    );
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert({
        'categories': [for (final c in mergedCategories) c.toJson()],
        'channels': [for (final c in mergedChannels) c.toJson()],
      }),
      categoryCount: mergedCategories.length,
      channelCount: mergedChannels.length,
    );
  }

  void _setScope(_ExportScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _future = _build(scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filename = 'lume-yt-tracker-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出分類／頻道',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_ExportScope>(
            segments: const [
              ButtonSegment(
                value: _ExportScope.localOnly,
                label: Text('僅這台裝置'),
              ),
              ButtonSegment(value: _ExportScope.withSeed, label: Text('連快照一起')),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => _setScope(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.glassFill,
              foregroundColor: AppColors.ink2,
              selectedBackgroundColor: AppColors.ytAccent.withValues(
                alpha: 0.28,
              ),
              selectedForegroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.glassEdge),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FutureBuilder(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.md),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final data = snap.data!;
              final sizeLabel = _formatExportSize(
                utf8.encode(data.text).length,
              );
              return Text(
                '$filename\n${data.categoryCount} 個分類、${data.channelCount} 個頻道 ・ 約 $sizeLabel',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
              );
            },
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () async {
            final data = await _future;
            final ok = saveTextFile(filename, data.text);
            if (!context.mounted) return;
            showAppNotice(context, ok ? '已下載 $filename' : '這個平台還不支援下載，改用複製');
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ytAccent,
            foregroundColor: AppColors.ytAccentInk,
          ),
          child: const Text('下載'),
        ),
        OutlinedButton(
          onPressed: () async {
            final data = await _future;
            await Clipboard.setData(ClipboardData(text: data.text));
            if (!context.mounted) return;
            showAppNotice(context, '已複製到剪貼簿');
          },
          child: const Text('複製'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

String _formatExportSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _exportTodayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected ? Border.all(color: AppColors.ink, width: 2) : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
