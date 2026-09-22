import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'yt_channel_avatar.dart';

/// 頻道詳情。目前只有基本資料（名稱、分類、網址）跟編輯／刪除，還沒有
/// 「最近影片」的真資料——見 `yt_tracker_browse_page.dart` 的
/// `_VideoEmptyState` 說明，同一個理由。
class YtTrackerChannelPage extends ConsumerStatefulWidget {
  const YtTrackerChannelPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<YtTrackerChannelPage> createState() =>
      _YtTrackerChannelPageState();
}

class _YtTrackerChannelPageState extends ConsumerState<YtTrackerChannelPage> {
  late Future<({YtChannel? channel, List<YtCategory> categories})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({YtChannel? channel, List<YtCategory> categories})> _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final channels = await repo.loadChannels();
    final categories = await repo.loadCategories();
    final channel = channels.where((c) => c.id == widget.channelId);
    return (channel: channel.isEmpty ? null : channel.first, categories: categories);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _showEditDialog(YtChannel channel, List<YtCategory> categories) async {
    final nameController = TextEditingController(text: channel.name);
    final urlController = TextEditingController(text: channel.url);
    final avatarController = TextEditingController(text: channel.avatarImageUrl);
    final descriptionController = TextEditingController(text: channel.description);
    String? categoryId = channel.categoryId;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('編輯頻道', style: TextStyle(color: AppColors.ink)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 30,
                  decoration: const InputDecoration(counterText: ''),
                  style: const TextStyle(color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(hintText: '頻道網址（選填）'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(hintText: '頭像圖片網址（選填）'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: descriptionController,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: const InputDecoration(hintText: '簡介（選填）'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.sm),
                Text('分類', style: AppText.note),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pick(
                      label: '未分類',
                      color: AppColors.ink3,
                      selected: categoryId == null,
                      onTap: () => setDialogState(() => categoryId = null),
                    ),
                    for (final cat in categories)
                      _Pick(
                        label: cat.name,
                        color: cat.color,
                        selected: categoryId == cat.id,
                        onTap: () => setDialogState(() => categoryId = cat.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('刪除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ytAccent,
                foregroundColor: AppColors.ytAccentInk,
              ),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );

    final repo = ref.read(ytTrackerRepositoryProvider);
    if (action == 'save') {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      await repo.updateChannel(
        YtChannel(
          id: channel.id,
          name: name,
          categoryId: categoryId,
          avatarEmoji: channel.avatarEmoji,
          avatarImageUrl: avatarController.text.trim(),
          url: urlController.text.trim(),
          description: descriptionController.text.trim(),
          addedAt: channel.addedAt,
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
          title: const Text('刪除這個頻道？', style: TextStyle(color: AppColors.ink)),
          content: Text('這個動作無法復原。', style: AppText.bodyDim),
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
      await repo.deleteChannel(channel.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
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
                Expanded(
                  child: FutureBuilder(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppTopBar(title: '頻道'),
                            const Expanded(
                              child: Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                            ),
                          ],
                        );
                      }
                      final channel = snap.data!.channel;
                      final categories = snap.data!.categories;
                      if (channel == null) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppTopBar(title: '頻道'),
                            Expanded(
                              child: Center(
                                child: Text('找不到這個頻道', style: AppText.bodyDim),
                              ),
                            ),
                          ],
                        );
                      }
                      final category = categories
                          .where((c) => c.id == channel.categoryId);
                      final categoryLabel =
                          category.isEmpty ? '未分類' : category.first.name;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTopBar(
                            title: channel.name,
                            actions: [
                              IconButton(
                                onPressed: () =>
                                    _showEditDialog(channel, categories),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                color: AppColors.ink2,
                                tooltip: '編輯頻道',
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.md),
                          Row(
                            children: [
                              YtChannelAvatar(channel: channel, radius: 28),
                              const SizedBox(width: Gap.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      channel.name,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(categoryLabel, style: AppText.note),
                                    if (channel.url.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        channel.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.note,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (channel.description.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            const PanelLabel('簡介'),
                            const SizedBox(height: Gap.xs),
                            Text(channel.description, style: AppText.bodyDim),
                          ],
                          const SizedBox(height: Gap.md),
                          const PanelLabel('最近影片'),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.video_library_outlined,
                                      size: 32,
                                      color: AppColors.ink3,
                                    ),
                                    const SizedBox(height: Gap.sm),
                                    Text(
                                      '還沒有接這個頻道的影片資料',
                                      style: AppText.bodyDim,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '目前只做分類／頻道管理，之後接上\nYouTube 資料來源，這裡就會列出\n最新上傳的影片。',
                                      style: AppText.note,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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

class _Pick extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? color.withValues(alpha: 0.22) : AppColors.glassFill,
          border: Border.all(color: selected ? color : AppColors.glassEdge),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}
