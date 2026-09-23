import 'dart:convert' show utf8, JsonEncoder;

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
import '../../data/seed/seed_merge.dart';
import '../../data/seed/yt_tracker_seed_loader.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';

/// YT 頻道追蹤首頁：分類資料夾格子（設計稿 06/07/08 定案，見
/// `design-history/Yt頻道訂閱管理/`）。
///
/// 這是「管理」導向的功能，不是「看動態牆」——使用者原話：訂閱太多人、
/// 不是為了照 YouTube 那樣逛訂閱的人，是想先分類、想不知道看誰的時候
/// 能照分類找。所以首頁不是影片清單，是分類資料夾（2026-09-22 使用者
/// 要求）。「依影片顯示」真的接了 YouTube Data API（2026-09-22），但
/// 金鑰只存記憶體，不進 localStorage／Git，所以一進這頁、金鑰還沒存的
/// 話會先跳懸浮視窗問（見 `yt_api_key_dialog.dart`）。
class YtTrackerHomePage extends ConsumerStatefulWidget {
  const YtTrackerHomePage({super.key});

  @override
  ConsumerState<YtTrackerHomePage> createState() => _YtTrackerHomePageState();
}

class _YtTrackerHomePageState extends ConsumerState<YtTrackerHomePage> {
  late Future<({List<YtCategory> categories, List<YtChannel> channels})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // 一進頁面就問金鑰，但不擋categorization——沒金鑰一樣能用分類/頻道
    // 管理，只有「依影片顯示」需要（2026-09-22 使用者要求：剛進來先
    // 跳懸浮視窗輸入）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = ref.read(ytApiKeyProvider);
      if (key == null || key.isEmpty) {
        showYtApiKeyDialog(context, ref);
      }
    });
  }

  /// 打開這頁那一瞬間先把分類／頻道快照（見 `yt_tracker_seed_loader.dart`）
  /// 併回本機，跟 `diary_page.dart` 的 `_loadWithSeedMerge` 同一套。
  Future<({List<YtCategory> categories, List<YtChannel> channels})> _load() async {
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
    await ref.read(ytTrackerRepositoryProvider).addCategory(
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
            ],
          ),
          // 刪除縮小放最左邊，跟儲存/取消拉開距離，不容易誤按；儲存在
          // 取消左邊（2026-09-22 使用者要求，跟頻道編輯對話框同一套）。
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('刪除', style: TextStyle(fontSize: 12)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ytAccent,
                foregroundColor: AppColors.ytAccentInk,
              ),
              child: const Text('儲存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
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
          content: Text(
            '底下的頻道不會被刪除，會變成未分類。',
            style: AppText.bodyDim,
          ),
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
                              Icon(Icons.notifications_active_outlined, size: 18),
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
                      icon: const Icon(Icons.create_new_folder_outlined, size: 20),
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
                      final gridCount =
                          categories.length + (uncategorized == null ? 0 : 1);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: gridCount == 0
                                ? _EmptyState(onAdd: _showAddCategoryDialog)
                                : GridView.builder(
                                    itemCount: gridCount,
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: 1.5,
                                        ),
                                    itemBuilder: (_, i) {
                                      final isUncategorized =
                                          i == categories.length;
                                      final cat = isUncategorized
                                          ? uncategorized!
                                          : categories[i];
                                      final catChannels = isUncategorized
                                          ? unassigned
                                          : channels
                                                .where(
                                                  (c) => c.categoryId == cat.id,
                                                )
                                                .toList();
                                      return _CategoryCard(
                                        category: cat,
                                        channels: catChannels.take(4).toList(),
                                        count: catChannels.length,
                                        onTap: () => context.push(
                                          '/yt-tracker/browse',
                                          extra: {cat.id},
                                        ).then((_) => _reload()),
                                        onLongPress: isUncategorized
                                            ? null
                                            : () => _showEditCategoryDialog(cat),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: Gap.sm),
                          GlassCard(
                            onTap: () => context
                                .push('/yt-tracker/browse', extra: <String>{})
                                .then((_) => _reload()),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.subscriptions_outlined,
                                  size: 18,
                                  color: AppColors.ink2,
                                ),
                                const SizedBox(width: Gap.sm),
                                Text(
                                  '全部頻道（共 ${channels.length} 個）',
                                  style: AppText.bodyDim,
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.ink3,
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.channels,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final YtCategory category;
  final List<YtChannel> channels;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
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
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
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
              ButtonSegment(
                value: _ExportScope.withSeed,
                label: Text('連快照一起'),
              ),
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
              final sizeLabel = _formatExportSize(utf8.encode(data.text).length);
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? '已下載 $filename' : '這個平台還不支援下載，改用複製')),
            );
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已複製到剪貼簿')));
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
  const _ColorDot({required this.color, required this.selected, required this.onTap});

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
