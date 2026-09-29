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
import 'yt_channel_avatar.dart';

/// 垃圾桶進了某個分類之後的清單：被刪除的頻道在這裡還原／永久刪除
/// （2026-09-29 使用者要求：垃圾桶也要照分類分層，跟 YT 首頁「點分類卡
/// 進 browse 頁」同一種兩層結構——分類格子見 `YtTrashPage`）。
/// [categoryIds] 空集合代表「全部」，不篩選。
class YtTrashBrowsePage extends ConsumerStatefulWidget {
  const YtTrashBrowsePage({super.key, required this.categoryIds});

  final Set<String> categoryIds;

  @override
  ConsumerState<YtTrashBrowsePage> createState() => _YtTrashBrowsePageState();
}

class _YtTrashBrowsePageState extends ConsumerState<YtTrashBrowsePage> {
  late Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _future = _load();

  Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final categories = await repo.loadCategories();
    final channels = await repo.loadDeletedChannels();
    return (categories: categories, channels: channels);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _restore(YtChannel c) async {
    await ref.read(ytTrackerRepositoryProvider).restoreChannel(c.id);
    _reload();
  }

  Future<void> _purge(YtChannel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text(
          '永久刪除「${c.name}」？',
          style: const TextStyle(color: AppColors.ink, fontSize: 16),
        ),
        content: Text(
          '之後垃圾桶就看不到它了，不能再還原。\n（如果還有別台裝置沒同步過這次刪除，'
          '之後同步時它可能又會出現在垃圾桶裡。）',
          style: AppText.bodyDim,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
            child: const Text('永久刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ytTrackerRepositoryProvider).purgeChannel(c.id);
    _reload();
  }

  String _title(List<YtCategory> categories) {
    if (widget.categoryIds.isEmpty) return '垃圾桶・全部';
    final id = widget.categoryIds.first;
    if (id == ytUncategorizedId) return '垃圾桶・未分類';
    for (final c in categories) {
      if (c.id == id) return '垃圾桶・${c.name}';
    }
    return '垃圾桶';
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
                  child:
                      FutureBuilder<
                        ({List<YtCategory> categories, List<YtChannel> channels})
                      >(
                        future: _future,
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          final categories = snap.data!.categories;
                          final all = snap.data!.channels;
                          final channels = widget.categoryIds.isEmpty
                              ? all
                              : all
                                    .where(
                                      (c) => widget.categoryIds.contains(
                                        c.categoryId ?? ytUncategorizedId,
                                      ),
                                    )
                                    .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTopBar(
                                title: _title(categories),
                                titleIcon: Icons.delete_outline_rounded,
                                showSettings: false,
                              ),
                              const SizedBox(height: Gap.md),
                              Expanded(
                                child: channels.isEmpty
                                    ? Center(
                                        child: Text(
                                          '這個分類沒有被刪除的頻道',
                                          style: AppText.bodyDim,
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: channels.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(
                                              height: 1,
                                              color: AppColors.glassEdge,
                                            ),
                                        itemBuilder: (context, i) {
                                          final c = channels[i];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                YtChannelAvatar(
                                                  channel: c,
                                                  radius: 18,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    c.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors.ink,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: () =>
                                                      _restore(c),
                                                  icon: const Icon(
                                                    Icons
                                                        .restore_from_trash_outlined,
                                                    size: 20,
                                                  ),
                                                  color: AppColors.ok,
                                                  tooltip: '還原',
                                                ),
                                                IconButton(
                                                  onPressed: () => _purge(c),
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_forever_outlined,
                                                    size: 20,
                                                  ),
                                                  color: AppColors.bad,
                                                  tooltip: '永久刪除',
                                                ),
                                              ],
                                            ),
                                          );
                                        },
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
