import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show appRouter;
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/music.dart';
import 'music_actions.dart';
import 'music_player.dart';
import 'music_widgets.dart';

/// 迷你播放列的高度（頁面最下面要多空這麼高，見 `app_bottom_nav.dart`）。
const musicMiniHeight = 64.0;

/// 音樂播放器畫在整個 App 最上層（2026-10-19）：迷你播放列浮在底部分頁列
/// 上面、點了展開成全螢幕。YouTube 播放器只有一個（[MusicPlayer.bridge]），
/// 迷你跟全螢幕是同一個 iframe 變大變小，所以切換、換頁都不會中斷。
///
/// 跳出對話框、底部面板時迷你列先滑下去讓開（[hideMini]），播放器本身還在。
class MusicPlayerLayer extends ConsumerWidget {
  const MusicPlayerLayer({
    super.key,
    required this.miniBottom,
    required this.hideMini,
  });

  /// 迷你播放列離畫面底部多遠（底部分頁列上面）。
  final double miniBottom;
  final bool hideMini;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final id = player.current;
    if (id == null) return const SizedBox.shrink();
    final data = ref.watch(musicDataProvider);
    final v = data.version(id);
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final full = player.expanded;
    // 影片框的位置：迷你時在播放列左邊；全螢幕時在上面（只聽時縮到右上角）。
    const miniVideoW = 86.0;
    final Rect videoRect;
    if (!full) {
      final top = size.height - miniBottom - musicMiniHeight + 6;
      videoRect = Rect.fromLTWH(
        18,
        hideMini ? size.height + 40 : top,
        miniVideoW,
        musicMiniHeight - 12,
      );
    } else if (player.showVideo) {
      final w = math.min(size.width - 32, 640.0);
      videoRect = Rect.fromLTWH(
        (size.width - w) / 2,
        mq.padding.top + 60,
        w,
        w * 9 / 16,
      );
    } else {
      videoRect = Rect.fromLTWH(
        size.width - 16 - 128,
        mq.padding.top + 60,
        128,
        72,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (full)
            Positioned.fill(
              child: _FullPlayer(version: v, data: data),
            )
          else
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: 10,
              right: 10,
              bottom: hideMini
                  ? -(miniBottom + musicMiniHeight + 20)
                  : miniBottom,
              height: musicMiniHeight,
              child: _MiniBar(version: v, data: data, videoWidth: miniVideoW),
            ),
          AnimatedPositioned.fromRect(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            rect: videoRect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(full ? 14 : 8),
              child: ColoredBox(
                color: Colors.black,
                child: player.bridge.view(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends ConsumerWidget {
  const _MiniBar({
    required this.version,
    required this.data,
    required this.videoWidth,
  });

  final MusicVersion? version;
  final MusicData data;
  final double videoWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final v = version;
    final title = v == null ? '' : data.work(v.workId)?.title ?? v.videoTitle;
    final pct = player.duration <= 0
        ? 0.0
        : (player.position / player.duration).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () => player.setExpanded(true),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xE61C1C28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Row(
              children: [
                SizedBox(width: videoWidth + 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      if (v != null)
                        Row(
                          children: [
                            MusicTypeBadge(v.type),
                            Expanded(
                              child: Text(
                                data.artistNames(v),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.ink3,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: player.toggle,
                  icon: Icon(
                    player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  color: AppColors.ink,
                  tooltip: player.playing ? '暫停' : '播放',
                ),
                IconButton(
                  onPressed: () => player.next(),
                  icon: const Icon(Icons.skip_next_rounded),
                  color: AppColors.ink,
                  tooltip: '下一首',
                ),
                IconButton(
                  onPressed: player.close,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.ink3,
                  tooltip: '關掉播放器',
                ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              height: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.white12,
                  color: musicPink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(double s) {
  final t = s.isNaN ? 0 : s.floor();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

class _FullPlayer extends ConsumerWidget {
  const _FullPlayer({required this.version, required this.data});

  final MusicVersion? version;
  final MusicData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final v = version;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final work = v == null ? null : data.work(v.workId);
    final others = v == null
        ? <MusicVersion>[]
        : data.versionsOfWork(v.workId).where((x) => x.id != v.id).toList();
    final videoH = player.showVideo
        ? math.min(size.width - 32, 640.0) * 9 / 16
        : 72.0;
    final dur = player.duration > 0
        ? player.duration
        : (v?.durationSec?.toDouble() ?? 0);
    final pos = player.position.clamp(0.0, dur <= 0 ? 0.0 : dur);
    void go(String path) {
      player.setExpanded(false);
      appRouter.push(path);
    }

    return Container(
      color: const Color(0xFF0D0D14),
      child: Stack(
        children: [
          if (v != null && v.thumbnailUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.22,
                child: Image.network(
                  v.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                22,
                mq.padding.top + 8,
                22,
                mq.padding.bottom + 24,
              ),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => player.setExpanded(false),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 30,
                      ),
                      color: AppColors.ink2,
                      tooltip: '收起來',
                    ),
                    Expanded(
                      child: Center(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('看影片')),
                            ButtonSegment(value: false, label: Text('只聽')),
                          ],
                          selected: {player.showVideo},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              player.setShowVideo(s.first),
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.ink2,
                            selectedForegroundColor: AppColors.ink,
                            selectedBackgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: v == null
                          ? null
                          : () {
                              player.setExpanded(false);
                              showMusicVersionMenu(context, ref, v.id);
                            },
                      icon: const Icon(Icons.more_horiz_rounded),
                      color: AppColors.ink2,
                      tooltip: '更多',
                    ),
                  ],
                ),
                // 影片框的位置（真正的播放器疊在上面，見 [MusicPlayerLayer]）。
                SizedBox(height: videoH + 12),
                if (!player.showVideo && v != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Center(
                      child: MusicCover(
                        url: v.thumbnailUrl.replaceAll(
                          'mqdefault',
                          'hqdefault',
                        ),
                        fallback: work?.title ?? '',
                        size: math.min(size.width - 80, 320),
                        radius: 20,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: work == null
                                ? null
                                : () => go('/music/work/${work.id}'),
                            child: Text(
                              work?.title ?? v?.videoTitle ?? '',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (v != null) ...[
                            const SizedBox(height: 2),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                MusicTypeBadge(v.type),
                                for (final aid in v.artistIds)
                                  if (data.artist(aid) != null)
                                    GestureDetector(
                                      onTap: () => go('/music/artist/$aid'),
                                      child: Text(
                                        '${data.artist(aid)!.name}  ',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.ink2,
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                            if (v.note.isNotEmpty)
                              Text(v.note, style: AppText.note),
                            Text(
                              '上傳：${v.uploaderName}・${v.publishedAt.year}',
                              style: AppText.note,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (v != null)
                      IconButton(
                        onPressed: () => MusicActions(ref).toggleLike(v.id),
                        icon: Icon(
                          data.liked.versionIds.contains(v.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 26,
                        ),
                        color: data.liked.versionIds.contains(v.id)
                            ? musicPink
                            : AppColors.ink2,
                        tooltip: '喜歡',
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // 自己畫的進度條：播放器畫在導覽器外面，沒有浮層，內建的
                // Slider 會找不到浮層而出錯（2026-10-19 實測抓到）。
                _SeekBar(
                  value: dur <= 0 ? 0 : pos / dur,
                  onSeek: dur <= 0 ? null : (f) => player.seek(f * dur),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      Text(_fmt(pos), style: AppText.note),
                      const Spacer(),
                      Text(_fmt(dur), style: AppText.note),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: player.toggleShuffle,
                      icon: const Icon(Icons.shuffle_rounded),
                      color: player.shuffle ? musicPink : AppColors.ink2,
                      tooltip: '隨機',
                    ),
                    IconButton(
                      onPressed: player.prev,
                      icon: const Icon(Icons.skip_previous_rounded, size: 34),
                      color: Colors.white,
                      tooltip: '上一首',
                    ),
                    IconButton.filled(
                      onPressed: player.toggle,
                      icon: Icon(
                        player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(68, 68),
                      ),
                      tooltip: player.playing ? '暫停' : '播放',
                    ),
                    IconButton(
                      onPressed: () => player.next(),
                      icon: const Icon(Icons.skip_next_rounded, size: 34),
                      color: Colors.white,
                      tooltip: '下一首',
                    ),
                    IconButton(
                      onPressed: player.cycleRepeat,
                      icon: Icon(
                        player.repeat == 2
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                      ),
                      color: player.repeat > 0 ? musicPink : AppColors.ink2,
                      tooltip: ['不重複', '重複整個佇列', '重複這一首'][player.repeat],
                    ),
                  ],
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '這首歌的其他版本',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  for (final o in others)
                    MusicVersionTile(
                      version: o,
                      queue: [
                        for (final x in data.versionsOfWork(o.workId)) x.id,
                      ],
                      byWho: true,
                      from: '播放器・這首歌的其他版本',
                    ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'iPhone 網頁版鎖螢幕或切到別的 App 就會停（Apple 對網頁的限制）。'
                    '第一首要在影片上點一下播放，之後會自動接下一首。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 進度條：點或拖到哪就跳到哪。
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.value, required this.onSeek});

  /// 0～1。
  final double value;
  final ValueChanged<double>? onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final v = (_drag ?? widget.value).clamp(0.0, 1.0);
      double at(Offset p) => (p.dx / w).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onSeek == null
            ? null
            : (d) => widget.onSeek!(at(d.localPosition)),
        onHorizontalDragUpdate: widget.onSeek == null
            ? null
            : (d) => setState(() => _drag = at(d.localPosition)),
        onHorizontalDragEnd: widget.onSeek == null
            ? null
            : (_) {
                widget.onSeek!(_drag ?? widget.value);
                setState(() => _drag = null);
              },
        child: SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Container(
                width: w * v,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Positioned(
                left: (w * v - 7).clamp(0.0, w - 14),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
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
