import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_playlist_store.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'yt_playlist_actions.dart';
import 'yt_video_row.dart';

/// YT 播放清單（2026-10-14 使用者選設計稿第 1 版「YouTube 式」）：兩欄
/// 大卡，封面是清單裡前 4 部縮圖拼起來、右邊半透明寫幾部（YouTube 媒體庫
/// 那樣）。「稍後觀看」一定在第一個。
class YtPlaylistsPage extends ConsumerWidget {
  const YtPlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = YtPlaylistStore.visible(ref.watch(ytPlaylistsProvider));
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
                  title: '播放清單',
                  titleIcon: Icons.video_library_rounded,
                  titleIconColor: AppColors.ytAccent,
                  showBack: Navigator.of(context).canPop(),
                  actions: [
                    IconButton(
                      onPressed: () async {
                        final name = await askPlaylistName(context);
                        if (name == null) return;
                        await YtPlaylistActions(ref).create(name);
                        if (context.mounted) {
                          showAppNotice(context, '已建立「$name」');
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 22),
                      color: AppColors.ink2,
                      tooltip: '新增播放清單',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                    itemCount: playlists.length,
                    itemBuilder: (context, i) {
                      final p = playlists[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push('/yt-playlists/${p.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 10,
                              child: YtPlaylistCover(playlist: p),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              '${p.isLater ? '系統清單・' : ''}${p.items.length} 部影片',
                              style: AppText.note,
                            ),
                          ],
                        ),
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

/// 封面：前 4 部縮圖拼成 2×2，右邊一塊半透明寫幾部。
class YtPlaylistCover extends StatelessWidget {
  const YtPlaylistCover({super.key, required this.playlist});

  final YtPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final thumbs = playlist.items.take(4).toList();
    Widget cell(int k) => k < thumbs.length
        ? Image.network(
            thumbs[k].video.thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.glassFill),
          )
        : const ColoredBox(color: Color(0xFF1B1B28));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              for (final row in [0, 2])
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: cell(row)),
                      const SizedBox(width: 2),
                      Expanded(child: cell(row + 1)),
                    ],
                  ),
                ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 64,
            child: ColoredBox(
              color: const Color(0xB80A0A10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    playlist.isLater
                        ? Icons.watch_later_outlined
                        : Icons.playlist_play_rounded,
                    color: AppColors.ink,
                    size: 20,
                  ),
                  Text(
                    '${playlist.items.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一份播放清單：上面漸層大標題，下面影片（⋮ 可以移到最上面、移除、
/// 存到別的清單）。⋯ 改名、刪除清單（「稍後觀看」不能）。
class YtPlaylistPage extends ConsumerWidget {
  const YtPlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ytPlaylistsProvider);
    final p = YtPlaylistActions(ref).byId(playlistId);
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
                  title: p?.name ?? '播放清單',
                  showBack: Navigator.of(context).canPop(),
                  actions: [
                    if (p != null && !p.isLater)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: AppColors.ink2,
                        ),
                        color: const Color(0xFF1A1A24),
                        onSelected: (v) => _onMenu(context, ref, p, v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('改名')),
                          PopupMenuItem(value: 'delete', child: Text('刪除清單')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: p == null
                      ? Center(child: Text('這份清單不在了', style: AppText.bodyDim))
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(child: _Header(playlist: p)),
                            if (p.items.isEmpty)
                              const SliverToBoxAdapter(
                                child: InlineEmptyCard(
                                  title: '還沒有影片',
                                  message: '在影片右邊 ⋮ 選「存到播放清單…」',
                                ),
                              ),
                            SliverList.separated(
                              itemCount: p.items.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: AppColors.glassEdge,
                              ),
                              itemBuilder: (_, i) {
                                final item = p.items[i];
                                return YtVideoRow(
                                  key: ValueKey(item.videoId),
                                  video: item.video,
                                  subtitle: [
                                    if (item.channelName.isNotEmpty)
                                      item.channelName,
                                    ytRelativeTime(item.video.publishedAt),
                                  ].join('・'),
                                  channelId: item.channelId,
                                  channelName: item.channelName,
                                  playlistId: p.id,
                                  // 收藏的就是要看到，隱藏過的也照樣列。
                                  forceShow: true,
                                );
                              },
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: Gap.lg),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    YtPlaylist p,
    String v,
  ) async {
    final actions = YtPlaylistActions(ref);
    if (v == 'rename') {
      final name = await askPlaylistName(context, title: '改名', initial: p.name);
      if (name != null) await actions.rename(p.id, name);
      return;
    }
    final ok = await showAppConfirmDialog(
      context,
      title: '刪除「${p.name}」？',
      message: '清單裡的 ${p.items.length} 部影片只是從清單拿掉，影片本身不受影響。',
      confirmLabel: '刪除',
    );
    if (!ok || !context.mounted) return;
    await actions.delete(p.id);
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/yt-playlists');
    }
    showAppNotice(context, '已刪除「${p.name}」');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.playlist});

  final YtPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final color = playlist.isLater
        ? const Color(0xFF7EA6FF)
        : AppColors.ytAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.33),
            color.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            playlist.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text('${playlist.items.length} 部影片', style: AppText.note),
        ],
      ),
    );
  }
}
