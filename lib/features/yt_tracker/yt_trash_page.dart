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

/// 垃圾桶：只看已刪除（墓碑標記）的頻道，可以還原或永久刪除
/// （2026-09-29 使用者要求：點錯刪除鍵沒地方後悔）。
class YtTrashPage extends ConsumerStatefulWidget {
  const YtTrashPage({super.key});

  @override
  ConsumerState<YtTrashPage> createState() => _YtTrashPageState();
}

class _YtTrashPageState extends ConsumerState<YtTrashPage> {
  late Future<List<YtChannel>> _future = _load();

  Future<List<YtChannel>> _load() =>
      ref.read(ytTrackerRepositoryProvider).loadDeletedChannels();

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
                const AppTopBar(title: '垃圾桶', showSettings: false),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<YtChannel>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final channels = snap.data!;
                      if (channels.isEmpty) {
                        return Center(
                          child: Text('垃圾桶是空的', style: AppText.bodyDim),
                        );
                      }
                      return ListView.separated(
                        itemCount: channels.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: AppColors.glassEdge,
                        ),
                        itemBuilder: (context, i) {
                          final c = channels[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                YtChannelAvatar(channel: c, radius: 18),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _restore(c),
                                  icon: const Icon(
                                    Icons.restore_from_trash_outlined,
                                    size: 20,
                                  ),
                                  color: AppColors.ok,
                                  tooltip: '還原',
                                ),
                                IconButton(
                                  onPressed: () => _purge(c),
                                  icon: const Icon(
                                    Icons.delete_forever_outlined,
                                    size: 20,
                                  ),
                                  color: AppColors.bad,
                                  tooltip: '永久刪除',
                                ),
                              ],
                            ),
                          );
                        },
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
