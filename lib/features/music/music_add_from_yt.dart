import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/services/youtube_api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../domain/models/yt_tracker.dart';
import 'add_to_music_sheet.dart';
import 'music_widgets.dart';

/// 音樂這邊按「＋」：從 YT 管理挑影片（2026-10-19）。先選頻道（任何分類都
/// 行），再從那個頻道抓過的影片挑（YT 快取，不花配額）。[searchTitle] 有給
/// （歌曲頁「加版本」）就直接列出所有頻道標題有這個歌名的影片。[forArtistId]
/// 有給（歌手頁右上角 ＋）就是幫那個歌手加歌：加的時候歌手直接選好他。
Future<void> showMusicAddFromYt(
  BuildContext context, {
  String? searchTitle,
  String? forArtistId,
}) => showMusicSheet<void>(
  context,
  (ctx) => SizedBox(
    height: MediaQuery.of(ctx).size.height * 0.78,
    child: _AddFromYt(searchTitle: searchTitle, forArtistId: forArtistId),
  ),
);

class _AddFromYt extends ConsumerStatefulWidget {
  const _AddFromYt({this.searchTitle, this.forArtistId});

  final String? searchTitle;
  final String? forArtistId;

  @override
  ConsumerState<_AddFromYt> createState() => _AddFromYtState();
}

class _AddFromYtState extends ConsumerState<_AddFromYt> {
  List<YtChannel>? _channels;
  YtChannel? _channel;
  List<YoutubeVideo>? _videos;

  /// 歌名搜尋的結果：(影片, 頻道)。
  List<(YoutubeVideo, YtChannel)>? _hits;
  late final _q = TextEditingController(text: widget.searchTitle ?? '');

  /// 貼了 YouTube 網址：查到的那部影片（null＝還沒貼或抓不到）。
  YoutubeVideo? _pasted;
  String? _pastedChannel;
  DateTime? _pastedAt;
  int? _pastedDur;
  String? _pastedNote;
  bool _fetching = false;

  /// 「從 YT 管理挑」（選頻道、打歌名找）展開了沒有。預設收起來，貼網址比較
  /// 常用（2026-10-20 使用者要求）；帶了歌名進來（從歌曲頁找版本）就直接展開。
  late bool _browse = (widget.searchTitle ?? '').trim().isNotEmpty;
  final _url = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await ref.read(ytTrackerRepositoryProvider).loadChannels();
    final live = all.where((c) => c.deletedAt == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    setState(() => _channels = live);
    if ((widget.searchTitle ?? '').isNotEmpty) _search();
  }

  Future<void> _open(YtChannel c) async {
    setState(() {
      _channel = c;
      _videos = null;
    });
    final vs = await YtVideoCacheStore(
      ref.read(keyValueStoreProvider),
    ).load(c.id);
    if (!mounted) return;
    setState(() => _videos = vs);
  }

  /// 貼網址：先用 YT API 金鑰查（有標題、頻道、時長）；沒有金鑰或查不到，
  /// 退而用 YouTube 的 oEmbed（只有標題、頻道），再不行就只用縮圖加手動
  /// 輸入歌名（加的視窗本來就能改歌名）。
  Future<void> _onUrl(String text) async {
    final id = YoutubeApiService.parseVideoId(text);
    if (id == null) {
      setState(() {
        _pasted = null;
        _pastedNote = text.trim().isEmpty ? null : '這不像 YouTube 影片網址';
      });
      return;
    }
    setState(() {
      _fetching = true;
      _pastedNote = null;
    });
    String title = '',
        channel = '',
        thumb = 'https://i.ytimg.com/vi/$id/mqdefault.jpg';
    var at = DateTime.now();
    int? dur;
    String? note;
    try {
      final key = ref.read(ytApiKeyProvider);
      if (key != null && key.isNotEmpty) {
        final info = await YoutubeApiService(key).fetchVideoInfo(id);
        if (info == null) {
          note = '找不到這部影片（可能是私人或已刪除）';
        } else {
          title = info.title;
          channel = info.channelName;
          thumb = info.thumbnailUrl;
          at = info.publishedAt;
          dur = info.duration?.inSeconds;
        }
      } else {
        final r = await http
            .get(
              Uri.https('www.youtube.com', '/oembed', {
                'url': 'https://www.youtube.com/watch?v=$id',
                'format': 'json',
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          title = j['title'] as String? ?? '';
          channel = j['author_name'] as String? ?? '';
        } else {
          note = '查不到影片資料，歌名請自己打';
        }
      }
    } catch (_) {
      note = '查不到影片資料（網路或權限問題），歌名請自己打';
    }
    if (!mounted || YoutubeApiService.parseVideoId(_url.text) != id) return;
    setState(() {
      _fetching = false;
      _pastedNote = note;
      if (note != null && note.startsWith('找不到')) {
        _pasted = null;
        return;
      }
      _pasted = YoutubeVideo(
        videoId: id,
        title: title,
        publishedAt: at,
        thumbnailUrl: thumb,
      );
      _pastedChannel = channel;
      _pastedAt = at;
      _pastedDur = dur;
    });
  }

  /// 貼網址查到的那部影片那一列（跟從 YT 管理挑的一樣長相、一樣按「＋ 加」）。
  Widget _pastedBlock(Set<String> inMusic) {
    final v = _pasted;
    final ch = YtChannel(
      id: '',
      name: _pastedChannel ?? '',
      categoryId: '',
      addedAt: DateTime.now(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _url,
          onChanged: _onUrl,
          style: const TextStyle(color: AppColors.ink),
          decoration: musicInputDecoration('貼 YouTube 影片網址').copyWith(
            prefixIcon: const Icon(Icons.link_rounded, color: AppColors.ink3),
            suffixIcon: _fetching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_pastedNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _pastedNote!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.mid),
            ),
          ),
        if (v != null)
          _videoRow(
            v,
            ch,
            inMusic,
            publishedAt: _pastedAt,
            durationSec: _pastedDur,
          ),
      ],
    );
  }

  /// 所有頻道的快取裡，標題有這幾個字的影片。
  Future<void> _search() async {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty || _channels == null) {
      setState(() => _hits = null);
      return;
    }
    final store = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    final out = <(YoutubeVideo, YtChannel)>[];
    for (final c in _channels!) {
      for (final v in await store.load(c.id)) {
        if (v.title.toLowerCase().contains(q)) out.add((v, c));
      }
    }
    out.sort((a, b) => b.$1.publishedAt.compareTo(a.$1.publishedAt));
    if (mounted) setState(() => _hits = out);
  }

  Widget _videoRow(
    YoutubeVideo v,
    YtChannel c,
    Set<String> inMusic, {
    DateTime? publishedAt,
    int? durationSec,
  }) {
    final has = inMusic.contains(v.videoId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          MusicCover(
            url: v.thumbnailUrl,
            fallback: v.title,
            size: 80,
            wide: true,
            radius: 6,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.title.isEmpty ? '（查不到標題，加的時候自己打歌名）' : v.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                Text(
                  '${c.name}・${v.publishedAt.year}',
                  style: const TextStyle(fontSize: 11, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          has
              ? const Text(
                  '已在音樂',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5FE08D),
                  ),
                )
              : FilledButton(
                  onPressed: () => showAddToMusicSheet(
                    context,
                    ref,
                    videoId: v.videoId,
                    videoTitle: v.title,
                    thumbnailUrl: v.thumbnailUrl,
                    channelName: c.name,
                    channelAvatarUrl: c.avatarImageUrl,
                    publishedAt: publishedAt ?? v.publishedAt,
                    durationSec: durationSec ?? v.duration?.inSeconds,
                    artistId: widget.forArtistId,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: musicPink,
                    foregroundColor: const Color(0xFF2A0614),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('＋ 加'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inMusic = ref.watch(musicVideoIdsProvider);
    final channels = _channels;
    Widget body;
    if (channels == null) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (_hits != null && _channel == null) {
      body = _hits!.isEmpty
          ? Center(
              child: Text(
                'YT 快取裡沒有標題有「${_q.text.trim()}」的影片',
                style: AppText.note,
              ),
            )
          : ListView(
              children: [for (final (v, c) in _hits!) _videoRow(v, c, inMusic)],
            );
    } else if (_channel == null) {
      body = ListView(
        children: [
          for (final c in channels)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.glassFill,
                backgroundImage: c.avatarImageUrl.isEmpty
                    ? null
                    : NetworkImage(c.avatarImageUrl),
                child: c.avatarImageUrl.isEmpty
                    ? Text(c.name.characters.first)
                    : null,
              ),
              title: Text(c.name, style: const TextStyle(color: AppColors.ink)),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink3,
              ),
              onTap: () => _open(c),
            ),
        ],
      );
    } else if (_videos == null) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else {
      body = _videos!.isEmpty
          ? Center(child: Text('這個頻道還沒抓過影片，先到 YT 管理打開它', style: AppText.note))
          : ListView(
              children: [
                for (final v in _videos!) _videoRow(v, _channel!, inMusic),
              ],
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        musicSheetHandle(),
        Row(
          children: [
            if (_channel != null)
              IconButton(
                onPressed: () => setState(() => _channel = null),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.ink2,
              ),
            Expanded(
              child: Text(
                _channel?.name ??
                    (widget.forArtistId == null
                        ? '從 YT 管理挑'
                        : '幫「${ref.read(musicDataProvider).artistMap[widget.forArtistId]?.name ?? ''}」添加歌曲'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
        if (_channel == null) ...[
          // 標題跟網址欄之間留空（2026-10-20 使用者回報太擠）。
          const SizedBox(height: 14),
          _pastedBlock(inMusic),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _browse = !_browse),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.video_library_outlined,
                    size: 18,
                    color: AppColors.ink2,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '或從 YT 管理挑（選頻道、打歌名找）',
                      style: TextStyle(fontSize: 13.5, color: AppColors.ink2),
                    ),
                  ),
                  Icon(
                    _browse
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.ink2,
                  ),
                ],
              ),
            ),
          ),
          if (_browse) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _q,
              onChanged: (_) => _search(),
              style: const TextStyle(color: AppColors.ink),
              decoration: musicInputDecoration('打歌名找影片（例如：晴天）').copyWith(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.ink3,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
        Expanded(
          child: _channel == null && !_browse ? const SizedBox.shrink() : body,
        ),
      ],
    );
  }
}
