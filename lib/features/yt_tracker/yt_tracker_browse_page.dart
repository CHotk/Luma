import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';
import 'yt_video_row.dart';

enum _ViewMode { channel, video }

/// 「依影片顯示」的類型篩選——API 本身沒有標「這是 Shorts」的欄位，
/// 靠 [YoutubeVideo.isLikelyShort] 的時長啟發式判斷來分（2026-09-23
/// 使用者問「api給的資料有區分嗎」，這是能做到的最接近做法）。
enum _TypeFilter { all, regular, shorts }

/// 「依頻道顯示」的排序（2026-09-24 使用者要求）。訂閱人數沒有資料的
/// （還沒更新到、或頻道隱藏訂閱數）一律排最後，不管升冪降冪。
enum _ChannelSort { normal, subsDesc, subsAsc }

/// 一部影片＋它屬於哪個頻道，「依影片顯示」要混合多個頻道的影片，
/// 每一列要能同時秀出影片跟頻道兩邊的資訊。
class _ChannelVideo {
  const _ChannelVideo({required this.video, required this.channel});

  final YoutubeVideo video;
  final YtChannel channel;
}

/// 篩選＋頻道／影片雙視圖畫面（設計稿 06/07/08 定案）。從首頁點分類
/// 資料夾進來時，[initialCategoryIds] 就是那個分類，篩選 chip 會直接
/// 帶入選中狀態，不用重選一次（2026-09-22 使用者要求）。
///
/// 「依影片顯示」接了真的 YouTube Data API（2026-09-22）：把篩選範圍內
/// 每個頻道的「已上傳影片」播放清單抓出來，混成一條時間軸依上傳時間
/// 排序。第一次抓某個頻道時要先呼叫一次 `channels.list` 把
/// [YtChannel.uploadsPlaylistId] 解析出來、存回本機，之後同一個頻道
/// 就不用再解析（省配額，見 `youtube_api_service.dart`）。
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
  // 每個分類（含「全部」）點進去都預設「依頻道顯示」（2026-09-24 使用者
  // 要求；之前分類預設依影片，但一進去就要抓影片，太慢）。切換鈕維持
  // 影片在左、頻道在右，要看影片自己再切。
  _ViewMode _mode = _ViewMode.channel;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _ChannelSort _sort = _ChannelSort.normal;

  Future<List<_ChannelVideo>>? _videosFuture;
  List<String>? _videosLoadedFor;
  _TypeFilter? _videosLoadedType;
  DateTime? _videosLoadedAt;

  /// 「篩選範圍沒變就不重抓」是為了不要每次畫面重繪（一秒可能好幾次）
  /// 都重打 API，不是要把影片清單長期快取著——實際的影片清單從來沒有
  /// 存進本機，每次真的重抓都是直接問 YouTube 當下的狀態。但如果同一個
  /// 瀏覽分頁開超過這個時間都沒離開過，一樣要自動重抓一次，不然真的可能
  /// 放好幾天看到的都是舊清單（2026-09-22 使用者糾正）。
  static const _staleAfter = Duration(minutes: 5);

  /// 依影片顯示：每個頻道抓最近幾部，湊在一起依時間排序。不支援往下滑
  /// 載入更多（頻道多，資料量會太大，2026-09-24 使用者決定）。
  static const _videosPerChannel = 10;

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

  /// 「依影片顯示」要抓資料才有得看，但不能每次 build 都重打 API——只在
  /// 「切到影片模式」或「篩選範圍變了」才重抓，[force] 是手動按重新整理
  /// 才會用到，無視快取直接重抓一次。
  void _ensureVideosLoaded(List<YtChannel> channels, {bool force = false}) {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    final ids = channels.map((c) => c.id).toList()..sort();
    // 篩選類型（全部／一般影片／Shorts）變了也要重抓：現在是直接抓對應的
    // 播放清單，不是抓回來再自己挑。
    final sameSelection =
        _videosLoadedFor != null &&
        _listEquals(_videosLoadedFor!, ids) &&
        _videosLoadedType == _typeFilter;
    final stillFresh =
        _videosLoadedAt != null &&
        DateTime.now().difference(_videosLoadedAt!) < _staleAfter;
    if (!force && sameSelection && stillFresh) return;
    _videosLoadedFor = ids;
    _videosLoadedType = _typeFilter;
    _videosLoadedAt = DateTime.now();
    setState(() {
      _videosFuture = _fetchVideos(channels, apiKey);
    });
  }

  /// 依目前排序方式排好的頻道。訂閱人數沒資料（沒更新到、或隱藏）的排最後，
  /// 同人數的維持原本順序（[List.sort] 不保證穩定，所以自己帶原始位置比）。
  List<YtChannel> _sortedChannels(List<YtChannel> channels) {
    if (_sort == _ChannelSort.normal) return channels;
    final indexed = [for (var i = 0; i < channels.length; i++) (i, channels[i])];
    indexed.sort((a, b) {
      final x = a.$2.subscriberCount;
      final y = b.$2.subscriberCount;
      if (x == null && y == null) return a.$1.compareTo(b.$1);
      if (x == null) return 1;
      if (y == null) return -1;
      final byCount = _sort == _ChannelSort.subsDesc
          ? y.compareTo(x)
          : x.compareTo(y);
      return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// 訂閱人數更新：超過 12 小時沒問過的頻道，一次批次問（50 個頻道 1 單位
  /// 額度）。還沒解析過頻道 ID 的頻道先用 @handle 解析（順便拿人數）。
  /// 這個 session 已經試過的頻道不再試，避免解析不出來的頻道每次重繪都
  /// 重打 API。頻道詳情頁只讀存下來的值，不打 API（2026-09-24 使用者要求）。
  final Set<String> _statsTried = {};
  bool _statsInFlight = false;

  Future<void> _ensureStats(List<YtChannel> channels) async {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty || _statsInFlight) return;
    final now = DateTime.now();
    final stale = [
      for (final c in channels)
        if (!_statsTried.contains(c.id) &&
            (c.statsUpdatedAt == null ||
                now.difference(c.statsUpdatedAt!) > const Duration(hours: 12)))
          c,
    ];
    if (stale.isEmpty) return;
    _statsInFlight = true;
    _statsTried.addAll(stale.map((c) => c.id));
    try {
      final service = YoutubeApiService(apiKey);
      final updated = <YtChannel>[];
      final withId = <YtChannel>[];
      for (final c in stale) {
        if (c.youtubeChannelId.isNotEmpty) {
          withId.add(c);
          continue;
        }
        final handle = YoutubeApiService.parseHandle(c.url);
        if (handle == null) continue;
        final info = await service.fetchChannelInfo(handle);
        updated.add(
          c.copyWith(
            avatarImageUrl: c.avatarImageUrl.isEmpty ? info.avatarUrl : null,
            youtubeChannelId: info.channelId,
            uploadsPlaylistId: info.uploadsPlaylistId,
            subscriberCount: info.subscriberCount,
            subscribersHidden: info.subscribersHidden,
            statsUpdatedAt: now,
          ),
        );
      }
      final stats = await service.fetchSubscriberStats([
        for (final c in withId) c.youtubeChannelId,
      ]);
      for (final c in withId) {
        final s = stats[c.youtubeChannelId];
        if (s == null) continue;
        updated.add(
          c.copyWith(
            subscriberCount: s.count,
            subscribersHidden: s.hidden,
            statsUpdatedAt: now,
          ),
        );
      }
      await ref.read(ytTrackerRepositoryProvider).updateChannels(updated);
      if (mounted && updated.isNotEmpty) _reload();
    } catch (e, stack) {
      AppLog.add('[YT] 訂閱人數更新失敗：$e\n$stack', isError: true);
    } finally {
      _statsInFlight = false;
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<List<_ChannelVideo>> _fetchVideos(
    List<YtChannel> channels,
    String apiKey,
  ) async {
    final service = YoutubeApiService(apiKey);
    final repo = ref.read(ytTrackerRepositoryProvider);
    final type = _typeFilter;
    final results = <_ChannelVideo>[];
    // 特殊播放清單抓不到、退回「抓全部再自己依長度挑」的頻道。
    final fallbackChannelIds = <String>{};
    for (final original in channels) {
      var channel = original;
      if (channel.uploadsPlaylistId.isEmpty) {
        final handle = YoutubeApiService.parseHandle(channel.url);
        if (handle == null) continue; // 沒網址／沒 @handle，這個頻道跳過
        final info = await service.fetchChannelInfo(handle);
        channel = channel.copyWith(
          // 順便拿這次呼叫本來就有的官方頭貼——但只在使用者自己沒貼過
          // 圖片網址時才覆蓋，不要蓋掉使用者手動選的圖。
          avatarImageUrl:
              channel.avatarImageUrl.isEmpty ? info.avatarUrl : null,
          youtubeChannelId: info.channelId,
          uploadsPlaylistId: info.uploadsPlaylistId,
          subscriberCount: info.subscriberCount,
          subscribersHidden: info.subscribersHidden,
          statsUpdatedAt: DateTime.now(),
        );
        // 解析結果快取回本機，下次同一個頻道不用再打一次 channels.list。
        await repo.updateChannel(channel);
      }
      final typed = _typedPlaylistId(channel.uploadsPlaylistId, type);
      List<YoutubeVideo> videos;
      if (typed == null) {
        videos = await service.fetchRecentVideos(
          channel.uploadsPlaylistId,
          maxResults: _videosPerChannel,
        );
      } else {
        try {
          videos = await service.fetchRecentVideos(
            typed,
            maxResults: _videosPerChannel,
          );
        } on YoutubeApiException {
          // 這個頻道沒有對應的清單（例如根本沒發過 Shorts），或 API 不認得
          // 這種清單：退回抓全部上傳，之後依影片長度自己挑。金鑰／額度
          // 這類真的出問題的話，這次呼叫一樣會丟出同樣的錯，照樣顯示出來。
          fallbackChannelIds.add(channel.id);
          videos = await service.fetchRecentVideos(
            channel.uploadsPlaylistId,
            maxResults: _videosPerChannel,
          );
        }
      }
      for (final v in videos) {
        results.add(_ChannelVideo(video: v, channel: channel));
      }
    }
    // 時長要多打一次 videos.list，這裡混了好幾個頻道，一次把所有影片
    // id 湊在一起問，不要每個頻道各打一次——省配額，最多一次 50 個 id
    // 這個 App 用量遠遠用不到那個上限。這次失敗就算了，清單照樣顯示，
    // 只是沒有時長角標。
    try {
      final durations = await service.fetchDurations(
        [for (final r in results) r.video.videoId],
      );
      for (var i = 0; i < results.length; i++) {
        final d = durations[results[i].video.videoId];
        if (d != null) {
          results[i] = _ChannelVideo(
            video: results[i].video.withDuration(d),
            channel: results[i].channel,
          );
        }
      }
    } catch (_) {
      // 忽略，影片清單本身已經抓到了。
    }
    // 退回做法的頻道，這時才有長度可以挑。
    if (fallbackChannelIds.isNotEmpty) {
      results.removeWhere(
        (r) =>
            fallbackChannelIds.contains(r.channel.id) &&
            (type == _TypeFilter.shorts) != r.video.isLikelyShort,
      );
    }
    // 抓到的影片存進本機快取（跟頻道詳情頁共用同一份，也會跟著同步），
    // 用影片 id 去重——每次進來都抓最近 10 部，大部分跟上次重複，只有
    // 真的新的才會新增，已存的不會被寫兩次（2026-09-24 使用者要求）。
    final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    final byChannel = <String, List<YoutubeVideo>>{};
    for (final r in results) {
      byChannel.putIfAbsent(r.channel.id, () => []).add(r.video);
    }
    for (final entry in byChannel.entries) {
      await cache.upsertVideos(entry.key, entry.value);
    }
    results.sort((a, b) => b.video.publishedAt.compareTo(a.video.publishedAt));
    return results;
  }

  /// 依類型換成 YouTube 的特殊上傳播放清單：上傳清單 ID 是 `UU` 開頭，
  /// 換成 `UUSH` 是只有 Shorts、`UULF` 是只有一般影片（非官方文件保證的
  /// 做法，2026-09-24 用志祺七七實測：`UU` 8,360 部＝`UUSH` 5,330＋`UULF`
  /// 3,029＋`UULV` 1，而且 `UUSH` 的每一部在 YouTube 網站上都是 Shorts
  /// 版型）。全部就維持原本的上傳清單，回傳 null。
  String? _typedPlaylistId(String uploads, _TypeFilter type) {
    if (type == _TypeFilter.all || !uploads.startsWith('UU')) return null;
    final rest = uploads.substring(2);
    return type == _TypeFilter.shorts ? 'UUSH$rest' : 'UULF$rest';
  }

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
                  decoration: const InputDecoration(
                    labelText: '頻道名稱',
                    counterText: '',
                  ),
                  style: const TextStyle(color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: '頻道網址',
                    hintText: '例如 https://www.youtube.com/@shasha77',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(
                    labelText: '頭像圖片網址',
                    hintText: '去頻道頁面複製大頭貼圖片網址',
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
                    labelText: '簡介',
                    hintText: '這個頻道在做什麼',
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

  Widget _buildVideoPanel(List<YtChannel> channels) {
    final apiKey = ref.watch(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.vpn_key_outlined,
                size: 32,
                color: AppColors.ink3,
              ),
              const SizedBox(height: Gap.sm),
              Text('還沒有設定 API 金鑰', style: AppText.bodyDim),
              const SizedBox(height: 4),
              Text(
                '依影片顯示需要用金鑰去 YouTube 抓資料，\n依頻道顯示不用金鑰照樣能用。',
                style: AppText.note,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: () => showYtApiKeyDialog(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ytAccent,
                  foregroundColor: AppColors.ytAccentInk,
                ),
                child: const Text('設定金鑰'),
              ),
            ],
          ),
        ),
      );
    }
    if (channels.isEmpty) {
      return Center(child: Text('這個篩選條件下沒有頻道', style: AppText.bodyDim));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  _TypeChip(
                    label: '全部',
                    selected: _typeFilter == _TypeFilter.all,
                    onTap: () => setState(() => _typeFilter = _TypeFilter.all),
                  ),
                  _TypeChip(
                    label: '一般影片',
                    selected: _typeFilter == _TypeFilter.regular,
                    onTap: () =>
                        setState(() => _typeFilter = _TypeFilter.regular),
                  ),
                  _TypeChip(
                    label: 'Shorts',
                    selected: _typeFilter == _TypeFilter.shorts,
                    onTap: () =>
                        setState(() => _typeFilter = _TypeFilter.shorts),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _ensureVideosLoaded(channels, force: true),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('重新整理'),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
            ),
          ],
        ),
        Expanded(
          child: _videosFuture == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : FutureBuilder<List<_ChannelVideo>>(
                  future: _videosFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator.adaptive(),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '${snap.error}',
                            style: AppText.bodyDim,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    // 類型篩選已經在抓的時候做掉了（見 _fetchVideos），這裡直接用。
                    final videos = snap.data ?? const [];
                    if (videos.isEmpty) {
                      return Center(
                        child: Text(
                          _typeFilter == _TypeFilter.all
                              ? '這些頻道抓不到影片'
                              : '這個篩選條件下沒有影片',
                          style: AppText.bodyDim,
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: videos.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.glassEdge),
                      itemBuilder: (_, i) {
                        final item = videos[i];
                        return YtVideoRow(
                          video: item.video,
                          subtitle:
                              '${item.channel.name}・${ytRelativeTime(item.video.publishedAt)}',
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
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

                      // 訂閱人數（頻道列表要顯示）：不管哪種視圖都排程更新一次，
                      // 內部會挑出超過 12 小時沒更新的頻道。
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _ensureStats(channels);
                      });

                      // 只在「依影片顯示」時才需要抓影片；[_ensureVideosLoaded]
                      // 內部會比對篩選範圍有沒有變，沒變就直接跳過，所以每次
                      // build 都排程呼叫也不會一直重打 API。不能在 build()
                      // 當下直接呼叫（裡面可能觸發 setState），要排到這一幀
                      // 畫完之後。
                      if (_mode == _ViewMode.video) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _ensureVideosLoaded(channels);
                        });
                      }

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
                                value: _ViewMode.video,
                                label: Text('依影片顯示'),
                              ),
                              ButtonSegment(
                                value: _ViewMode.channel,
                                label: Text('依頻道顯示'),
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
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          _TypeChip(
                                            label: '預設排序',
                                            selected: _sort == _ChannelSort.normal,
                                            onTap: () => setState(
                                              () => _sort = _ChannelSort.normal,
                                            ),
                                          ),
                                          _TypeChip(
                                            label: '訂閱人數 多→少',
                                            selected: _sort == _ChannelSort.subsDesc,
                                            onTap: () => setState(
                                              () => _sort = _ChannelSort.subsDesc,
                                            ),
                                          ),
                                          _TypeChip(
                                            label: '訂閱人數 少→多',
                                            selected: _sort == _ChannelSort.subsAsc,
                                            onTap: () => setState(
                                              () => _sort = _ChannelSort.subsAsc,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: Gap.sm),
                                      Expanded(
                                        child: _ChannelGrid(
                                          channels: _sortedChannels(channels),
                                        ),
                                      ),
                                    ],
                                  )
                                : _buildVideoPanel(channels),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      if (c.subscriberLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          c.subscriberLabel!,
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
          ),
        );
      },
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

/// 「依影片顯示」的一般影片／Shorts 篩選 chip，比 [_CategoryPickChip]
/// 小一號——這排要跟「重新整理」按鈕擠在同一行，字級跟分類篩選那排
/// 一樣大會太擠。
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.22)
              : AppColors.glassFill,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.glassEdge,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}
