import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'yt_channel_avatar.dart';

enum _ViewMode { channel, video }

/// 篩選＋頻道／影片雙視圖畫面（設計稿 06/07/08 定案）。從首頁點分類
/// 資料夾進來時，[initialCategoryIds] 就是那個分類，篩選 chip 會直接
/// 帶入選中狀態，不用重選一次（2026-09-22 使用者要求）。
///
/// 「依影片顯示」目前是空狀態——還沒接 YouTube API（見
/// `yt_tracker_repository.dart` 說明），畫面先做好，之後接上資料就能用。
class YtTrackerBrowsePage extends ConsumerStatefulWidget {
  const YtTrackerBrowsePage({super.key, required this.initialCategoryIds});

  final Set<String> initialCategoryIds;

  @override
  ConsumerState<YtTrackerBrowsePage> createState() =>
      _YtTrackerBrowsePageState();
}

class _YtTrackerBrowsePageState extends ConsumerState<YtTrackerBrowsePage> {
  late Future<({List<YtCategory> categories, List<YtChannel> channels})> _future;
  late final Set<String> _selected = {...widget.initialCategoryIds};
  _ViewMode _mode = _ViewMode.channel;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({List<YtCategory> categories, List<YtChannel> channels})> _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final categories = await repo.loadCategories();
    final channels = await repo.loadChannels();
    return (categories: categories, channels: channels);
  }

  void _reload() => setState(() => _future = _load());

  String _title(List<YtCategory> categories) {
    if (_selected.isEmpty) return '全部頻道';
    if (_selected.length == 1) {
      if (_selected.first == ytUncategorizedId) return '未分類';
      final match = categories.where((c) => c.id == _selected.first);
      if (match.isNotEmpty) return match.first.name;
    }
    return '已選 ${_selected.length} 個分類';
  }

  Future<void> _showAddChannelDialog(List<YtCategory> categories) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final avatarController = TextEditingController();
    final descriptionController = TextEditingController();
    String? categoryId =
        _selected.length == 1 && _selected.first != ytUncategorizedId
        ? _selected.first
        : null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('新增頻道', style: TextStyle(color: AppColors.ink)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 30,
                  decoration: const InputDecoration(hintText: '頻道名稱', counterText: ''),
                  style: const TextStyle(color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    hintText: '頻道網址（選填，先存起來給之後用）',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(
                    hintText: '頭像圖片網址（選填，去頻道頁面複製大頭貼圖片網址）',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: descriptionController,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: '簡介（選填，這個頻道在做什麼）',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.sm),
                Text('分類', style: AppText.note),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CategoryPickChip(
                      label: '未分類',
                      color: AppColors.ink3,
                      selected: categoryId == null,
                      onTap: () => setDialogState(() => categoryId = null),
                    ),
                    for (final cat in categories)
                      _CategoryPickChip(
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
    final name = nameController.text.trim();
    if (saved != true || name.isEmpty) return;
    await ref.read(ytTrackerRepositoryProvider).addChannel(
      YtChannel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        categoryId: categoryId,
        avatarImageUrl: avatarController.text.trim(),
        url: urlController.text.trim(),
        description: descriptionController.text.trim(),
        addedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    _reload();
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
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final categories = snap.data!.categories;
                      final allChannels = snap.data!.channels;
                      final hasUnassigned = allChannels.any(
                        (c) => c.categoryId == null,
                      );
                      final channels = _selected.isEmpty
                          ? allChannels
                          : allChannels
                                .where(
                                  (c) => _selected.contains(
                                    c.categoryId ?? ytUncategorizedId,
                                  ),
                                )
                                .toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTopBar(
                            title: _title(categories),
                            actions: [
                              IconButton(
                                onPressed: () => _showAddChannelDialog(categories),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 20,
                                ),
                                color: AppColors.ink2,
                                tooltip: '新增頻道',
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.sm),
                          if (categories.isNotEmpty || hasUnassigned)
                            SizedBox(
                              height: 34,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount:
                                    categories.length + (hasUnassigned ? 1 : 0),
                                separatorBuilder: (_, _) => const SizedBox(width: 6),
                                itemBuilder: (_, i) {
                                  if (i == categories.length) {
                                    final on = _selected.contains(
                                      ytUncategorizedId,
                                    );
                                    return _CategoryPickChip(
                                      label: '未分類',
                                      color: AppColors.ink3,
                                      selected: on,
                                      onTap: () => setState(() {
                                        if (on) {
                                          _selected.remove(ytUncategorizedId);
                                        } else {
                                          _selected.add(ytUncategorizedId);
                                        }
                                      }),
                                    );
                                  }
                                  final cat = categories[i];
                                  final on = _selected.contains(cat.id);
                                  return _CategoryPickChip(
                                    label: cat.name,
                                    color: cat.color,
                                    selected: on,
                                    onTap: () => setState(() {
                                      if (on) {
                                        _selected.remove(cat.id);
                                      } else {
                                        _selected.add(cat.id);
                                      }
                                    }),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: Gap.sm),
                          SegmentedButton<_ViewMode>(
                            segments: const [
                              ButtonSegment(
                                value: _ViewMode.channel,
                                label: Text('依頻道顯示'),
                              ),
                              ButtonSegment(
                                value: _ViewMode.video,
                                label: Text('依影片顯示'),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) =>
                                setState(() => _mode = s.first),
                            style: SegmentedButton.styleFrom(
                              backgroundColor: AppColors.glassFill,
                              foregroundColor: AppColors.ink2,
                              selectedBackgroundColor: AppColors.ytAccent
                                  .withValues(alpha: 0.28),
                              selectedForegroundColor: AppColors.ink,
                              side: const BorderSide(color: AppColors.glassEdge),
                            ),
                          ),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: _mode == _ViewMode.channel
                                ? _ChannelGrid(channels: channels)
                                : const _VideoEmptyState(),
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

class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.channels});

  final List<YtChannel> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Text('這個篩選條件下沒有頻道', style: AppText.bodyDim),
      );
    }
    return GridView.builder(
      itemCount: channels.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (_, i) {
        final c = channels[i];
        return InkWell(
          onTap: () => context.push('/yt-tracker/channel/${c.id}'),
          borderRadius: BorderRadius.circular(Radii.card),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              color: AppColors.glassFill,
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                YtChannelAvatar(channel: c, radius: 17),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VideoEmptyState extends StatelessWidget {
  const _VideoEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined, size: 32, color: AppColors.ink3),
            const SizedBox(height: Gap.sm),
            Text('還沒有接影片資料', style: AppText.bodyDim, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              '目前只做分類／頻道管理，之後接上 YouTube 資料來源，\n這裡就會列出選中分類底下所有頻道的影片，依上傳時間排序。',
              style: AppText.note,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickChip extends StatelessWidget {
  const _CategoryPickChip({
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
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          color: selected ? color.withValues(alpha: 0.22) : AppColors.glassFill,
          border: Border.all(
            color: selected ? color : AppColors.glassEdge,
          ),
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
