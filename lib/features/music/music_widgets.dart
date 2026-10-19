import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show appRouter, rootNavigatorKey;
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../yt_tracker/yt_video_row.dart' show openExternalUrl;
import '../../domain/models/music.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import 'music_actions.dart';
import 'music_player.dart';

/// 音樂的主色（設計稿的粉紅）。
const musicPink = Color(0xFFFF6FAE);
const musicSheetBg = Color(0xFF1C1C2A);

/// 次要按鈕（半透明白，不用 App 預設的藍）。
final musicGhostButton = FilledButton.styleFrom(
  backgroundColor: Colors.white.withValues(alpha: 0.12),
  foregroundColor: Colors.white,
);

Color musicTypeColor(MusicVersionType t) => switch (t) {
  MusicVersionType.sing => AppColors.ink2,
  MusicVersionType.duet => const Color(0xFF7EA6FF),
  MusicVersionType.cover => const Color(0xFFC9A6FF),
  MusicVersionType.live => const Color(0xFF5FE08D),
  MusicVersionType.acapella => const Color(0xFFF5C763),
  MusicVersionType.other => AppColors.ink3,
};

class MusicTypeBadge extends StatelessWidget {
  const MusicTypeBadge(this.type, {super.key});

  final MusicVersionType type;

  @override
  Widget build(BuildContext context) {
    final c = musicTypeColor(type);
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.label,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}

/// 縮圖（方的裁中間；寬的 16:9）。抓不到圖就用歌名第一個字。
class MusicCover extends StatelessWidget {
  const MusicCover({
    super.key,
    required this.url,
    required this.fallback,
    this.size = 50,
    this.wide = false,
    this.radius = 8,
  });

  final String url;
  final String fallback;
  final double size;
  final bool wide;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final w = size, h = wide ? size * 9 / 16 : size;
    final placeholder = Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A58), Color(0xFF15151F)],
        ),
      ),
      child: Text(
        fallback.isEmpty ? '♪' : fallback.characters.first,
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w900,
          color: Colors.white70,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: w,
              height: h,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class MusicArtistAvatar extends StatelessWidget {
  const MusicArtistAvatar(this.artist, {super.key, this.size = 50});

  final MusicArtist artist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF5A6BB0), Color(0xFF8E5BC4)],
        ),
      ),
      child: Text(
        artist.name.isEmpty ? '?' : artist.name.characters.first,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
    if (artist.avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        artist.avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// 一列版本。[byWho]：在歌曲頁時主字是誰唱的，不然主字是歌名。
class MusicVersionTile extends ConsumerWidget {
  const MusicVersionTile({
    super.key,
    required this.version,
    required this.queue,
    this.byWho = false,
    this.rank,
  });

  final MusicVersion version;

  /// 點這一列時要播的整份清單（從這首開始）。
  final List<String> queue;
  final bool byWho;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final player = ref.watch(musicPlayerProvider);
    final v = version;
    final work = data.work(v.workId);
    final title = work?.title ?? v.videoTitle;
    final names = data.artistNames(v);
    final now = player.current == v.id;
    final liked = data.liked.versionIds.contains(v.id);
    final origNames = [
      for (final id in work?.originalArtistIds ?? const <String>[])
        if (!v.artistIds.contains(id)) data.artist(id)?.name ?? '',
    ].where((n) => n.isNotEmpty).join('、');
    final parts = <String>[
      if (byWho) ...[
        if (v.note.isNotEmpty) v.note,
        if (!names.contains(v.uploaderName) && v.uploaderName.isNotEmpty)
          '在「${v.uploaderName}」',
        '${v.publishedAt.year}',
      ] else ...[
        names,
        if (v.type == MusicVersionType.cover && origNames.isNotEmpty)
          '原唱 $origNames',
        if (v.note.isNotEmpty) v.note,
      ],
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => ref.read(musicPlayerProvider).playList(queue, v.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink3,
                  ),
                ),
              ),
            MusicCover(url: v.thumbnailUrl, fallback: title),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    byWho ? (names.isEmpty ? '（沒填誰唱）' : names) : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: now ? musicPink : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      MusicTypeBadge(v.type),
                      Expanded(
                        child: Text(
                          parts.where((p) => p.isNotEmpty).join('・'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.ink3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (liked)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.favorite_rounded, size: 14, color: musicPink),
              ),
            IconButton(
              onPressed: () => showMusicVersionMenu(context, ref, v.id),
              icon: Transform.scale(
                scaleY: 1.25,
                child: const Icon(Icons.more_vert_rounded, size: 24),
              ),
              color: AppColors.ink2,
              tooltip: '更多',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一列歌曲：疊兩張封面、歌名、原唱、幾個版本。
class MusicWorkTile extends ConsumerWidget {
  const MusicWorkTile({super.key, required this.work});

  final MusicWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final vs = data.versionsOfWork(work.id);
    final counts = [
      for (final t in MusicVersionType.values)
        if (vs.any((v) => v.type == t))
          '${t.label} ${vs.where((v) => v.type == t).length}',
    ].join('・');
    final orig = [
      for (final id in work.originalArtistIds) data.artist(id)?.name ?? '',
    ].where((n) => n.isNotEmpty).join('、');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => appRouter.push('/music/work/${work.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                children: [
                  for (var i = 0; i < vs.length && i < 2; i++)
                    Positioned(
                      left: i * 8.0,
                      top: i * 8.0,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.bg, width: 2),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: MusicCover(
                          url: vs[i].thumbnailUrl,
                          fallback: work.title,
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '${orig.isEmpty ? '' : '原唱 $orig・'}${vs.length} 個版本（$counts）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// 底部面板的外框（音樂的樣子）。
Future<T?> showMusicSheet<T>(
  BuildContext context,
  Widget Function(BuildContext) builder,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: musicSheetBg,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: builder(ctx),
      ),
    ),
  ),
);

Widget musicSheetHandle() => Center(
  child: Container(
    width: 40,
    height: 5,
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(9),
    ),
  ),
);

Widget _menuItem(
  IconData icon,
  String label,
  VoidCallback onTap, {
  Color? color,
}) => ListTile(
  leading: Icon(icon, color: color ?? AppColors.ink2),
  title: Text(label, style: TextStyle(color: color ?? AppColors.ink)),
  dense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
  onTap: onTap,
);

/// 版本的 ⋮ 選單。
Future<void> showMusicVersionMenu(
  BuildContext callerContext,
  WidgetRef ref,
  String id,
) async {
  // 全螢幕播放器畫在導覽器外面，從那裡叫的話用根導覽器的 context 開面板。
  final context = rootNavigatorKey.currentContext ?? callerContext;
  final data = ref.read(musicDataProvider);
  final v = data.version(id);
  if (v == null) return;
  final work = data.work(v.workId);
  final liked = data.liked.versionIds.contains(id);
  final choice = await showMusicSheet<String>(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        musicSheetHandle(),
        Row(
          children: [
            MusicCover(
              url: v.thumbnailUrl,
              fallback: work?.title ?? '',
              size: 46,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work?.title ?? v.videoTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Row(
                    children: [
                      MusicTypeBadge(v.type),
                      Flexible(
                        child: Text(
                          data.artistNames(v),
                          overflow: TextOverflow.ellipsis,
                          style: AppText.note,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _menuItem(
          Icons.edit_rounded,
          '編輯（歌名、備註、種類、誰唱）',
          () => Navigator.pop(ctx, 'edit'),
          color: musicPink,
        ),
        _menuItem(
          Icons.queue_play_next_rounded,
          '下一首播放',
          () => Navigator.pop(ctx, 'next'),
        ),
        _menuItem(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          liked ? '取消喜歡' : '喜歡',
          () => Navigator.pop(ctx, 'like'),
        ),
        _menuItem(
          Icons.playlist_add_rounded,
          '加到歌單…',
          () => Navigator.pop(ctx, 'list'),
        ),
        if (work != null)
          _menuItem(
            Icons.library_music_rounded,
            '這首歌的所有版本（${data.versionsOfWork(work.id).length}）',
            () => Navigator.pop(ctx, 'work'),
          ),
        for (final aid in v.artistIds)
          if (data.artist(aid) != null)
            _menuItem(
              Icons.person_rounded,
              '去 ${data.artist(aid)!.name}',
              () => Navigator.pop(ctx, 'artist:$aid'),
            ),
        _menuItem(
          Icons.open_in_new_rounded,
          '在 YouTube 開啟',
          () => Navigator.pop(ctx, 'yt'),
        ),
        _menuItem(
          Icons.delete_outline_rounded,
          '從音樂刪掉',
          () => Navigator.pop(ctx, 'delete'),
          color: const Color(0xFFFF7A7A),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final player = ref.read(musicPlayerProvider);
  switch (choice) {
    case 'edit':
      await showMusicEditVersionSheet(context, ref, id);
    case 'next':
      player.playNext(id);
      showAppNotice(context, '下一首播放');
    case 'like':
      await MusicActions(ref).toggleLike(id);
    case 'list':
      await showMusicAddToPlaylistSheet(context, ref, id);
    case 'work':
      player.setExpanded(false);
      appRouter.push('/music/work/${v.workId}');
    case 'yt':
      await openExternalUrl(context, 'https://www.youtube.com/watch?v=$id');
    case 'delete':
      final ok = await showAppConfirmDialog(
        context,
        title: '從音樂刪掉？',
        message: '只刪音樂裡這一份，YT 管理的影片不動。',
        confirmLabel: '刪掉',
        cancelLabel: '取消',
      );
      if (ok) {
        await MusicActions(ref).deleteVersion(id);
        player.removeFromQueue(id);
      }
    default:
      if (choice.startsWith('artist:')) {
        player.setExpanded(false);
        if (context.mounted) {
          appRouter.push('/music/artist/${choice.substring(7)}');
        }
      }
  }
}

/// 選誰唱的（可以好幾個；可以打名字新增）。回傳選好的歌手 id。
class MusicArtistPicker extends ConsumerStatefulWidget {
  const MusicArtistPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.newNames = const [],
    this.onNewNamesChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// 還沒建立的新歌手名字（存的時候才建立）。
  final List<String> newNames;
  final ValueChanged<List<String>>? onNewNamesChanged;

  @override
  ConsumerState<MusicArtistPicker> createState() => _MusicArtistPickerState();
}

class _MusicArtistPickerState extends ConsumerState<MusicArtistPicker> {
  @override
  Widget build(BuildContext context) {
    final artists = ref.watch(musicDataProvider).artists
      ..sort((a, b) => a.name.compareTo(b.name));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in artists)
          musicChoiceChip(
            a.name,
            widget.selected.contains(a.id),
            () => widget.onChanged(
              widget.selected.contains(a.id)
                  ? widget.selected.where((x) => x != a.id).toList()
                  : [...widget.selected, a.id],
            ),
          ),
        for (final n in widget.newNames)
          musicChoiceChip(
            '$n（新歌手）✕',
            true,
            () => widget.onNewNamesChanged?.call(
              widget.newNames.where((x) => x != n).toList(),
            ),
          ),
        if (widget.onNewNamesChanged != null)
          musicChoiceChip('＋ 新歌手', false, () async {
            final n = await promptMusicText(context, title: '新歌手的名字');
            if (n != null && n.isNotEmpty) {
              widget.onNewNamesChanged!([...widget.newNames, n]);
            }
          }, dashed: true),
      ],
    );
  }
}

Widget musicChoiceChip(
  String label,
  bool on,
  VoidCallback onTap, {
  bool dashed = false,
}) => GestureDetector(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: on
          ? Colors.white
          : (dashed ? null : Colors.white.withValues(alpha: 0.08)),
      borderRadius: BorderRadius.circular(99),
      border: dashed ? Border.all(color: AppColors.ink3) : null,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: on ? FontWeight.w800 : FontWeight.w500,
        color: on ? const Color(0xFF111111) : AppColors.ink2,
      ),
    ),
  ),
);

Widget musicFieldLabel(String t) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Text(
    t,
    style: const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppColors.ink3,
    ),
  ),
);

InputDecoration musicInputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.ink3),
  isDense: true,
  filled: true,
  fillColor: Colors.white.withValues(alpha: 0.08),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
);

Future<String?> promptMusicText(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: musicSheetBg,
      title: Text(
        title,
        style: const TextStyle(color: AppColors.ink, fontSize: 17),
      ),
      content: TextField(
        controller: c,
        autofocus: true,
        style: const TextStyle(color: AppColors.ink),
        decoration: musicInputDecoration(''),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: musicPink),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

/// 編輯一個版本：歌名（改了等於換到那首歌）、備註、種類、誰唱。
Future<void> showMusicEditVersionSheet(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final data = ref.read(musicDataProvider);
  final v = data.version(id);
  if (v == null) return;
  final work = data.work(v.workId);
  final titleC = TextEditingController(text: work?.title ?? '');
  final noteC = TextEditingController(text: v.note);
  var type = v.type;
  var artists = List<String>.of(v.artistIds);
  var newNames = <String>[];
  final saved = await showMusicSheet<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          musicSheetHandle(),
          const Text(
            '編輯',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _VideoPreview(
            thumbnailUrl: v.thumbnailUrl,
            title: v.videoTitle,
            sub: '「${v.uploaderName}」上傳・${v.publishedAt.year}',
          ),
          musicFieldLabel('歌名'),
          TextField(
            controller: titleC,
            style: const TextStyle(color: AppColors.ink, fontSize: 15),
            decoration: musicInputDecoration('例如：晴天'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '改成別首的歌名＝搬到那首歌底下（同名的會自動併在一起）',
              style: TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ),
          musicFieldLabel('備註（選填）'),
          TextField(
            controller: noteC,
            style: const TextStyle(color: AppColors.ink),
            decoration: musicInputDecoration('例如：2019 演唱會、鋼琴版'),
          ),
          musicFieldLabel('這一版是'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in MusicVersionType.values)
                musicChoiceChip(t.label, type == t, () => setS(() => type = t)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              type.hint,
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ),
          musicFieldLabel('誰唱的（可以好幾個）'),
          MusicArtistPicker(
            selected: artists,
            onChanged: (x) => setS(() => artists = x),
            newNames: newNames,
            onNewNamesChanged: (x) => setS(() => newNames = x),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: musicPink,
              foregroundColor: const Color(0xFF2A0614),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              '儲存',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final actions = MusicActions(ref);
  final ids = [...artists];
  for (final n in newNames) {
    ids.add(await actions.ensureArtist(n));
  }
  await actions.editVersion(id, type: type, artistIds: ids, note: noteC.text);
  final t = titleC.text.trim();
  if (t.isNotEmpty && t != work?.title) {
    // 這首歌只有這一個版本：直接改歌名；有別的版本：搬到新歌名（或併到同名的）。
    final only =
        ref.read(musicDataProvider).versionsOfWork(v.workId).length == 1;
    final exists = ref.read(musicDataProvider).works.any((w) => w.title == t);
    if (only && !exists && work != null) {
      await actions.editWork(work.id, title: t);
    } else {
      await actions.moveVersionToTitle(id, t);
    }
  }
  if (context.mounted) showAppNotice(context, '已儲存');
}

/// 加到歌單（可以勾好幾個、可以新增）。
Future<void> showMusicAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  String versionId,
) => showMusicSheet<void>(
  context,
  (ctx) => Consumer(
    builder: (ctx, ref, _) {
      final data = ref.watch(musicDataProvider);
      final lists = [data.liked, ...data.playlists.where((p) => !p.isLiked)];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          musicSheetHandle(),
          const Text(
            '加到歌單',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in lists)
            CheckboxListTile(
              value: p.versionIds.contains(versionId),
              onChanged: (_) =>
                  MusicActions(ref).togglePlaylistItem(p.id, versionId),
              title: Text(
                p.isLiked ? '♥ 喜歡的歌' : p.name,
                style: const TextStyle(color: AppColors.ink),
              ),
              secondary: Text('${p.versionIds.length}', style: AppText.note),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: musicPink,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          TextButton.icon(
            onPressed: () async {
              final n = await promptMusicText(ctx, title: '新歌單的名字');
              if (n == null || n.isEmpty) return;
              final actions = MusicActions(ref);
              final id = await actions.createPlaylist(n);
              await actions.togglePlaylistItem(id, versionId);
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增歌單'),
          ),
        ],
      );
    },
  ),
);

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.thumbnailUrl,
    required this.title,
    required this.sub,
  });

  final String thumbnailUrl;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        MusicCover(url: thumbnailUrl, fallback: title, size: 96, wide: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.ink2),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 給「加到音樂功能」用的影片預覽（同一個樣子）。
Widget musicVideoPreview({
  required String thumbnailUrl,
  required String title,
  required String sub,
}) => _VideoPreview(thumbnailUrl: thumbnailUrl, title: title, sub: sub);
