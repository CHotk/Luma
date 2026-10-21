import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show appRouter, rootNavigatorKey;
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../data/external_link.dart';
import '../../data/repositories/music_play_mode_store.dart';
import '../../data/repositories/music_play_log_store.dart';
import '../../domain/models/music.dart';
import '../../shared/widgets/app_notice.dart';
import 'music_actions.dart';
import 'music_play.dart';
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
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// 歌手大頭貼：先用選的那張，壞了（網址失效、被擋）就照順序換下一張備用的，
/// 全都不行才用名字第一個字（2026-10-19 使用者要求）。
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
    final urls = artist.avatarOrder;
    Widget chain(int i) => i >= urls.length
        ? fallback
        : musicCroppedImage(
            urls[i],
            artist.cropOf(urls[i]),
            size,
            errorBuilder: (_, _, _) => chain(i + 1),
          );
    final ring = musicGenderColor(artist.gender);
    final pic = ClipOval(
      child: SizedBox(width: size, height: size, child: chain(0)),
    );
    if (ring == null || size < 30) return pic;
    // 外圈：男藍、女粉（2026-10-21 使用者要求）
    return Container(
      padding: EdgeInsets.all(size >= 80 ? 3 : 2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: pic,
    );
  }
}

/// 性別的顏色：男藍、女粉（沒填是 null）。
Color? musicGenderColor(String? g) => g == 'm'
    ? const Color(0xFF5AA9FF)
    : (g == 'f' ? const Color(0xFFFF7EB6) : null);

/// 照圓框位置（[左右, 上下, 放大]）畫一張大頭貼。
Widget musicCroppedImage(
  String url,
  List<double> crop,
  double size, {
  ImageErrorWidgetBuilder? errorBuilder,
}) => Transform.translate(
  offset: Offset(crop[0] * size, crop[1] * size),
  child: Transform.scale(
    scale: crop[2],
    child: Image.network(
      url,
      key: ValueKey(url),
      width: size,
      height: size,
      fit: BoxFit.cover,
      // 別的網站的圖常常不給跨網域讀，被擋就改用瀏覽器原生的 <img>
      // 顯示（不然大頭貼網址幾乎都會失敗）。
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: errorBuilder,
    ),
  ),
);

/// 調整大頭貼的圓框（像交友軟體）：拖動、兩指縮放（電腦用滾輪或下面的滑桿），回傳 [左右, 上下, 放大]。
Future<List<double>?> showMusicAvatarCropper(
  BuildContext context,
  String url,
  List<double> crop,
) {
  const box = 260.0;
  var dx = crop[0] * box, dy = crop[1] * box, z = crop[2];
  double z0 = 1;
  Offset p0 = Offset.zero, d0 = Offset.zero;
  return showDialog<List<double>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text(
          '調整大頭貼',
          style: TextStyle(color: AppColors.ink, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('拖動移位置、兩指縮放', style: AppText.note),
            const SizedBox(height: 10),
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  setS(
                    () => z = (z * (e.scrollDelta.dy > 0 ? .95 : 1.05)).clamp(
                      1.0,
                      4.0,
                    ),
                  );
                }
              },
              child: GestureDetector(
                onScaleStart: (d) {
                  z0 = z;
                  p0 = d.focalPoint;
                  d0 = Offset(dx, dy);
                },
                onScaleUpdate: (d) => setS(() {
                  z = (z0 * d.scale).clamp(1.0, 4.0);
                  final o = d0 + (d.focalPoint - p0);
                  final lim = box * (z - 1) / 2 + box * .25;
                  dx = o.dx.clamp(-lim, lim);
                  dy = o.dy.clamp(-lim, lim);
                }),
                child: SizedBox(
                  width: box,
                  height: box,
                  child: Stack(
                    children: [
                      // 圓框外面變暗，看得出最後顯示的範圍
                      ClipRect(
                        child: musicCroppedImage(url, [
                          dx / box,
                          dy / box,
                          z,
                        ], box),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          size: const Size(box, box),
                          painter: _CircleMask(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Slider(
              value: z,
              min: 1,
              max: 4,
              onChanged: (v) => setS(() => z = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => setS(() {
              dx = 0;
              dy = 0;
              z = 1;
            }),
            child: const Text('重設'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, [dx / box, dy / box, z]),
            style: FilledButton.styleFrom(
              backgroundColor: musicPink,
              foregroundColor: const Color(0xFF2A0614),
            ),
            child: const Text('好'),
          ),
        ],
      ),
    ),
  );
}

class _CircleMask extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(0, 0, s.width, s.height);
    c.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(r),
        Path()..addOval(r.deflate(4)),
      ),
      Paint()..color = const Color(0xAA000000),
    );
    c.drawOval(
      r.deflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

/// 熱門那一排的卡片（左右滑，2026-10-21）：大封面、排名、歌名、播放幾次。
class MusicHotCard extends ConsumerWidget {
  const MusicHotCard({
    super.key,
    required this.version,
    required this.rank,
    required this.plays,
    required this.queue,
    this.from = '',
  });

  final MusicVersion version;
  final int rank;
  final int plays;
  final List<String> queue;
  final String from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final v = version;
    final title = data.work(v.workId)?.title ?? v.videoTitle;
    return SizedBox(
      width: 168,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => musicPlay(context, ref, queue, v.id, from: from),
        onLongPress: () => showMusicVersionMenu(context, ref, v.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                MusicCover(
                  url: v.thumbnailUrl,
                  fallback: title,
                  size: 168,
                  wide: true,
                  radius: 10,
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              plays == 0 ? '還沒播過' : '播過 $plays 次',
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
          ],
        ),
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
    this.from = '',
    this.bigCover = false,
  });

  /// 從哪裡點的（記進播放紀錄，例如「歌手頁」「首頁・快速選曲」）。
  final String from;

  /// 封面大張（16:9、跟 YT 管理的影片列一樣大）：歌手頁用（2026-10-21 使用者要求）。
  final bool bigCover;

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
        '${v.year}',
      ] else ...[
        names,
        if (v.type == MusicVersionType.cover && origNames.isNotEmpty)
          '原唱 $origNames',
        if (v.note.isNotEmpty) v.note,
      ],
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => musicPlay(context, ref, queue, v.id, from: from),
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
            bigCover
                ? MusicCover(
                    url: v.thumbnailUrl,
                    fallback: title,
                    size: 128,
                    wide: true,
                    radius: 8,
                  )
                : MusicCover(url: v.thumbnailUrl, fallback: title),
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

/// 音樂的面板（2026-10-19 使用者要求：不要從下面升起來，改成畫面中間的
/// 卡片；四周留空白，點外面就關，右上角也有 ✕）。內容太長在卡片裡捲。
Future<T?> showMusicSheet<T>(
  BuildContext context,
  Widget Function(BuildContext) builder,
) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '關閉',
  barrierColor: const Color(0x99000000),
  transitionDuration: const Duration(milliseconds: 220),
  transitionBuilder: (ctx, anim, _, child) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      scale: Tween(
        begin: 0.94,
        end: 1.0,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
  pageBuilder: (ctx, _, _) {
    final mq = MediaQuery.of(ctx);
    return SafeArea(
      child: Padding(
        // 四周留空白，點得到外面（點外面＝取消）。鍵盤出來時往上讓。
        padding: EdgeInsets.fromLTRB(18, 28, 18, 28 + mq.viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.86,
            ),
            child: _SwipeDownToClose(
              child: Material(
                color: musicSheetBg,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      // 拉到最上面還往下拉＝關掉（見 _SwipeDownToClose）
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: builder(ctx),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.ink3,
                        tooltip: '關閉',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);

/// 往下滑關掉面板（2026-10-21 使用者要求：新增歌手、新增歌曲的視窗要能往下滑取消）。
/// 面板內容已經捲在最上面還繼續往下拉，卡片就跟著手指往下，拉超過 110 放開就關，不夠就彈回去。
class _SwipeDownToClose extends StatefulWidget {
  const _SwipeDownToClose({required this.child});
  final Widget child;
  @override
  State<_SwipeDownToClose> createState() => _SwipeDownToCloseState();
}

class _SwipeDownToCloseState extends State<_SwipeDownToClose> {
  double _dy = 0;
  bool _dragging = false;

  void _end() {
    if (_dy > 110) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _dy = 0);
    }
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is OverscrollNotification &&
              n.overscroll < 0 &&
              n.dragDetails != null) {
            _dragging = true;
            setState(() => _dy = (_dy - n.overscroll).clamp(0, 400));
          } else if (n is ScrollUpdateNotification &&
              _dragging &&
              n.dragDetails != null &&
              (n.scrollDelta ?? 0) > 0 &&
              _dy > 0) {
            setState(() => _dy = (_dy - n.scrollDelta!).clamp(0, 400));
          } else if (n is ScrollEndNotification && _dragging) {
            _end();
          }
          return false;
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: _dragging ? 0 : 180),
          transform: Matrix4.translationValues(0, _dy, 0),
          child: Opacity(
            opacity: (1 - _dy / 500).clamp(.3, 1),
            child: widget.child,
          ),
        ),
      );
}

/// 面板最上面留給 ✕ 的空間（原本是底部面板的拉把）。
Widget musicSheetHandle() => const SizedBox(height: 2);

/// 新增／編輯歌手（2026-10-19 使用者要求）：打名字、直接貼大頭貼網址（最多
/// 5 張，照順序是預設、大頭貼 2～5），每張旁邊即時預覽；點「顯示這張」選要顯示
/// 哪一張，那張壞了就照順序換下一張。回傳 (名字, 網址們, 顯示第幾張)；取消是 null。
Future<
  ({
    String name,
    List<String> avatarUrls,
    int shownAvatar,
    String? gender,
    Map<String, List<double>> crops,
  })?
>
promptMusicArtist(
  BuildContext context, {
  String name = '',
  List<String> avatarUrls = const [],
  int shownAvatar = 0,
  String? gender,
  Map<String, List<double>> crops = const {},
}) {
  var g = gender;
  final cropMap = Map<String, List<double>>.of(crops);
  final nameC = TextEditingController(text: name);
  final urlCs = [
    for (final u in (avatarUrls.isEmpty ? const [''] : avatarUrls))
      TextEditingController(text: u),
  ];
  var shown = shownAvatar.clamp(0, urlCs.length - 1);
  String label(int i) => i == 0 ? '預設' : '大頭貼 ${i + 1}';
  return showMusicSheet<
    ({
      String name,
      List<String> avatarUrls,
      int shownAvatar,
      String? gender,
      Map<String, List<double>> crops,
    })
  >(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final urls = [for (final c in urlCs) c.text.trim()];
        final preview = MusicArtist(
          id: '',
          name: nameC.text.trim().isEmpty ? '?' : nameC.text.trim(),
          avatarUrls: urls,
          shownAvatar: shown,
          gender: g,
          crops: cropMap,
          updatedAt: DateTime(2000),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name.isEmpty ? '新增歌手' : '編輯歌手',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            // 實際會顯示的樣子（選的那張壞了會換下一張）。
            Center(child: MusicArtistAvatar(preview, size: 92)),
            const SizedBox(height: 4),
            Center(
              child: Text(
                urls.any((u) => u.isNotEmpty)
                    ? '顯示：${label(shown)}'
                    : '還沒有大頭貼，先用名字第一個字',
                style: AppText.note,
              ),
            ),
            musicFieldLabel('歌手名稱'),
            TextField(
              controller: nameC,
              autofocus: name.isEmpty,
              onChanged: (_) => setS(() {}),
              style: const TextStyle(color: AppColors.ink, fontSize: 15),
              decoration: musicInputDecoration('例如：周杰倫'),
            ),
            // 性別：首頁歌手分兩排（上男下女），新增時一定要選
            musicFieldLabel(name.isEmpty ? '性別（必填）' : '性別'),
            Wrap(
              spacing: 6,
              children: [
                musicChoiceChip(
                  '男',
                  g == 'm',
                  () => setS(() => g = 'm'),
                  color: musicGenderColor('m'),
                ),
                musicChoiceChip(
                  '女',
                  g == 'f',
                  () => setS(() => g = 'f'),
                  color: musicGenderColor('f'),
                ),
              ],
            ),
            musicFieldLabel(
              '大頭貼網址（直接貼，最多 ${MusicArtist.maxAvatars} 張，壞了照順序換下一張）',
            ),
            for (var i = 0; i < urlCs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // 每一張的小預覽。
                    GestureDetector(
                      onTap: () => setS(() => shown = i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: shown == i ? musicPink : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: MusicArtistAvatar(
                          MusicArtist(
                            id: '',
                            name: '${i + 1}',
                            avatarUrls: [urls[i]],
                            crops: cropMap,
                            updatedAt: DateTime(2000),
                          ),
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: urlCs[i],
                        onChanged: (_) => setS(() {}),
                        keyboardType: TextInputType.url,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                        ),
                        decoration: musicInputDecoration(
                          '${label(i)}：https://…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setS(() => shown = i),
                          child: Text(
                            shown == i ? '● 顯示' : '○ 顯示',
                            key: ValueKey('show$i'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: shown == i ? musicPink : AppColors.ink3,
                            ),
                          ),
                        ),
                        if (urls[i].isNotEmpty)
                          GestureDetector(
                            onTap: () async {
                              final c = await showMusicAvatarCropper(
                                ctx,
                                urls[i],
                                cropMap[urls[i]] ?? const [0, 0, 1],
                              );
                              if (c != null) setS(() => cropMap[urls[i]] = c);
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '調整',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8FD3FF),
                                ),
                              ),
                            ),
                          ),
                        if (urlCs.length > 1)
                          GestureDetector(
                            onTap: () => setS(() {
                              urlCs.removeAt(i);
                              if (shown >= urlCs.length) {
                                shown = urlCs.length - 1;
                              } else if (shown > i) {
                                shown--;
                              }
                            }),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '拿掉',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.ink3,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            if (urlCs.length < MusicArtist.maxAvatars)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setS(() => urlCs.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(label(urlCs.length)),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (nameC.text.trim().isEmpty) {
                  showAppNotice(ctx, '名字不能空白', isError: true);
                  return;
                }
                if (g == null) {
                  showAppNotice(ctx, '請選性別（男／女）', isError: true);
                  return;
                }
                // 空白的欄位不算；顯示的那張跟著移到對的位置。
                final keep = <String>[];
                var shownOut = 0;
                for (var i = 0; i < urlCs.length; i++) {
                  final u = urlCs[i].text.trim();
                  if (u.isEmpty) continue;
                  if (i == shown) shownOut = keep.length;
                  keep.add(u);
                }
                Navigator.pop(ctx, (
                  name: nameC.text.trim(),
                  avatarUrls: keep,
                  shownAvatar: shownOut,
                  gender: g,
                  crops: {
                    for (final u in keep)
                      if (cropMap[u] != null) u: cropMap[u]!,
                  },
                ));
              },
              style: FilledButton.styleFrom(
                backgroundColor: musicPink,
                foregroundColor: const Color(0xFF2A0614),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                name.isEmpty ? '新增' : '儲存',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    ),
  );
}

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
  final plays = ref.read(musicPlayLogProvider)[id] ?? const <MusicPlay>[];
  final events = ref
      .read(musicEventLogProvider)
      .where((e) => e.versionId == id)
      .length;
  final embedded = ref.read(musicPlayModeProvider) == MusicPlayMode.embedded;
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
        // 下一首播放只有 App 內播放才有佇列可以插。
        if (embedded)
          _menuItem(
            Icons.queue_play_next_rounded,
            '下一首播放',
            () => Navigator.pop(ctx, 'next'),
          ),
        _menuItem(
          Icons.history_rounded,
          '紀錄（播放 ${plays.length} 次・異動 $events 筆）',
          () => Navigator.pop(ctx, 'log'),
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
          // 點下去當下就開（等選單關掉再開，手機瀏覽器會擋）
          () {
            openExternalUrlSync('https://www.youtube.com/watch?v=$id');
            Navigator.pop(ctx, 'yt');
          },
        ),
        // 音樂不做刪除（2026-10-19 使用者要求：本意是記這個歌手有哪些歌），
        // 不想聽的放「不喜歡」。
        _menuItem(
          v.disliked
              ? Icons.thumb_up_alt_outlined
              : Icons.thumb_down_alt_outlined,
          v.disliked ? '取消不喜歡' : '不喜歡（不出現在首頁、不會被排進播放）',
          () => Navigator.pop(ctx, 'dislike'),
          color: const Color(0xFFFF9A7A),
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
    case 'log':
      await showMusicPlayLog(context, ref, id);
    case 'list':
      await showMusicAddToPlaylistSheet(context, ref, id);
    case 'work':
      player.setExpanded(false);
      appRouter.push('/music/work/${v.workId}');
    case 'yt':
      break;
    case 'dislike':
      await MusicActions(ref).toggleDislike(id);
      if (context.mounted) {
        showAppNotice(context, v.disliked ? '已取消不喜歡' : '已標成不喜歡（在「不喜歡」那一區找得到）');
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

/// 選誰唱的（可以好幾個）。「＋ 新歌手」打名字、大頭貼網址，當場建好並選上。
class MusicArtistPicker extends ConsumerWidget {
  const MusicArtistPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.allowNew = true,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool allowNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(musicDataProvider).artists
      ..sort((a, b) => a.name.compareTo(b.name));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in artists)
          musicChoiceChip(
            a.name,
            selected.contains(a.id),
            () => onChanged(
              selected.contains(a.id)
                  ? selected.where((x) => x != a.id).toList()
                  : [...selected, a.id],
            ),
          ),
        if (allowNew)
          musicChoiceChip('＋ 新歌手', false, () async {
            final r = await promptMusicArtist(context);
            if (r == null) return;
            final id = await MusicActions(ref).ensureArtist(
              r.name,
              avatarUrls: r.avatarUrls,
              shownAvatar: r.shownAvatar,
              gender: r.gender,
              crops: r.crops,
            );
            onChanged([...selected, id]);
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
  Color? color,
}) => GestureDetector(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: on
          ? (color ?? Colors.white)
          : (dashed ? null : Colors.white.withValues(alpha: 0.08)),
      borderRadius: BorderRadius.circular(99),
      border: dashed
          ? Border.all(color: AppColors.ink3)
          : (color != null && !on
                ? Border.all(color: color.withValues(alpha: .6))
                : null),
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
  final yearC = TextEditingController(text: '${v.year}');
  var type = v.type;
  var artists = List<String>.of(v.artistIds);
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
          musicFieldLabel('發行年份'),
          TextField(
            controller: yearC,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.ink),
            decoration: musicInputDecoration('例如：2003'),
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
  final y = int.tryParse(yearC.text.trim());
  await actions.editVersion(
    id,
    type: type,
    artistIds: ids,
    note: noteC.text,
    releaseYear: y == v.publishedAt.year ? null : y,
    setYear: true,
  );
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

/// 一首歌的紀錄（2026-10-19）：播放紀錄（什麼時候、從哪裡、怎麼播）跟異動
/// 紀錄（加入、改了什麼、喜歡、不喜歡…），新的在上面。
Future<void> showMusicPlayLog(BuildContext context, WidgetRef ref, String id) {
  final data = ref.read(musicDataProvider);
  final v = data.version(id);
  final title = v == null ? '' : data.work(v.workId)?.title ?? v.videoTitle;
  final plays = [...?ref.read(musicPlayLogProvider)[id]]
    ..sort((a, b) => b.at.compareTo(a.at));
  final events = ref
      .read(musicEventLogProvider)
      .where((e) => e.versionId == id)
      .toList()
      .reversed
      .toList();
  return showMusicSheet<void>(
    context,
    (ctx) => DefaultTabController(
      length: 2,
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            musicSheetHandle(),
            Text(
              '紀錄・$title',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            TabBar(
              labelColor: AppColors.ink,
              unselectedLabelColor: AppColors.ink3,
              indicatorColor: musicPink,
              tabs: [
                Tab(text: '播放 ${plays.length}'),
                Tab(text: '異動 ${events.length}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  plays.isEmpty
                      ? Center(child: Text('還沒播過', style: AppText.note))
                      : ListView(
                          children: [
                            for (final p in plays)
                              musicLogLine(
                                p.at,
                                [
                                  p.from,
                                  p.modeLabel,
                                ].where((x) => x.isNotEmpty).join('・'),
                              ),
                          ],
                        ),
                  events.isEmpty
                      ? Center(child: Text('還沒有異動', style: AppText.note))
                      : ListView(
                          children: [
                            for (final e in events) musicLogLine(e.at, e.text),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 紀錄的一行：時間＋內容。
Widget musicLogLine(DateTime t, String text) {
  String two(int n) => n.toString().padLeft(2, '0');
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),
          ),
        ),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: const TextStyle(fontSize: 13.5, color: AppColors.ink2),
          ),
        ),
      ],
    ),
  );
}
