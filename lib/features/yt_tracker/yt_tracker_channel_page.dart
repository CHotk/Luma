import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'upload_frequency_chart.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';
import 'yt_video_row.dart';

/// 頻道詳情。基本資料（名稱、分類、網址、簡介）可以編輯／刪除，網址點
/// 下去會開新分頁；「最近影片」真的接了 YouTube Data API（2026-09-22，
/// 之前漏接，跟 `yt_tracker_browse_page.dart` 的「依影片顯示」補齊成
/// 同一套邏輯，見 `yt_video_row.dart` 共用元件）。
class YtTrackerChannelPage extends ConsumerStatefulWidget {
  const YtTrackerChannelPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<YtTrackerChannelPage> createState() =>
      _YtTrackerChannelPageState();
}

class _YtTrackerChannelPageState extends ConsumerState<YtTrackerChannelPage> {
  late Future<({YtChannel? channel, List<YtCategory> categories})> _future;

  Future<List<YoutubeVideo>>? _videosFuture;
  String? _videosLoadedForChannelId;
  DateTime? _videosLoadedAt;

  /// 「上傳頻率」摺線圖用的近半年影片，跟「最近影片」分開抓、分開快取
  /// ——這支可能要翻好幾頁 API、抓不少影片的時長，比最近影片貴，用同一
  /// 個 5 分鐘節流太浪費；半年內的資料不會突然變，只要同一個頻道同一次
  /// 進頁面抓過一次就夠，不用時間到就重抓，只有手動按重新整理（跟最近
  /// 影片共用那顆按鈕）才會強制重抓。
  Future<List<YoutubeVideo>>? _historyFuture;
  String? _historyLoadedForChannelId;

  /// 跟 `yt_tracker_browse_page.dart` 同一個節流理由：不是把影片清單
  /// 長期快取，只是不要每次重繪都重打 API，超過這個時間或按「重新
  /// 整理」都會重抓一次真的資料。
  static const _staleAfter = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({YtChannel? channel, List<YtCategory> categories})> _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final channels = await repo.loadChannels();
    final categories = await repo.loadCategories();
    final channel = channels.where((c) => c.id == widget.channelId);
    return (channel: channel.isEmpty ? null : channel.first, categories: categories);
  }

  void _reload() => setState(() => _future = _load());

  void _ensureVideosLoaded(YtChannel channel, {bool force = false}) {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    final sameChannel = _videosLoadedForChannelId == channel.id;
    final stillFresh =
        _videosLoadedAt != null &&
        DateTime.now().difference(_videosLoadedAt!) < _staleAfter;
    if (!force && sameChannel && stillFresh) return;
    _videosLoadedForChannelId = channel.id;
    _videosLoadedAt = DateTime.now();
    setState(() {
      _videosFuture = _fetchVideos(channel);
    });
  }

  Future<List<YoutubeVideo>> _fetchVideos(YtChannel channel) async {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return const [];
    final service = YoutubeApiService(apiKey);
    var uploadsId = channel.uploadsPlaylistId;
    if (uploadsId.isEmpty) {
      final handle = YoutubeApiService.parseHandle(channel.url);
      if (handle == null) {
        throw YoutubeApiException('這個頻道沒有網址，或網址裡找不到 @帳號，先去編輯頻道補上');
      }
      final info = await service.fetchChannelInfo(handle);
      uploadsId = info.uploadsPlaylistId;
      final updated = YtChannel(
        id: channel.id,
        name: channel.name,
        categoryId: channel.categoryId,
        avatarEmoji: channel.avatarEmoji,
        avatarImageUrl: channel.avatarImageUrl.isEmpty
            ? info.avatarUrl
            : channel.avatarImageUrl,
        url: channel.url,
        description: channel.description,
        youtubeChannelId: info.channelId,
        uploadsPlaylistId: info.uploadsPlaylistId,
        addedAt: channel.addedAt,
      );
      await ref.read(ytTrackerRepositoryProvider).updateChannel(updated);
    }
    final videos = await service.fetchRecentVideos(uploadsId, maxResults: 10);
    // 時長要多打一次 videos.list 才有，見 youtube_api_service.dart 的
    // 說明。這次失敗就算了，讓影片清單照樣顯示，只是沒有時長角標，
    // 不要因為這個次要資訊讓整個清單抓失敗。
    try {
      final durations = await service.fetchDurations(
        [for (final v in videos) v.videoId],
      );
      return [
        for (final v in videos)
          durations.containsKey(v.videoId)
              ? v.withDuration(durations[v.videoId]!)
              : v,
      ];
    } catch (_) {
      return videos;
    }
  }

  void _ensureHistoryLoaded(YtChannel channel, {bool force = false}) {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    if (!force && _historyLoadedForChannelId == channel.id) return;
    _historyLoadedForChannelId = channel.id;
    setState(() {
      _historyFuture = _fetchHistory(channel);
    });
  }

  Future<List<YoutubeVideo>> _fetchHistory(YtChannel channel) async {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return const [];
    final service = YoutubeApiService(apiKey);
    var uploadsId = channel.uploadsPlaylistId;
    if (uploadsId.isEmpty) {
      final handle = YoutubeApiService.parseHandle(channel.url);
      if (handle == null) return const [];
      final info = await service.fetchChannelInfo(handle);
      uploadsId = info.uploadsPlaylistId;
    }
    final now = DateTime.now();
    // 只抓近半年，不是全部歷史——時間範圍固定，不會因為頻道發片多寡
    // 讓等待時間跟配額失控（2026-09-23 使用者要求）。
    final since = DateTime(now.year, now.month - 6, now.day);
    final videos = await service.fetchAllVideos(uploadsId, since: since);
    // 時長抓失敗不影響圖能不能畫，只是 Shorts／一般影片分不出來，兩條
    // 線會全部算進「一般影片」那條（因為 isLikelyShort 需要 duration
    // 才能判斷，沒有就當作不是 Shorts）。
    try {
      final durations = await service.fetchDurations(
        [for (final v in videos) v.videoId],
      );
      return [
        for (final v in videos)
          durations.containsKey(v.videoId)
              ? v.withDuration(durations[v.videoId]!)
              : v,
      ];
    } catch (_) {
      return videos;
    }
  }

  Widget _buildHistoryChart(YtChannel channel) {
    final apiKey = ref.watch(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return const SizedBox.shrink();
    if (_historyFuture == null) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return FutureBuilder<List<YoutubeVideo>>(
      future: _historyFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        if (snap.hasError) {
          return SizedBox(
            height: 60,
            child: Center(
              child: Text(
                '抓不到歷史影片：${snap.error}',
                style: AppText.note,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final videos = snap.data ?? const [];
        return UploadFrequencyChart(data: bucketVideosByMonth(videos));
      },
    );
  }

  Widget _buildVideos(YtChannel channel) {
    final apiKey = ref.watch(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.vpn_key_outlined, size: 32, color: AppColors.ink3),
              const SizedBox(height: Gap.sm),
              Text('還沒有設定 API 金鑰', style: AppText.bodyDim),
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
    if (_videosFuture == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder<List<YoutubeVideo>>(
      future: _videosFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
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
        final videos = snap.data ?? const [];
        if (videos.isEmpty) {
          return Center(child: Text('這個頻道抓不到影片', style: AppText.bodyDim));
        }
        // 用 Column 不用 ListView.separated——這塊現在是外層
        // SingleChildScrollView 的一部分，自己不用再是獨立的可捲動
        // 區域（見 build() 的說明：簡介／圖表／影片要一起滑動）。
        return Column(
          children: [
            for (var i = 0; i < videos.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.glassEdge),
              YtVideoRow(
                video: videos[i],
                subtitle: ytRelativeTime(videos[i].publishedAt),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(YtChannel channel, List<YtCategory> categories) async {
    final nameController = TextEditingController(text: channel.name);
    final urlController = TextEditingController(text: channel.url);
    final avatarController = TextEditingController(text: channel.avatarImageUrl);
    final descriptionController = TextEditingController(text: channel.description);
    String? categoryId = channel.categoryId;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('編輯頻道', style: TextStyle(color: AppColors.ink)),
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
                  decoration: const InputDecoration(labelText: '頻道網址'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(labelText: '頭像圖片網址'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.xs),
                TextField(
                  controller: descriptionController,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '簡介'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
                const SizedBox(height: Gap.sm),
                Text('分類', style: AppText.note),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pick(
                      label: '未分類',
                      color: AppColors.ink3,
                      selected: categoryId == null,
                      onTap: () => setDialogState(() => categoryId = null),
                    ),
                    for (final cat in categories)
                      _Pick(
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
          // 刪除是破壞性動作，字體縮小、放最左邊跟儲存/取消拉開距離，
          // 不要跟常用的兩個動作擠在一起、字級還一樣大，容易誤按
          // （2026-09-22 使用者要求）。儲存在取消左邊，離刪除比較遠。
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('刪除', style: TextStyle(fontSize: 12)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ytAccent,
                foregroundColor: AppColors.ytAccentInk,
              ),
              child: const Text('儲存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );

    final repo = ref.read(ytTrackerRepositoryProvider);
    if (action == 'save') {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      await repo.updateChannel(
        YtChannel(
          id: channel.id,
          name: name,
          categoryId: categoryId,
          avatarEmoji: channel.avatarEmoji,
          avatarImageUrl: avatarController.text.trim(),
          url: urlController.text.trim(),
          description: descriptionController.text.trim(),
          addedAt: channel.addedAt,
        ),
      );
      if (!mounted) return;
      _reload();
    } else if (action == 'delete') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('刪除這個頻道？', style: TextStyle(color: AppColors.ink)),
          content: Text('這個動作無法復原。', style: AppText.bodyDim),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('刪除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await repo.deleteChannel(channel.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    }
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppTopBar(title: '頻道'),
                            const Expanded(
                              child: Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                            ),
                          ],
                        );
                      }
                      final channel = snap.data!.channel;
                      final categories = snap.data!.categories;
                      if (channel == null) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppTopBar(title: '頻道'),
                            Expanded(
                              child: Center(
                                child: Text('找不到這個頻道', style: AppText.bodyDim),
                              ),
                            ),
                          ],
                        );
                      }
                      final category = categories
                          .where((c) => c.id == channel.categoryId);
                      final categoryLabel =
                          category.isEmpty ? '未分類' : category.first.name;

                      // 不能在 build() 當下直接呼叫（裡面可能觸發
                      // setState），排到這一幀畫完之後——跟
                      // `yt_tracker_browse_page.dart` 同一套做法。
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _ensureVideosLoaded(channel);
                        _ensureHistoryLoaded(channel);
                      });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTopBar(
                            title: channel.name,
                            actions: [
                              IconButton(
                                onPressed: () =>
                                    _showEditDialog(channel, categories),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                color: AppColors.ink2,
                                tooltip: '編輯頻道',
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.md),
                          // 簡介／上傳頻率圖／最近影片全部包進同一個可捲動
                          // 區域，不要只有最近影片自己捲、上面的內容固定
                          // 不動——不然滑最近影片清單時，簡介跟圖表卻停在
                          // 原地不會一起往上滑，體驗很奇怪（2026-09-23
                          // 使用者回報）。只有頂部列固定在外面。
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildChannelBody(
                                    channel,
                                    categories,
                                    categoryLabel,
                                  ),
                                ],
                              ),
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

  Widget _buildChannelBody(
    YtChannel channel,
    List<YtCategory> categories,
    String categoryLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
                            children: [
                              YtChannelAvatar(channel: channel, radius: 28),
                              const SizedBox(width: Gap.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      channel.name,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(categoryLabel, style: AppText.note),
                                    if (channel.url.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      InkWell(
                                        onTap: () => openExternalUrl(
                                          context,
                                          channel.url,
                                        ),
                                        child: Text(
                                          channel.url,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.note.copyWith(
                                            // 連結照網頁慣例用淡藍色，不用
                                            // 這個功能自己的紅色強調色——
                                            // 紅在這個 App 的語意色系裡也
                                            // 常代表錯誤/警示，用在連結上
                                            // 會讓人誤會（2026-09-22
                                            // 使用者回饋）。AppColors.accent
                                            // 就是既有的淡藍色，不用另外
                                            // 開新色碼。
                                            color: AppColors.accent,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (channel.description.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            const PanelLabel('簡介'),
                            const SizedBox(height: Gap.xs),
                            Text(channel.description, style: AppText.bodyDim),
                          ],
                          const SizedBox(height: Gap.md),
                          const PanelLabel('上傳頻率（近半年）'),
                          const SizedBox(height: Gap.xs),
                          _buildHistoryChart(channel),
                          const SizedBox(height: Gap.md),
                          Row(
                            children: [
                              const PanelLabel('最近影片'),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () {
                                  _ensureVideosLoaded(channel, force: true);
                                  _ensureHistoryLoaded(channel, force: true);
                                },
                                icon: const Icon(Icons.refresh, size: 15),
                                label: const Text('重新整理'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.ink2,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
        const SizedBox(height: Gap.sm),
        _buildVideos(channel),
      ],
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
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
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? color.withValues(alpha: 0.22) : AppColors.glassFill,
          border: Border.all(color: selected ? color : AppColors.glassEdge),
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
