import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/music.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'music_actions.dart';
import 'music_add_from_yt.dart';
import 'music_play.dart';
import 'music_widgets.dart';

/// 音樂功能（2026-10-19，設計稿
/// `design-history/已選擇完成/音樂功能設計/2026-10-19_音樂功能最終版.html`，
/// 照第 1 版「音樂庫分頁」）：首頁／搜尋／音樂庫三格（底部分頁列），歌手頁、
/// 歌曲頁、歌單頁疊在上面。播放器在整個 App 最上層（見 `music_player_layer.dart`）。
class MusicScaffold extends StatelessWidget {
  const MusicScaffold({super.key, required this.child, this.showDrawer = true});

  final Widget child;
  final bool showDrawer;

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: showDrawer ? const AppSideDrawer() : null,
    backgroundColor: const Color(0xFF0E0E16),
    body: Stack(
      children: [
        // 上面一抹藍光（設計稿第 1 版）。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -1),
                  radius: 1.1,
                  colors: [
                    const Color(0xFF3B6FB6).withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(bottom: false, child: child),
      ],
    ),
  );
}

/// 每頁最下面要空出來的高度：底部分頁列＋迷你播放列。
double musicBottomInset(BuildContext context) =>
    FloatingNavInset.of(context) + Gap.lg;

Widget _h2(String t, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 20, bottom: 8),
  child: Row(
    children: [
      Expanded(
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
      ?trailing,
    ],
  ),
);

Widget _more(String label, VoidCallback onTap) => GestureDetector(
  onTap: onTap,
  child: Text(
    label,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.ink2,
    ),
  ),
);

Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.only(right: 7),
  child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? Colors.white : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: on ? Colors.white : Colors.white.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          color: on ? const Color(0xFF111111) : AppColors.ink,
        ),
      ),
    ),
  ),
);

Widget _chips(List<Widget> chips) => SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(children: chips),
);

/// 空的音樂庫：怎麼開始。
class MusicEmpty extends StatelessWidget {
  const MusicEmpty({super.key, this.title = '還沒有歌'});

  /// 首頁是拿歌拼出來的（最近加的、快速選曲…），沒歌就說「還沒有歌」；
  /// 音樂庫頁才說「音樂庫還是空的」。
  final String title;

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String sub) => Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: musicPink,
            child: Text(
              '$n',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2A0614),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Text(sub, style: AppText.note),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Text('🎵', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text('歌是你自己加的', style: AppText.note),
          step(1, '去 YT 管理找影片', '任何分類的影片，按 ⋮ →「加到音樂功能」'),
          step(2, '選歌手、確認歌名', '歌名、種類（演唱／翻唱／Live…）會自動猜，可以改'),
          step(3, '開始聽', '點一首就播，播完自動接下一首'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => showMusicAddFromYt(context),
            style: FilledButton.styleFrom(
              backgroundColor: musicPink,
              foregroundColor: const Color(0xFF2A0614),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('從 YT 管理挑'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════ 首頁 ═══════════════

class MusicHomePage extends ConsumerStatefulWidget {
  const MusicHomePage({super.key});

  @override
  ConsumerState<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends ConsumerState<MusicHomePage> {
  MusicVersionType? _type;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(musicDataProvider);
    // 不喜歡的不出現在首頁（2026-10-19）。
    final all = data.playable;
    final hour = DateTime.now().hour;
    final hello = hour < 11
        ? '早安'
        : hour < 18
        ? '午安'
        : '晚安';
    final pool = _type == null
        ? all
        : all.where((v) => v.type == _type).toList();
    final quick = pool.take(16).toList();
    // 最近播放：照播放紀錄，最後一次播的新到舊。
    final log = ref.watch(musicPlayLogProvider);
    final recent = [
      for (final e
          in (log.entries.where((e) => e.value.isNotEmpty).toList()
            ..sort((a, b) => b.value.last.at.compareTo(a.value.last.at))))
        if (data.version(e.key) case final v? when !v.disliked) v,
    ].take(12).toList();
    final hot = data.works.toList()
      ..sort(
        (a, b) => data
            .versionsOfWork(b.id)
            .length
            .compareTo(data.versionsOfWork(a.id).length),
      );
    // 還沒有歌的（剛新增、等著加歌的）排最前面，新增完一回首頁就看得到；
    // 其餘照歌多的在前。
    final artists = data.artists
      ..sort((a, b) {
        final na = data.versionsOfArtist(a.id).length;
        final nb = data.versionsOfArtist(b.id).length;
        if ((na == 0) != (nb == 0)) return na == 0 ? -1 : 1;
        if (na == 0) return b.updatedAt.compareTo(a.updatedAt);
        return nb.compareTo(na);
      });
    // 「你的歌手」一列：沒有任何歌時也要顯示（先新增歌手、再慢慢加歌）。
    final artistSection = <Widget>[
      _h2(
        '你的歌手',
        trailing: _more('全部 ›', () => context.push('/music/library?tab=歌手')),
      ),
      for (final (row, label) in [
        (artists.where((a) => a.gender == 'm').toList(), '男'),
        (artists.where((a) => a.gender == 'f').toList(), '女'),
        (artists.where((a) => a.gender == null).toList(), '還沒填性別（點進去編輯）'),
      ])
        if (row.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    label,
                    style: AppText.note.copyWith(
                      color: label == '男'
                          ? musicGenderColor('m')
                          : (label == '女' ? musicGenderColor('f') : null),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(
                  '/music/library?tab=歌手${label == '男' ? '&g=m' : (label == '女' ? '&g=f' : '')}',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink2,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('全部 ›'),
              ),
            ],
          ),
          SizedBox(
            height: 106,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in row)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => context.push('/music/artist/${a.id}'),
                      child: SizedBox(
                        width: 74,
                        child: Column(
                          children: [
                            MusicArtistAvatar(a, size: 74),
                            const SizedBox(height: 6),
                            Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
    ];
    return MusicScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.screenSide,
          Gap.sm,
          Gap.screenSide,
          musicBottomInset(context),
        ),
        children: [
          AppTopBar(
            title: hello,
            showBack: false,
            actions: [
              IconButton(
                onPressed: () => showMusicAddMenu(context, ref),
                icon: const Icon(Icons.add_rounded),
                color: AppColors.ink2,
                tooltip: '新增',
              ),
            ],
          ),
          if (data.versions.isEmpty) ...[
            const MusicEmpty(),
            if (artists.isNotEmpty) ...artistSection,
          ] else ...[
            const SizedBox(height: Gap.sm),
            // 歌手放第一排（2026-10-21 使用者要求）
            ...artistSection,
            _chips([
              _chip('全部', _type == null, () => setState(() => _type = null)),
              for (final t in MusicVersionType.values)
                if (all.any((v) => v.type == t))
                  _chip(t.label, _type == t, () => setState(() => _type = t)),
            ]),
            if (recent.isNotEmpty) ...[
              _h2('最近播放'),
              SizedBox(
                height: 186,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final v in recent)
                      _RecentTile(
                        version: v,
                        queue: [for (final x in recent) x.id],
                      ),
                  ],
                ),
              ),
            ],
            _h2('最近加的'),
            SizedBox(
              height: 186,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final v in all.take(10))
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => musicPlay(
                          context,
                          ref,
                          [for (final x in all) x.id],
                          v.id,
                          from: '首頁・最近加的',
                        ),
                        child: SizedBox(
                          width: 132,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MusicCover(
                                url: v.thumbnailUrl,
                                fallback: data.work(v.workId)?.title ?? '',
                                size: 132,
                                radius: 10,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                data.work(v.workId)?.title ?? v.videoTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              Row(
                                children: [
                                  MusicTypeBadge(v.type),
                                  Expanded(
                                    child: Text(
                                      data.artistNames(v),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _h2(
              '快速選曲',
              trailing: _more(
                '全部播放',
                () => musicPlay(
                  context,
                  ref,
                  [for (final v in quick) v.id],
                  quick.first.id,
                  from: '首頁・快速選曲・全部播放',
                ),
              ),
            ),
            for (final v in quick)
              MusicVersionTile(
                version: v,
                queue: [for (final x in quick) x.id],
                from: '首頁・快速選曲',
              ),
            if (hot.any((w) => data.versionsOfWork(w.id).length > 1)) ...[
              _h2('很多人唱過的歌'),
              for (final w
                  in hot
                      .where((w) => data.versionsOfWork(w.id).length > 1)
                      .take(5))
                MusicWorkTile(work: w),
            ],
          ],
        ],
      ),
    );
  }
}

// ═══════════════ 搜尋 ═══════════════

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(musicDataProvider);
    final q = _c.text.trim().toLowerCase();
    final artists = q.isEmpty
        ? <MusicArtist>[]
        : data.artists.where((a) => a.name.toLowerCase().contains(q)).toList();
    final works = q.isEmpty
        ? <MusicWork>[]
        : data.works.where((w) => w.title.toLowerCase().contains(q)).toList();
    final versions = q.isEmpty
        ? <MusicVersion>[]
        : data.versions
              .where(
                (v) => [
                  data.work(v.workId)?.title ?? '',
                  data.artistNames(v),
                  v.note,
                  v.type.label,
                  v.uploaderName,
                ].join(' ').toLowerCase().contains(q),
              )
              .toList();
    final ids = [for (final v in versions) v.id];
    return MusicScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.screenSide,
          Gap.sm,
          Gap.screenSide,
          musicBottomInset(context),
        ),
        children: [
          const AppTopBar(title: '搜尋', showBack: false),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _c,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.ink, fontSize: 15),
            decoration: musicInputDecoration('歌名、歌手、備註').copyWith(
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.ink3,
              ),
            ),
          ),
          if (q.isEmpty) ...[
            _h2('試試看'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final t in [
                  ...data.works.take(3).map((w) => w.title),
                  ...data.artists.take(2).map((a) => a.name),
                  '翻唱',
                ])
                  _chip(t, false, () {
                    _c.text = t;
                    setState(() {});
                  }),
              ],
            ),
          ] else ...[
            if (artists.isNotEmpty) ...[
              _h2('歌手'),
              for (final a in artists)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MusicArtistAvatar(a, size: 48),
                  title: Text(
                    a.name,
                    style: const TextStyle(color: AppColors.ink),
                  ),
                  subtitle: Text(
                    '${data.versionsOfArtist(a.id).length} 首',
                    style: AppText.note,
                  ),
                  onTap: () => context.push('/music/artist/${a.id}'),
                ),
            ],
            if (works.isNotEmpty) ...[
              _h2('歌曲'),
              for (final w in works) MusicWorkTile(work: w),
            ],
            if (versions.isNotEmpty) ...[
              _h2('版本'),
              for (final v in versions)
                MusicVersionTile(version: v, queue: ids, from: '搜尋'),
            ],
            if (artists.isEmpty && works.isEmpty && versions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(
                  children: [
                    Text('音樂裡沒有「${_c.text.trim()}」', style: AppText.bodyDim),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: musicGhostButton,
                      onPressed: () => showMusicAddFromYt(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('從 YT 管理挑'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════ 音樂庫 ═══════════════

class MusicLibraryPage extends ConsumerStatefulWidget {
  const MusicLibraryPage({super.key, this.initialTab, this.initialGender});

  final String? initialTab;

  /// 歌手那一頁先篩哪個性別（'m'／'f'，首頁男女兩排的「全部」帶過來）。
  final String? initialGender;

  @override
  ConsumerState<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends ConsumerState<MusicLibraryPage> {
  static const _tabs = ['歌單', '喜歡的歌', '歌手', '歌曲', '不喜歡'];

  /// 歌手篩性別：null 全部、'm' 男、'f' 女（2026-10-21 使用者要求）。
  late String? _g = widget.initialGender;
  late String _tab = _tabs.contains(widget.initialTab)
      ? widget.initialTab!
      : '歌手';

  @override
  void didUpdateWidget(MusicLibraryPage old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab &&
        _tabs.contains(widget.initialTab)) {
      _tab = widget.initialTab!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(musicDataProvider);
    final children = <Widget>[];
    switch (_tab) {
      case '歌單':
        final lists = data.playlists.where((p) => !p.isLiked).toList();
        children.addAll([
          _PlaylistTile(playlist: data.liked),
          for (final p in lists) _PlaylistTile(playlist: p),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.glassEdge, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.ink2),
            ),
            title: const Text('新增歌單', style: TextStyle(color: AppColors.ink)),
            onTap: () async {
              final n = await promptMusicText(context, title: '新歌單的名字');
              if (n != null && n.isNotEmpty) {
                await MusicActions(ref).createPlaylist(n);
              }
            },
          ),
        ]);
      case '喜歡的歌':
        final vs = [for (final id in data.liked.versionIds) ?data.version(id)];
        children.addAll(
          vs.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('還沒有，在歌的 ⋮ 按「喜歡」', style: AppText.note),
                    ),
                  ),
                ]
              : [
                  for (final v in vs)
                    MusicVersionTile(
                      version: v,
                      queue: [for (final x in vs) x.id],
                      from: '喜歡的歌',
                    ),
                ],
        );
      case '不喜歡':
        // 不做刪除：不想聽的都在這裡，⋮ 可以取消（2026-10-19）。
        final vs = data.disliked;
        children.addAll(
          vs.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        '沒有。不想聽的歌在 ⋮ 按「不喜歡」，會收到這裡',
                        style: AppText.note,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '不會出現在首頁、也不會被排進播放全部／隨機；⋮ 可以取消',
                      style: AppText.note,
                    ),
                  ),
                  for (final v in vs)
                    MusicVersionTile(version: v, queue: [v.id], from: '不喜歡'),
                ],
        );
      case '歌手':
        final artists =
            data.artists.where((a) => _g == null || a.gender == _g).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        children.addAll([
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              children: [
                musicChoiceChip(
                  '全部性別',
                  _g == null,
                  () => setState(() => _g = null),
                ),
                musicChoiceChip(
                  '男',
                  _g == 'm',
                  () => setState(() => _g = 'm'),
                  color: musicGenderColor('m'),
                ),
                musicChoiceChip(
                  '女',
                  _g == 'f',
                  () => setState(() => _g = 'f'),
                  color: musicGenderColor('f'),
                ),
              ],
            ),
          ),
          for (final a in artists) _ArtistTile(artist: a),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassEdge, width: 1.5),
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.ink2),
            ),
            title: const Text('新增歌手', style: TextStyle(color: AppColors.ink)),
            subtitle: Text('打名字、貼大頭貼網址', style: AppText.note),
            onTap: () async {
              final r = await promptMusicArtist(context);
              if (r != null) {
                await MusicActions(ref).ensureArtist(
                  r.name,
                  avatarUrls: r.avatarUrls,
                  shownAvatar: r.shownAvatar,
                  gender: r.gender,
                  crops: r.crops,
                );
              }
            },
          ),
        ]);
      case '歌曲':
        final works = data.works..sort((a, b) => a.title.compareTo(b.title));
        children.addAll([
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('一首歌一列，點進去看所有人唱的版本', style: AppText.note),
          ),
          for (final w in works) MusicWorkTile(work: w),
        ]);
    }
    return MusicScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.screenSide,
          Gap.sm,
          Gap.screenSide,
          musicBottomInset(context),
        ),
        children: [
          AppTopBar(
            title: '音樂庫',
            // 音樂庫：左上角是返回（2026-10-21 使用者要求，不是選單）；沒有上一頁就回音樂首頁
            onBack: () =>
                context.canPop() ? context.pop() : context.go('/music'),
            actions: [
              IconButton(
                onPressed: () => context.push('/music/log'),
                icon: const Icon(Icons.history_rounded),
                color: AppColors.ink2,
                tooltip: '異動紀錄',
              ),
              IconButton(
                onPressed: () => showMusicAddMenu(context, ref),
                icon: const Icon(Icons.add_rounded),
                color: AppColors.ink2,
                tooltip: '新增',
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          _chips([
            for (final t in _tabs)
              _chip(t, _tab == t, () => setState(() => _tab = t)),
          ]),
          const SizedBox(height: Gap.sm),
          if (data.versions.isEmpty && _tab != '歌單')
            const MusicEmpty(title: '音樂庫還是空的')
          else
            ...children,
        ],
      ),
    );
  }
}

class _ArtistTile extends ConsumerWidget {
  const _ArtistTile({required this.artist});

  final MusicArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final vs = data.versionsOfArtist(artist.id);
    final counts = [
      for (final t in MusicVersionType.values)
        if (vs.any((v) => v.type == t))
          '${t.label} ${vs.where((v) => v.type == t).length}',
    ].join('・');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: MusicArtistAvatar(artist, size: 50),
      title: Text(
        artist.name,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        vs.isEmpty ? '還沒有歌' : '${vs.length} 首・$counts',
        style: AppText.note,
      ),
      onTap: () => context.push('/music/artist/${artist.id}'),
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({required this.playlist});

  final MusicPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final first = playlist.versionIds
        .map(data.version)
        .whereType<MusicVersion>()
        .firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: playlist.isLiked
          ? Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [musicPink, Color(0xFF7E5BFF)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white),
            )
          : MusicCover(url: first?.thumbnailUrl ?? '', fallback: playlist.name),
      title: Text(
        playlist.isLiked ? '喜歡的歌' : playlist.name,
        style: const TextStyle(color: AppColors.ink),
      ),
      subtitle: Text(
        '${playlist.isLiked ? '' : '歌單・'}${playlist.versionIds.length} 首',
        style: AppText.note,
      ),
      onTap: () => context.push('/music/list/${playlist.id}'),
    );
  }
}

// ═══════════════ 歌手頁 ═══════════════

class MusicArtistPage extends ConsumerStatefulWidget {
  const MusicArtistPage({super.key, required this.artistId});

  final String artistId;

  @override
  ConsumerState<MusicArtistPage> createState() => _MusicArtistPageState();
}

class _MusicArtistPageState extends ConsumerState<MusicArtistPage> {
  MusicVersionType? _type;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(musicDataProvider);
    final a = data.artist(widget.artistId);
    if (a == null) {
      return const MusicScaffold(
        showDrawer: false,
        child: Column(
          children: [
            AppTopBar(title: '歌手'),
            Expanded(child: Center(child: Text('找不到這個歌手'))),
          ],
        ),
      );
    }
    final everything = data.versionsOfArtist(a.id);
    // 不喜歡的放最下面那一區，不排進播放（2026-10-19）。
    final vs = everything.where((v) => !v.disliked).toList();
    final bad = everything.where((v) => v.disliked).toList();
    final ids = [for (final v in vs) v.id];
    // 熱門：照播放次數（播放紀錄），一樣多的話按過喜歡的先、再來新加的
    // （2026-10-21 使用者：熱門沒照播放次數排——原本只是照加進來的順序取前五）。
    final plays = ref.watch(musicPlayLogProvider);
    final likedIds = data.liked.versionIds.toSet();
    final hot = [...vs]
      ..sort((x, y) {
        final c = (plays[y.id]?.length ?? 0).compareTo(
          plays[x.id]?.length ?? 0,
        );
        if (c != 0) return c;
        final l =
            (likedIds.contains(y.id) ? 1 : 0) -
            (likedIds.contains(x.id) ? 1 : 0);
        if (l != 0) return l;
        return y.addedAt.compareTo(x.addedAt);
      });
    final shown = _type == null
        ? vs
        : vs.where((v) => v.type == _type).toList();
    final own = data.worksByOriginal(a.id);
    final hero = everything.where((v) => v.thumbnailUrl.isNotEmpty).firstOrNull;
    // 搜尋（2026-10-21 使用者要求）：先找這個歌手的歌；他沒有的話，也列出其他歌手的，照歌手分段
    final q = _q.text.trim().toLowerCase();
    bool hit(MusicVersion v) =>
        (data.work(v.workId)?.title ?? '').toLowerCase().contains(q) ||
        v.videoTitle.toLowerCase().contains(q) ||
        v.note.toLowerCase().contains(q);
    final mine = q.isEmpty ? <MusicVersion>[] : vs.where(hit).toList();
    final others = <MusicArtist, List<MusicVersion>>{};
    if (q.isNotEmpty) {
      for (final o in data.artists) {
        if (o.id == a.id) continue;
        final l = data
            .versionsOfArtist(o.id)
            .where((v) => !v.disliked && !v.artistIds.contains(a.id) && hit(v))
            .toList();
        if (l.isNotEmpty) others[o] = l;
      }
    }
    return MusicScaffold(
      showDrawer: false,
      child: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(bottom: musicBottomInset(context)),
            children: [
              // 大圖（第 1 版的歌手頁）：用他第一首歌的縮圖。
              SizedBox(
                height: 270,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hero != null)
                      Image.network(
                        hero.thumbnailUrl.replaceAll('mqdefault', 'hqdefault'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xFF0E0E16)],
                          stops: [0.35, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 4,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black38,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      bottom: 14,
                      right: 18,
                      child: Row(
                        children: [
                          MusicArtistAvatar(a, size: 56),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.name,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${vs.length} 首・原唱 ${own.length} 首',
                                  style: AppText.note,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: AppColors.ink),
                      decoration: musicInputDecoration('搜${a.name}的歌').copyWith(
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.ink3,
                        ),
                        suffixIcon: _q.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => setState(_q.clear),
                                icon: const Icon(Icons.cancel_rounded),
                                color: AppColors.ink3,
                              ),
                      ),
                    ),
                    if (q.isNotEmpty) ...[
                      _h2('${a.name}・${mine.length} 首'),
                      if (mine.isEmpty)
                        Text(
                          '${a.name}沒有「${_q.text.trim()}」',
                          style: AppText.note,
                        ),
                      for (final v in mine)
                        MusicVersionTile(
                          bigCover: true,
                          version: v,
                          queue: [for (final x in mine) x.id],
                          from: '歌手頁「${a.name}」・搜尋',
                        ),
                      for (final e in others.entries) ...[
                        _h2('其他歌手：${e.key.name}・${e.value.length} 首'),
                        for (final v in e.value)
                          MusicVersionTile(
                            bigCover: true,
                            version: v,
                            queue: [for (final x in e.value) x.id],
                            from: '歌手頁「${a.name}」・搜尋其他歌手',
                          ),
                      ],
                      if (mine.isEmpty && others.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('其他歌手也沒有', style: AppText.note),
                        ),
                      const Divider(height: 28, color: Color(0x22FFFFFF)),
                    ],
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: vs.isEmpty
                              ? null
                              : () => musicPlay(
                                  context,
                                  ref,
                                  ids,
                                  ids.first,
                                  shuffle: true,
                                  from: '歌手頁「${a.name}」',
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: musicPink,
                            foregroundColor: const Color(0xFF2A0614),
                          ),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('隨機播放'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: musicGhostButton,
                          onPressed: vs.isEmpty
                              ? null
                              : () => musicPlay(
                                  context,
                                  ref,
                                  ids,
                                  ids.first,
                                  from: '歌手頁「${a.name}」・播放',
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放'),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () async {
                            final r = await promptMusicArtist(
                              context,
                              name: a.name,
                              avatarUrls: a.avatarUrls,
                              shownAvatar: a.shownAvatar,
                              gender: a.gender,
                              crops: a.crops,
                            );
                            if (r != null) {
                              await MusicActions(ref).updateArtist(
                                a.id,
                                name: r.name,
                                avatarUrls: r.avatarUrls,
                                shownAvatar: r.shownAvatar,
                                gender: r.gender,
                                crops: r.crops,
                              );
                            }
                          },
                          icon: const Icon(Icons.edit_rounded),
                          color: AppColors.ink2,
                          tooltip: '編輯',
                        ),
                      ],
                    ),
                    if (vs.isNotEmpty) ...[
                      _h2('熱門'),
                      // 左右滑（2026-10-21 使用者：一整排往下太長，看不到下面）
                      SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: math.min(10, hot.length),
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => MusicHotCard(
                            version: hot[i],
                            rank: i + 1,
                            plays: plays[hot[i].id]?.length ?? 0,
                            queue: [for (final v in hot) v.id],
                            from: '歌手頁「${a.name}」・熱門',
                          ),
                        ),
                      ),
                      _h2('他唱的・全部 ${vs.length}'),
                      _chips([
                        _chip(
                          '全部 ${vs.length}',
                          _type == null,
                          () => setState(() => _type = null),
                        ),
                        for (final t in MusicVersionType.values)
                          if (vs.any((v) => v.type == t))
                            _chip(
                              '${t.label} ${vs.where((v) => v.type == t).length}',
                              _type == t,
                              () => setState(() => _type = t),
                            ),
                      ]),
                      const SizedBox(height: 6),
                      for (final v in shown)
                        MusicVersionTile(
                          bigCover: true,
                          version: v,
                          queue: [for (final x in shown) x.id],
                          from: '歌手頁「${a.name}」',
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '還沒有歌：到 YT 管理按 ⋮ →「加到音樂功能」',
                          style: AppText.note,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (own.isNotEmpty) ...[
                      _h2('他原唱的歌'),
                      Text('點進去看還有誰唱過', style: AppText.note),
                      for (final w in own) MusicWorkTile(work: w),
                    ],
                    if (bad.isNotEmpty) ...[
                      _h2('不喜歡 ${bad.length}'),
                      Text('記著他有這些歌，但不會被排進播放；⋮ 可以取消', style: AppText.note),
                      for (final v in bad)
                        MusicVersionTile(
                          version: v,
                          queue: [v.id],
                          from: '歌手頁「${a.name}」・不喜歡',
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 幫這個歌手加歌：固定在右上角、不跟著捲走，大一點好按（2026-10-21 使用者要求）
          Positioned(
            right: 12,
            top: 8,
            child: Material(
              color: musicPink,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showMusicAddFromYt(context, forArtistId: a.id),
                child: Tooltip(
                  message: '幫${a.name}添加歌曲',
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(
                      Icons.add_rounded,
                      size: 34,
                      color: Color(0xFF2A0614),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════ 歌曲頁 ═══════════════

class MusicWorkPage extends ConsumerStatefulWidget {
  const MusicWorkPage({super.key, required this.workId});

  final String workId;

  @override
  ConsumerState<MusicWorkPage> createState() => _MusicWorkPageState();
}

class _MusicWorkPageState extends ConsumerState<MusicWorkPage> {
  MusicVersionType? _type;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(musicDataProvider);
    final w = data.work(widget.workId);
    if (w == null) {
      return const MusicScaffold(
        showDrawer: false,
        child: Column(
          children: [
            AppTopBar(title: '歌曲'),
            Expanded(child: Center(child: Text('這首歌已經不在音樂裡了'))),
          ],
        ),
      );
    }
    final everything = data.versionsOfWork(w.id);
    final vs = everything.where((v) => !v.disliked).toList();
    final bad = everything.where((v) => v.disliked).toList();
    final shown = _type == null
        ? vs
        : vs.where((v) => v.type == _type).toList();
    final ids = [for (final v in shown) v.id];
    final singers = {for (final v in everything) ...v.artistIds};
    final orig = [for (final id in w.originalArtistIds) ?data.artist(id)];
    final bg = everything.where((v) => v.thumbnailUrl.isNotEmpty).firstOrNull;
    return MusicScaffold(
      showDrawer: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: musicBottomInset(context)),
        children: [
          Stack(
            children: [
              if (bg != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.35,
                    child: Image.network(
                      bg.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x660E0E16), Color(0xFF0E0E16)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.screenSide,
                  4,
                  Gap.screenSide,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _editWork(w),
                          icon: const Icon(Icons.edit_rounded),
                          color: AppColors.ink2,
                          tooltip: '編輯',
                        ),
                      ],
                    ),
                    Text('歌曲', style: AppText.note),
                    Text(
                      w.title,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (orig.isNotEmpty) ...[
                          Text('原唱 ', style: AppText.note),
                          for (final a in orig)
                            GestureDetector(
                              onTap: () =>
                                  context.push('/music/artist/${a.id}'),
                              child: Text(
                                '${a.name}  ',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                        Text(
                          '${vs.length} 個版本・${singers.length} 個人唱過',
                          style: AppText.note,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: ids.isEmpty
                              ? null
                              : () => musicPlay(
                                  context,
                                  ref,
                                  ids,
                                  ids.first,
                                  from: '歌曲頁《${w.title}》・依序聽',
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: musicPink,
                            foregroundColor: const Color(0xFF2A0614),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('依序聽每個版本'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: musicGhostButton,
                          onPressed: () =>
                              showMusicAddFromYt(context, searchTitle: w.title),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('加版本'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chips([
                  _chip(
                    '全部 ${vs.length}',
                    _type == null,
                    () => setState(() => _type = null),
                  ),
                  for (final t in MusicVersionType.values)
                    if (vs.any((v) => v.type == t))
                      _chip(
                        '${t.label} ${vs.where((v) => v.type == t).length}',
                        _type == t,
                        () => setState(() => _type = t),
                      ),
                ]),
                for (final t in MusicVersionType.values)
                  if (shown.any((v) => v.type == t)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 4),
                      child: Row(
                        children: [
                          MusicTypeBadge(t),
                          Text(
                            t.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.note,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final v in shown.where((v) => v.type == t))
                      MusicVersionTile(
                        version: v,
                        queue: ids,
                        byWho: true,
                        from: '歌曲頁《${w.title}》',
                      ),
                  ],
                if (bad.isNotEmpty) ...[
                  _h2('不喜歡 ${bad.length}'),
                  for (final v in bad)
                    MusicVersionTile(
                      version: v,
                      queue: [v.id],
                      byWho: true,
                      from: '歌曲頁《${w.title}》・不喜歡',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editWork(MusicWork w) async {
    final c = TextEditingController(text: w.title);
    var orig = List<String>.of(w.originalArtistIds);
    final ok = await showMusicSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            musicSheetHandle(),
            const Text(
              '編輯歌曲',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            musicFieldLabel('歌名（這首歌所有版本一起改）'),
            TextField(
              controller: c,
              style: const TextStyle(color: AppColors.ink, fontSize: 15),
              decoration: musicInputDecoration('歌名'),
            ),
            musicFieldLabel('原唱'),
            MusicArtistPicker(
              selected: orig,
              onChanged: (x) => setS(() => orig = x),
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
    if (ok == true) {
      await MusicActions(
        ref,
      ).editWork(w.id, title: c.text, originalArtistIds: orig);
    }
  }
}

// ═══════════════ 歌單頁 ═══════════════

class MusicPlaylistPage extends ConsumerWidget {
  const MusicPlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final p = playlistId == MusicPlaylist.likedId
        ? data.liked
        : data.playlistMap[playlistId];
    final vs = [
      for (final id in p?.versionIds ?? const <String>[]) ?data.version(id),
    ];
    final ids = [for (final v in vs) v.id];
    return MusicScaffold(
      showDrawer: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.screenSide,
          Gap.sm,
          Gap.screenSide,
          musicBottomInset(context),
        ),
        children: [
          AppTopBar(
            title: p == null ? '歌單' : (p.isLiked ? '喜歡的歌' : p.name),
            actions: [
              if (p != null && !p.isLiked)
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.ink2,
                  ),
                  color: musicSheetBg,
                  onSelected: (c) async {
                    if (c == 'del') {
                      final ok = await showAppConfirmDialog(
                        context,
                        title: '刪掉歌單「${p.name}」？',
                        message: '歌還在音樂裡，只是這份歌單不見。',
                        confirmLabel: '刪掉',
                      );
                      if (ok) {
                        await MusicActions(ref).deletePlaylist(p.id);
                        if (context.mounted) Navigator.of(context).maybePop();
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'del', child: Text('刪掉歌單')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            '${vs.length} 首',
            textAlign: TextAlign.center,
            style: AppText.note,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: ids.isEmpty
                    ? null
                    : () => musicPlay(
                        context,
                        ref,
                        ids,
                        ids.first,
                        from:
                            '歌單「${p?.isLiked ?? false ? '喜歡的歌' : p?.name ?? ''}」',
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: musicGhostButton,
                onPressed: ids.isEmpty
                    ? null
                    : () => musicPlay(
                        context,
                        ref,
                        ids,
                        ids.first,
                        shuffle: true,
                        from:
                            '歌單「${p?.isLiked ?? false ? '喜歡的歌' : p?.name ?? ''}」',
                      ),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('隨機'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (vs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '還沒有歌，在歌的 ⋮ 選「加到歌單」',
                style: AppText.note,
                textAlign: TextAlign.center,
              ),
            ),
          for (final v in vs)
            MusicVersionTile(
              version: v,
              queue: ids,
              from: '歌單「${p?.isLiked ?? false ? '喜歡的歌' : p?.name ?? ''}」',
            ),
        ],
      ),
    );
  }
}

class _RecentTile extends ConsumerWidget {
  const _RecentTile({required this.version, required this.queue});

  final MusicVersion version;
  final List<String> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(musicDataProvider);
    final v = version;
    final title = data.work(v.workId)?.title ?? v.videoTitle;
    final n = ref.watch(musicPlayLogProvider)[v.id]?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => musicPlay(context, ref, queue, v.id, from: '首頁・最近播放'),
        child: SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MusicCover(
                url: v.thumbnailUrl,
                fallback: title,
                size: 132,
                radius: 10,
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '${data.artistNames(v)}・播過 $n 次',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════ 異動紀錄 ═══════════════

/// 音樂的全部異動紀錄（2026-10-19）：加了哪首、改了什麼、喜歡、不喜歡、歌單，
/// 新的在上面、一筆都不刪；點有對應歌的那一筆看那首的紀錄。
class MusicEventLogPage extends ConsumerWidget {
  const MusicEventLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(musicEventLogProvider).reversed.toList();
    final data = ref.watch(musicDataProvider);
    String? lastDay;
    final children = <Widget>[];
    for (final e in events) {
      final day = '${e.at.year}/${e.at.month}/${e.at.day}';
      if (day != lastDay) {
        lastDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
            child: Text(day, style: AppText.note),
          ),
        );
      }
      final v = e.versionId == null ? null : data.version(e.versionId!);
      String two(int n) => n.toString().padLeft(2, '0');
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: v == null ? null : () => showMusicPlayLog(context, ref, v.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    '${two(e.at.hour)}:${two(e.at.minute)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.text,
                    style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  ),
                ),
                if (v != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink3,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return MusicScaffold(
      showDrawer: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.screenSide,
          Gap.sm,
          Gap.screenSide,
          musicBottomInset(context),
        ),
        children: [
          const AppTopBar(title: '異動紀錄'),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '加了哪首、改了什麼、喜歡／不喜歡、歌單，一筆都不刪；共 ${events.length} 筆',
              style: AppText.note,
            ),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Text('還沒有異動', style: AppText.note)),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// 音樂右上角「＋」（2026-10-19 使用者要求：要能直接新增歌手，不是只能去
/// 搜影片）：新增歌手／加歌（從 YT 管理挑）／新增歌單。
Future<void> showMusicAddMenu(BuildContext context, WidgetRef ref) async {
  Future<String?>? clip;
  Widget item(
    BuildContext ctx,
    IconData icon,
    String title,
    String sub,
    String v,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      child: Icon(icon, color: musicPink),
    ),
    title: Text(
      title,
      style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(sub, style: AppText.note),
    onTap: () {
      // 添加歌曲：點這一下就讀剪貼簿（iOS 只准點擊當下讀）
      if (v == 'song') clip = readClipboardText();
      Navigator.pop(ctx, v);
    },
  );
  final c = await showMusicSheet<String>(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '新增',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        item(
          ctx,
          Icons.person_add_alt_1_rounded,
          '新增歌手',
          '打名字、貼大頭貼網址',
          'artist',
        ),
        item(
          ctx,
          Icons.library_add_rounded,
          '添加歌曲',
          '從 YT 管理挑影片（任何分類），或打歌名找',
          'song',
        ),
        item(
          ctx,
          Icons.playlist_add_rounded,
          '新增歌單',
          '取個名字，之後在歌的 ⋮ 加進來',
          'list',
        ),
      ],
    ),
  );
  if (c == null || !context.mounted) return;
  switch (c) {
    case 'artist':
      final r = await promptMusicArtist(context);
      if (r == null) return;
      final id = await MusicActions(ref).ensureArtist(
        r.name,
        avatarUrls: r.avatarUrls,
        shownAvatar: r.shownAvatar,
        gender: r.gender,
        crops: r.crops,
      );
      if (context.mounted) context.push('/music/artist/$id');
    case 'song':
      await showMusicAddFromYt(context, clip: clip);
    case 'list':
      final n = await promptMusicText(context, title: '新歌單的名字');
      if (n == null || n.isEmpty) return;
      final id = await MusicActions(ref).createPlaylist(n);
      if (context.mounted) context.push('/music/list/$id');
  }
}
