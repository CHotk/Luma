import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/repositories/yt_video_hidden_store.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/background_refresh.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'upload_frequency_chart.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';
import 'yt_video_row.dart';

/// 「影片」清單的類型篩選，跟 `yt_tracker_browse_page.dart` 的
/// `_TypeFilter` 同一個概念、各自獨立一份（2026-09-30 使用者要求：
/// 頻道詳情頁也要能直接篩全部／一般影片／Shorts／直播）。
enum _TypeFilter { all, regular, shorts, live }

/// 頻道詳情。基本資料（名稱、分類、網址、簡介）可以編輯／刪除，網址點
/// 下去會開新分頁；「影片」清單真的接了 YouTube Data API（2026-09-22，
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

  /// 「最近影片」往下滑到底繼續載入更早影片（2026-09-24 使用者要求）：
  /// 第一頁 10 部由 [_videosFuture] 抓，之後每頁 20 部接在 [_moreVideos]。
  final _scroll = ScrollController();

  /// 往下滑每次載入幾部。YouTube `playlistItems.list` 一次最多 50 部，
  /// 不管要 5 部還是 50 部都是 1 單位配額，所以直接拉滿（2026-09-24
  /// 使用者要求）；補時長的 `videos.list` 一次也最多吃 50 個 id、同樣
  /// 1 單位，所以一批 50 部總共 2 單位。
  static const _loadMoreBatch = 50;
  String? _uploadsId;
  String? _nextPageToken;
  List<YoutubeVideo> _firstPage = const [];
  bool _reachedEnd = false;
  String? _loadMoreChannelId;
  List<YoutubeVideo> _moreVideos = const [];
  bool _loadingMore = false;
  String? _loadMoreError;
  String? _videosLoadedForChannelId;
  DateTime? _videosLoadedAt;

  /// 「上傳頻率」摺線圖用的近半年影片，跟「最近影片」分開抓、分開快取
  /// ——這支可能要翻好幾頁 API、抓不少影片的時長，比最近影片貴，用同一
  /// 個 5 分鐘節流太浪費；半年內的資料不會突然變，只要同一個頻道同一次
  /// 進頁面抓過一次就夠，不用時間到就重抓，只有手動按重新整理（跟最近
  /// 影片共用那顆按鈕）才會強制重抓。
  Future<List<YoutubeVideo>>? _historyFuture;

  /// 快取有點舊、背景補抓新影片期間，先拿本機資料把圖畫出來的預覽。
  List<YoutubeVideo>? _historyPreview;
  String? _historyLoadedForChannelId;

  /// 跟 `yt_tracker_browse_page.dart` 同一個節流理由：不是把影片清單
  /// 長期快取，只是不要每次重繪都重打 API，超過這個時間或按「重新
  /// 整理」都會重抓一次真的資料。
  static const _staleAfter = Duration(minutes: 5);

  /// 「最近影片」清單的顯示篩選（2026-09-30 使用者要求）：預設把已經看
  /// 過的影片收起來，專心看還沒看的；隱藏過的影片預設也不顯示，開關
  /// 開了才連同已隱藏的一起看（給「隱藏所有看過的」用完之後想回頭review
  /// 用）。這兩個集合只在這頁載入一次，個別影片列自己滑動隱藏／取消
  /// 隱藏之後靠 [YtVideoRow.onHiddenChanged] 通知這裡重新讀一次。
  Set<String> _watchedVideoIds = {};
  Set<String> _hiddenVideoIds = {};
  bool _hideWatched = true;
  bool _showHiddenVideos = false;

  // 哪些 videoId 這次是從本機快取讀到的、不是真的打 API 抓來的
  // （2026-09-30 使用者要求：想在畫面上看出哪些是秒出來、不用配額的）。
  // 只有「全部」清單的 `_loadMoreVideos` 會往這裡加——那邊往下滑載入
  // 更多會先查本機快取（見那個方法的說明），類型篩選的 `_loadTypedVideos`
  // 目前每次都是真的打 API，不會有快取來源。
  final Set<String> _cachedVideoIds = {};

  /// 第一頁還在向 YouTube 拿的時候，先顯示的本機快取影片（2026-10-02
  /// 使用者選了「先顯示舊的、背景更新」：不讓畫面空著轉圈等，有快取
  /// 就先秀出來，頂端細進度條＋「正在檢查新影片」膠囊）。
  List<YoutubeVideo> _cachePreview = const [];

  /// 這個頻道本機快取裡的全部影片（不只上面那 50 部預覽）。篩選開關上
  /// 「看過幾部」要算整份快取，不能只算這次打開後抓進來的那幾頁
  /// （2026-10-05 使用者抓到：快取明明有一百部看過，數字只算到幾十）。
  List<YoutubeVideo> _cachedChannelVideos = const [];

  // 全部／一般影片／Shorts／直播的類型篩選（2026-09-30 使用者要求）。
  // 選「全部」以外的類型時，直接翻那個類型自己的特殊清單（見
  // `_loadTypedVideos` 的說明），是一份跟「全部」完全分開的分頁狀態
  // ——自己的清單游標（`_typedNextPageToken`）、自己的到底旗標，不跟
  // `_firstPage`／`_moreVideos`／那份 resume 共用，兩邊翻頁位置是對應
  // 不同清單，混在一起會對不上。
  _TypeFilter _typeFilter = _TypeFilter.all;

  // 「篩選完可見清單太短就主動幫忙多抓一批」的保險（見下面
  // `_buildVideos` 裡的說明）沒有設上限——使用者曾問「看過的量一大，
  // 每次打開頻道頁是不是都要燒好幾個配額單位」，答案是本機快取住之後
  // 第二次開多半直接從快取秒出（見 `_loadMoreVideos` 「先查本機快取」
  // 那段），不用真的打 API；第一次確實會真的多打幾次，但使用者決定
  // 這個代價無所謂，不用另外設上限、多一個「再載入」按鈕的麻煩
  // （2026-09-30 使用者要求）。
  List<YoutubeVideo> _typedVideos = const [];
  String? _typedNextPageToken;
  bool _typedReachedEnd = false;
  bool _typedLoading = false;
  String? _typedError;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _scroll.addListener(_onScroll);
    _loadVideoFilters();
  }

  Future<void> _loadVideoFilters() async {
    final store = ref.read(keyValueStoreProvider);
    final watched = await YtVideoWatchStore(store).loadAll();
    final hidden = await YtVideoHiddenStore(store).loadAll();
    if (!mounted) return;
    setState(() {
      _watchedVideoIds = watched.keys.toSet();
      _hiddenVideoIds = hidden;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    // 選了特定類型就是翻那個類型自己的清單，跟「全部」是兩份分開的
    // 分頁狀態，見 `_loadTypedVideos` 的說明。
    if (_typeFilter == _TypeFilter.all) {
      _loadMoreVideos();
    } else {
      _loadTypedVideos();
    }
  }

  Future<List<YoutubeVideo>> _withDurations(
    YoutubeApiService service,
    List<YoutubeVideo> videos,
  ) async {
    // 時長要多打一次 videos.list 才有，這次失敗就算了，讓影片清單照樣
    // 顯示，只是沒有時長角標。
    try {
      final durations = await service.fetchDurations([
        for (final v in videos) v.videoId,
      ]);
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

  /// 往下滑載入更早的影片。順序：
  /// 1. 先看本機快取（含其他裝置同步過來的）有沒有「比畫面上最舊那部更
  ///    早」的影片，有就直接拿來用，**不打 API**。
  /// 2. 快取用完了才打 API，而且從快取記下的「翻到哪裡」的位置接著抓
  ///    （見 [YtResume]），已經抓過的那一段整段跳過，不從頭翻。
  /// 抓回來的影片一律存進快取（之後不用再請求、也會跟著同步），用影片
  /// id 去重。
  Future<void> _loadMoreVideos() async {
    final apiKey = ref.read(ytApiKeyProvider);
    final uploadsId = _uploadsId;
    final channelId = _loadMoreChannelId;
    if (_loadingMore ||
        _loadMoreError != null ||
        _reachedEnd ||
        uploadsId == null ||
        channelId == null ||
        apiKey == null ||
        apiKey.isEmpty) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
      final shown = [..._firstPage, ..._moreVideos];
      final shownIds = {for (final v in shown) v.videoId};
      final oldestShown = shown
          .map((v) => v.publishedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      // 1. 本機快取
      final cached = await cache.load(channelId);
      final older = [
        for (final v in cached)
          if (!shownIds.contains(v.videoId) &&
              v.publishedAt.isBefore(oldestShown))
            v,
      ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      if (older.isNotEmpty) {
        final batch = older.take(_loadMoreBatch).toList();
        if (!mounted) return;
        setState(() {
          _moreVideos = [..._moreVideos, ...batch];
          _cachedVideoIds.addAll(batch.map((v) => v.videoId));
          _loadingMore = false;
        });
        return;
      }

      // 2. 打 API，從記下的位置續抓
      final service = YoutubeApiService(apiKey);
      var resume = await cache.loadResume(channelId);
      if (resume != null && resume.end) {
        if (!mounted) return;
        setState(() {
          _reachedEnd = true;
          _loadingMore = false;
        });
        return;
      }
      var token = resume?.token ?? _nextPageToken;
      var offset = resume?.offset ?? _firstPage.length;
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _reachedEnd = true;
          _loadingMore = false;
        });
        return;
      }
      final fresh = <YoutubeVideo>[];
      final knownIds = {...shownIds, for (final v in cached) v.videoId};
      // 位置往後挪過的話這一頁可能全是重複，最多連翻 5 頁找新的。
      for (var i = 0; i < 5 && fresh.isEmpty && token != null; i++) {
        final page = await service.fetchVideosPage(
          uploadsId,
          pageToken: token,
          maxResults: _loadMoreBatch,
        );
        offset += page.videos.length;
        final newOnes = [
          for (final v in page.videos)
            if (!knownIds.contains(v.videoId)) v,
        ];
        final withDurations = await _withDurations(service, newOnes);
        await cache.upsertVideos(channelId, withDurations);
        await cache.saveResumeIfDeeper(
          channelId,
          YtResume(
            token: page.nextPageToken,
            offset: offset,
            end: page.nextPageToken == null,
          ),
        );
        fresh.addAll(withDurations);
        token = page.nextPageToken;
      }
      if (!mounted) return;
      setState(() {
        _moreVideos = [..._moreVideos, ...fresh];
        _reachedEnd = token == null && fresh.isEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = '$e';
      });
    }
  }

  Future<({YtChannel? channel, List<YtCategory> categories})> _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final channels = await repo.loadChannels();
    final categories = await repo.loadCategories();
    final channel = channels.where((c) => c.id == widget.channelId);
    return (
      channel: channel.isEmpty ? null : channel.first,
      categories: categories,
    );
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
      _uploadsId = null;
      _nextPageToken = null;
      _firstPage = const [];
      _reachedEnd = false;
      _loadMoreChannelId = channel.id;
      _moreVideos = const [];
      _loadingMore = false;
      _loadMoreError = null;
      _cachedVideoIds.clear();
      _cachePreview = const [];
      _cachedChannelVideos = const [];
      _videosFuture = _fetchVideos(channel);
    });
    YtVideoCacheStore(ref.read(keyValueStoreProvider)).load(channel.id).then((
      cached,
    ) {
      if (!mounted || _videosLoadedForChannelId != channel.id) return;
      final sorted = [...cached]
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      setState(() {
        _cachePreview = sorted.take(_loadMoreBatch).toList();
        _cachedChannelVideos = cached;
      });
    });
  }

  /// 「重新整理」按鈕跟空狀態卡片上的「重新整理」共用。
  void _refresh(YtChannel channel) {
    _ensureVideosLoaded(channel, force: true);
    _ensureHistoryLoaded(channel, force: true);
    // 目前如果正看著特定類型，重新整理也要連那份分開的分頁狀態一起
    // 重抓，不然按了重新整理、類型篩選那份還是舊的。
    if (_typeFilter != _TypeFilter.all) {
      setState(() {
        _typedVideos = const [];
        _typedNextPageToken = null;
        _typedReachedEnd = false;
        _typedError = null;
      });
      _loadTypedVideos();
    }
  }

  /// 「隱藏已看過」「顯示已隱藏」兩個開關套用後，這支影片要不要出現。
  bool _passesFilters(YoutubeVideo v) {
    if (_hiddenVideoIds.contains(v.videoId)) return _showHiddenVideos;
    return !(_hideWatched && _watchedVideoIds.contains(v.videoId));
  }

  Widget _videoRows(List<YoutubeVideo> list, {bool allFromCache = false}) =>
      Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.glassEdge),
            YtVideoRow(
              // 一定要給明確的 key，理由跟 yt_tracker_browse_page.dart
              // 那邊一樣：篩選開關一切換，清單位置就會洗牌，沒有 key
              // 的話 Flutter 照位置重用 State，「已看過」狀態會錯配到
              // 別支影片上（2026-09-30 使用者回報抓到）。
              key: ValueKey(list[i].videoId),
              video: list[i],
              subtitle: ytRelativeTime(list[i].publishedAt),
              forceShow: _hiddenVideoIds.contains(list[i].videoId),
              onHiddenChanged: _loadVideoFilters,
              fromCache:
                  allFromCache || _cachedVideoIds.contains(list[i].videoId),
            ),
          ],
        ],
      );

  // 切類型篩選（2026-09-30 使用者要求）。原本的做法是抓全部上傳清單，
  // 用另外抓來的 50 部樣本 id 去核對「這部是不是 Shorts／直播」——這招
  // 對「全部」清單很夠用，但選「Shorts」這種在整個頻道歷史裡很稀疏的
  // 類型時，會逼著 `_loadMoreVideos` 一路往回翻好幾百部普通影片，
  // 才能湊到 50 部真的是 Shorts 的（使用者回報「搜尋太久」）；更糟的是
  // 這些連帶翻出來的普通影片全部留在 `_moreVideos` 裡，切回「一般影片」
  // 一次要把成百上千部塞進沒有虛擬化的 `Column`，直接卡死（使用者回報
  // 「點shorts又點一般影片會當機」）。
  //
  // 正確做法（使用者提醒：「不是有專門蒐 shorts 的 API」）：選了特定
  // 類型就直接翻那個類型自己的特殊清單（UUSH／UULV／UULF），不是抓
  // 全部再篩——清單本身就是答案，不用大海撈針，也不會不小心撈出一堆
  // 不相關的影片。這跟 `yt_tracker_browse_page.dart` 的「依影片顯示」
  // 是同一個道理，只是那邊沒有往下滑載入更多，這邊要另外接一套自己的
  // 分頁狀態（`_typedVideos` 那組），不跟「全部」共用 `_firstPage`／
  // `_moreVideos`／resume——兩邊的翻頁游標是對應不同清單，混在一起會
  // 對不上。
  void _switchTypeFilter(_TypeFilter next) {
    if (_typeFilter == next) return;
    setState(() {
      _typeFilter = next;
      _typedVideos = const [];
      _typedNextPageToken = null;
      _typedReachedEnd = false;
      _typedLoading = false;
      _typedError = null;
    });
    if (next != _TypeFilter.all) _loadTypedVideos();
  }

  String? _typedPlaylistId() {
    final uploadsId = _uploadsId;
    if (uploadsId == null || !uploadsId.startsWith('UU')) return null;
    final rest = uploadsId.substring(2);
    return switch (_typeFilter) {
      _TypeFilter.shorts => 'UUSH$rest',
      _TypeFilter.live => 'UULV$rest',
      _TypeFilter.regular => 'UULF$rest',
      _TypeFilter.all => null,
    };
  }

  Future<void> _loadTypedVideos() async {
    final apiKey = ref.read(ytApiKeyProvider);
    final playlistId = _typedPlaylistId();
    if (_typedLoading ||
        _typedError != null ||
        _typedReachedEnd ||
        playlistId == null ||
        apiKey == null ||
        apiKey.isEmpty) {
      return;
    }
    setState(() => _typedLoading = true);
    try {
      final service = YoutubeApiService(apiKey);
      List<YoutubeVideo> page;
      String? nextToken;
      try {
        final result = await service.fetchVideosPage(
          playlistId,
          pageToken: _typedNextPageToken,
          maxResults: _loadMoreBatch,
        );
        page = result.videos;
        nextToken = result.nextPageToken;
      } on YoutubeApiException catch (e) {
        // 404：這個頻道真的沒有這個類型（例如從沒開過直播），不是錯誤，
        // 這次篩選就是 0 部。其他錯誤才是真的抓不到，設 _typedError 讓
        // 畫面給重試按鈕。
        if (e.status == 404) {
          page = const [];
          nextToken = null;
        } else {
          rethrow;
        }
      }
      final tagged = switch (_typeFilter) {
        _TypeFilter.shorts => [
          for (final v in page) v.withShort(true).withLive(false),
        ],
        _TypeFilter.live => [
          for (final v in page) v.withShort(false).withLive(true),
        ],
        _TypeFilter.regular => [
          for (final v in page) v.withShort(false).withLive(false),
        ],
        _TypeFilter.all => page,
      };
      final withDurations = await _withDurations(service, tagged);
      // 這些也是這個頻道的真實影片，存進跟「全部」共用的同一份快取
      // （用 videoId 去重，不會蓋掉其他來源已經有的資料），之後「全部」
      // 清單翻頁翻到同一部時，也能直接拿到已經分類好的 Shorts／直播
      // 標籤，不用再猜。
      final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
      final channelId = _loadMoreChannelId;
      if (channelId != null) await cache.upsertVideos(channelId, withDurations);
      if (!mounted) return;
      setState(() {
        _typedVideos = [..._typedVideos, ...withDurations];
        _typedNextPageToken = nextToken;
        _typedReachedEnd = nextToken == null;
        _typedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _typedLoading = false;
        _typedError = '$e';
      });
    }
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
      final updated = channel.copyWith(
        avatarImageUrl: channel.avatarImageUrl.isEmpty ? info.avatarUrl : null,
        youtubeChannelId: info.channelId,
        uploadsPlaylistId: info.uploadsPlaylistId,
        subscriberCount: info.subscriberCount,
        subscribersHidden: info.subscribersHidden,
        statsUpdatedAt: DateTime.now(),
        videoCount: info.videoCount,
      );
      await ref.read(ytTrackerRepositoryProvider).updateChannel(updated);
    }
    _uploadsId = uploadsId;
    final page = await service.fetchVideosPage(uploadsId, maxResults: 10);
    _nextPageToken = page.nextPageToken;
    _loadMoreChannelId = channel.id;
    final videos = page.videos;
    // 時長要多打一次 videos.list 才有，見 youtube_api_service.dart 的
    // 說明。這次失敗就算了，讓影片清單照樣顯示，只是沒有時長角標，
    // 不要因為這個次要資訊讓整個清單抓失敗。
    final result = await _withDurations(service, videos);
    // 最近影片也存進快取（跟往下滑載入的更早影片、上傳頻率圖共用同一份），
    // 之後不用再請求，也會跟著同步（2026-09-24 使用者要求）。
    final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    await cache.upsertVideos(channel.id, result);
    await cache.saveResumeIfDeeper(
      channel.id,
      YtResume(
        token: page.nextPageToken,
        offset: result.length,
        end: page.nextPageToken == null,
      ),
    );
    // 用 setState：篩選開關上的數字（看過幾部、隱藏幾部）是從這份清單
    // 算的，第一頁進來時要跟著更新。
    if (mounted) setState(() => _firstPage = result);
    return result;
  }

  void _ensureHistoryLoaded(YtChannel channel, {bool force = false}) {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    if (!force && _historyLoadedForChannelId == channel.id) return;
    _historyLoadedForChannelId = channel.id;
    setState(() {
      _historyPreview = null;
      _historyFuture = _fetchHistory(channel);
    });
  }

  Future<List<YoutubeVideo>> _fetchHistory(YtChannel channel) async {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return const [];
    final now = DateTime.now();
    // 只抓近半年，不是全部歷史——時間範圍固定，不會因為頻道發片多寡
    // 讓等待時間跟配額失控（2026-09-23 使用者要求）。
    final since = DateTime(now.year, now.month - 6, now.day);

    // 本機已經快取過的影片（見 yt_video_cache_store.dart）。頻道隨時
    // 可能發新片（10 秒、5 分鐘、15 分鐘都有可能），所以**不設**「多久內
    // 不用重抓」的時間限制，每次進頁面都補抓一次；但不讓使用者乾等——
    // 先把本機（含其他裝置同步過來的）資料畫出來當預覽，背景只補「上次
    // 之後新發的影片」：翻頁遇到已知影片就停（通常只要 1 次 API 呼叫），
    // 也不會重打已知影片的時長（2026-09-23 使用者要求：本機已經有的資料
    // 不用再往後拿，省配額）。
    final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    final cached = await cache.load(channel.id);
    final cachedById = {for (final v in cached) v.videoId: v};
    final cachedInWindow =
        cached.where((v) => !v.publishedAt.isBefore(since)).toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    if (cached.isNotEmpty && mounted) {
      setState(() => _historyPreview = cachedInWindow);
    }

    final service = YoutubeApiService(apiKey);
    var uploadsId = channel.uploadsPlaylistId;
    if (uploadsId.isEmpty) {
      final handle = YoutubeApiService.parseHandle(channel.url);
      if (handle == null) return cachedInWindow;
      final info = await service.fetchChannelInfo(handle);
      uploadsId = info.uploadsPlaylistId;
    }

    // 「遇到已知影片就停止翻頁」只有在之前**完整抓過一次半年份**（有記錄
    // 「上次對過 YouTube 的時間」）才成立。最近影片／往下滑載入的影片也會
    // 寫進同一份快取，快取裡有幾部不代表半年份抓齊了，這時要一路抓到
    // since 為止，不然常發片的頻道上傳頻率圖會缺資料。
    final everCompleted = await cache.lastFetchedAt(channel.id) != null;
    final resumeWrites = <Future<void>>[];
    final fetched = await service.fetchAllVideos(
      uploadsId,
      since: since,
      knownVideoIds: everCompleted ? cachedById.keys.toSet() : const {},
      onPage: (token, offset) => resumeWrites.add(
        cache.saveResumeIfDeeper(
          channel.id,
          YtResume(token: token, offset: offset, end: token == null),
        ),
      ),
    );
    await Future.wait(resumeWrites);

    // 這次翻頁翻到的影片，扣掉本來就已經快取、時長也已經有的，只有
    // 真的新的才需要多打一次 fetchDurations。
    final newIds = [
      for (final v in fetched)
        if (!cachedById.containsKey(v.videoId) ||
            cachedById[v.videoId]!.duration == null)
          v.videoId,
    ];
    var withDurations = fetched;
    if (newIds.isNotEmpty) {
      // 時長抓失敗不影響圖能不能畫，只是 Shorts／一般影片分不出來，
      // 兩條線會全部算進「一般影片」那條（isLikelyShort 需要 duration
      // 才能判斷，沒有就當作不是 Shorts）。
      try {
        final durations = await service.fetchDurations(newIds);
        withDurations = [
          for (final v in fetched)
            durations.containsKey(v.videoId)
                ? v.withDuration(durations[v.videoId]!)
                : v,
        ];
      } catch (_) {
        // 忽略，withDurations 保持沒補時長的版本。
      }
    }

    // 合併快取＋這次抓到的，新的蓋舊的（時長可能剛補上），整份落地存回去
    // 給下次用——**不再裁掉半年以前的**：往下滑載入的更早影片也存在同一份
    // 快取裡，下次不用重抓。上傳頻率圖只畫 since 窗口內的那部分。
    final merged = {
      for (final v in cached) v.videoId: v,
      // 這次翻頁又翻到的已知影片沒帶時長，別把快取裡已有的時長蓋成 null。
      for (final v in withDurations)
        v.videoId: v.duration == null && cachedById[v.videoId]?.duration != null
            ? cachedById[v.videoId]!
            : v,
    }.values.toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    // Shorts 用 YouTube 自己的 Shorts 播放清單（UUSH）比對，不再靠「≤60 秒」
    // 估（2026-09-24 使用者要求）。頻道沒有 Shorts 清單（404）就代表沒有
    // Shorts；其他錯誤（網路、配額）就先不動，維持原本的判斷。
    var classified = merged;
    if (uploadsId.startsWith('UU')) {
      Set<String>? shortIds;
      try {
        final knownShorts = everCompleted
            ? {
                for (final v in merged)
                  if (v.isShort == true ||
                      cachedById[v.videoId]?.isShort == true)
                    v.videoId,
              }
            : <String>{};
        final shorts = await service.fetchAllVideos(
          'UUSH${uploadsId.substring(2)}',
          since: since,
          knownVideoIds: knownShorts,
        );
        shortIds = {for (final v in shorts) v.videoId};
      } on YoutubeApiException catch (e) {
        if (e.status == 404) shortIds = <String>{};
      } catch (_) {
        // 忽略，維持原本的判斷。
      }
      if (shortIds != null) {
        final ids = shortIds;
        classified = [
          for (final v in merged)
            v.publishedAt.isBefore(since)
                ? v
                : v.withShort(
                    ids.contains(v.videoId) ||
                        v.isShort == true ||
                        cachedById[v.videoId]?.isShort == true,
                  ),
        ];
      }
    }
    await cache.save(channel.id, classified);
    return [
      for (final v in classified)
        if (!v.publishedAt.isBefore(since)) v,
    ];
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
          // 背景補抓新影片期間，先用本機快取把圖畫出來，不讓使用者對著
          // 轉圈圈乾等。
          final preview = _historyPreview;
          if (preview != null) {
            return UploadFrequencyChart(data: bucketVideosByMonth(preview));
          }
          return const SizedBox(
            height: 110,
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
              const Icon(
                Icons.vpn_key_outlined,
                size: 32,
                color: AppColors.ink3,
              ),
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
          // 先顯示舊的、背景更新：有快取就先秀快取（類型篩選時快取裡
          // 分不準類型，只秀膠囊不秀內容），沒快取（第一次開這個頻道）
          // 就只有細進度條＋膠囊。
          final preview = _typeFilter == _TypeFilter.all
              ? _cachePreview.where(_passesFilters).toList()
              : const <YoutubeVideo>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ThinRefreshBar(),
              const SizedBox(height: Gap.sm),
              RefreshingPill(
                label: preview.isEmpty ? '正在向 YouTube 拿影片…' : '正在檢查新影片…',
              ),
              const SizedBox(height: Gap.xs),
              if (preview.isNotEmpty)
                _videoRows(preview, allFromCache: true)
              else
                const SizedBox(height: 120),
            ],
          );
        }
        if (snap.hasError) {
          return InlineEmptyCard(
            title: '影片抓不下來',
            message: '${snap.error}',
            actions: [EmptyAction('重新整理', () => _refresh(channel))],
          );
        }
        final firstPage = snap.data ?? const [];
        if (firstPage.isEmpty) {
          return InlineEmptyCard(
            title: '這個頻道抓不到影片',
            message: '可能還沒發過公開影片',
            actions: [EmptyAction('重新整理', () => _refresh(channel))],
          );
        }
        // 選了特定類型（一般影片／Shorts／直播）就是看 `_typedVideos`
        // 那份分頁狀態，跟「全部」（`_firstPage`+`_moreVideos`）完全分開
        // ——每種類型都直接翻自己的特殊清單，不是抓全部再篩（見
        // `_loadTypedVideos` 的說明：原本抓全部再篩的做法，選稀疏類型
        // 時會逼著往回翻一大串不相關的影片，量一大沒有虛擬化的
        // `Column` 直接卡死，2026-09-30 使用者回報過）。
        final isTyped = _typeFilter != _TypeFilter.all;
        final videos = isTyped ? _typedVideos : [...firstPage, ..._moreVideos];
        final loading = isTyped ? _typedLoading : _loadingMore;
        final error = isTyped ? _typedError : _loadMoreError;
        final reachedEnd = isTyped ? _typedReachedEnd : _reachedEnd;
        void loadMore() => isTyped ? _loadTypedVideos() : _loadMoreVideos();

        // 篩選規則（2026-09-30 使用者要求）：已隱藏的影片只有開了「顯示
        // 已隱藏」才出現；沒被隱藏的影片再看「隱藏已看過」那個開關決定
        // 要不要收起已看過的。類型本身不用在這裡再篩一次——`videos` 這個
        // 來源本身就已經是正確類型了（`isTyped` 時直接來自對應的特殊
        // 清單，`all` 時本來就是全部）。
        final visibleVideos = videos.where(_passesFilters).toList();
        // 「隱藏已看過」預設開著，一個頻道看過越多，篩選完剩下的影片就
        // 越少——少到畫面塞不滿、捲不動的話，往下滑觸發載入更多影片的
        // `_onScroll` 永遠不會被觸發（沒東西可滑，滑動事件根本不會發生），
        // 使用者只會看到寥寥幾部甚至沒有影片，看起來就像「連沒看過的
        // 影片也一起被藏起來了」——其實它們只是還沒被抓進來，不是被藏
        // 起來（2026-09-30 使用者回報「取消隱藏已看過才會出現其他影片」
        // 抓到的就是這個：關掉篩選後，畫面東西夠多能捲動了，才第一次
        // 真的觸發到載入）。這裡補一個不靠捲動的保險：篩選完的可見清單
        // 太短、還沒到底、也沒在載入中，就主動幫忙多抓一批，直到畫面
        // 有夠多可見影片、或是真的抓到底為止。
        //
        // 門檻用 [_loadMoreBatch]（50）不是隨便一個數字（2026-09-30
        // 使用者糾正：門檻本來寫死抄第一頁筆數 10，邏輯上沒對齊）——
        // 「載入更多」一次真的抓的量就是 50，篩選前後使用者感受到的
        // 捲動節奏要一樣，可見清單就該補到跟一次原始批次同一個量級，
        // 不然篩掉的越多，同一次滑動觸發後能看到的新影片反而越少，
        // 跟沒開篩選時不等價。
        //
        // 沒有設上限：看過的量一大，第一次確實會真的多打幾次 API，但
        // 抓過的都存進本機快取，第二次開同一個頻道多半直接從快取秒出、
        // 不用再打 API（見 `_loadMoreVideos` 「先查本機快取」那段），
        // 使用者決定這個代價無所謂（2026-09-30）。
        if (visibleVideos.length < _loadMoreBatch &&
            !reachedEnd &&
            !loading &&
            error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) loadMore();
          });
        }
        // 用 Column 不用 ListView.separated——這塊現在是外層
        // SingleChildScrollView 的一部分，自己不用再是獨立的可捲動
        // 區域（見 build() 的說明：簡介／圖表／影片要一起滑動）。
        return Column(
          children: [
            if (visibleVideos.isEmpty && !loading)
              _filteredEmptyCard(channel, videos, isTyped),
            _videoRows(visibleVideos),
            // 往下滑到底會自動載入更早的影片；載入中轉圈、失敗給重試、
            // 沒有更多了就說一聲。
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : error != null
                  ? Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            if (isTyped) {
                              _typedError = null;
                            } else {
                              _loadMoreError = null;
                            }
                          });
                          loadMore();
                        },
                        child: Text('載入失敗：$error（點一下重試）'),
                      ),
                    )
                  : reachedEnd
                  ? Center(
                      child: Text(
                        isTyped ? '共 ${videos.length} 部' : '沒有更早的影片了',
                        style: AppText.note,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  /// 篩選完一部都不剩時的空狀態：直接算給使用者看是誰把影片收起來的，
  /// 每個原因配一顆解除按鈕（2026-10-02 選的第 5 版空狀態；原本只有
  /// 「沒有符合目前篩選條件的影片」一行灰字，不說原因，之前就被誤會成
  /// 「連沒看過的影片也一起藏起來了」）。
  Widget _filteredEmptyCard(
    YtChannel channel,
    List<YoutubeVideo> loaded,
    bool isTyped,
  ) {
    final hiddenByUser = loaded
        .where((v) => _hiddenVideoIds.contains(v.videoId))
        .length;
    final watched = loaded
        .where(
          (v) =>
              !_hiddenVideoIds.contains(v.videoId) &&
              _watchedVideoIds.contains(v.videoId),
        )
        .length;
    final reasons = <String>[
      if (loaded.isEmpty && isTyped) '這個頻道沒有這個類型的影片',
      if (_hideWatched && watched > 0) '$watched 部已看過的被收起來了',
      if (!_showHiddenVideos && hiddenByUser > 0) '$hiddenByUser 部是你隱藏的',
    ];
    return InlineEmptyCard(
      title: '這裡空空的',
      message: reasons.isEmpty ? '目前的篩選下沒有影片' : reasons.join('，'),
      actions: [
        if (_hideWatched && watched > 0)
          EmptyAction('顯示已看過', () => setState(() => _hideWatched = false)),
        if (!_showHiddenVideos && hiddenByUser > 0)
          EmptyAction('顯示已隱藏', () => setState(() => _showHiddenVideos = true)),
        if (isTyped)
          EmptyAction('看全部類型', () => _switchTypeFilter(_TypeFilter.all)),
        EmptyAction('重新整理', () => _refresh(channel)),
      ],
    );
  }

  Future<void> _showEditDialog(
    YtChannel channel,
    List<YtCategory> categories,
  ) async {
    final nameController = TextEditingController(text: channel.name);
    final urlController = TextEditingController(text: channel.url);
    final avatarController = TextEditingController(
      text: channel.avatarImageUrl,
    );
    final descriptionController = TextEditingController(
      text: channel.description,
    );
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
                  decoration: InputDecoration(
                    labelText: '頻道網址',
                    // 旁邊放一顆小貼上按鈕，不用整段刪掉重打
                    // （2026-09-29 使用者要求）。
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.content_paste_go_rounded,
                        size: 18,
                      ),
                      tooltip: '貼上',
                      onPressed: () async {
                        String? text;
                        try {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          text = data?.text?.trim();
                        } catch (_) {
                          // 權限被擋、瀏覽器不支援：當沒讀到，不影響再按一次。
                        }
                        if (text == null || text.isEmpty) return;
                        urlController.text = text;
                        setDialogState(() {});
                      },
                    ),
                  ),
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
                // 刪除是破壞性動作：跟一般的「取消／儲存」分開，獨立放在
                // 內容最底下、紅色外框全寬按鈕（一般手機 App 的慣例），不跟
                // 底部按鈕列擠在一起，也不用紅色實心搶過主要動作
                // （2026-09-24 使用者要求重新配置）。
                const SizedBox(height: Gap.lg),
                const Divider(height: 1, color: AppColors.glassEdge),
                const SizedBox(height: Gap.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'delete'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('刪除頻道'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.bad,
                      side: BorderSide(
                        color: AppColors.bad.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 底部按鈕列照慣例：次要的「取消」在左（純文字），主要的「儲存」
          // 在最右（實心強調色，用藍色不是紅色——紅色留給刪除）。
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('儲存'),
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
        // 用 copyWith 保留已解析的頻道 ID／上傳清單 ID／訂閱人數（原本整個
        // 重建會把這些洗掉，編輯完下次又要重新問 API）。
        channel.copyWith(
          name: name,
          categoryId: categoryId,
          avatarImageUrl: avatarController.text.trim(),
          url: urlController.text.trim(),
          description: descriptionController.text.trim(),
        ),
      );
      if (!mounted) return;
      _reload();
    } else if (action == 'delete') {
      if (!mounted) return;
      final confirmed = await showAppConfirmDialog(
        context,
        title: '刪除這個頻道？',
        message: '這個動作無法復原。',
        confirmLabel: '刪除',
      );
      if (!confirmed) return;
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
                      final category = categories.where(
                        (c) => c.id == channel.categoryId,
                      );
                      final categoryLabel = category.isEmpty
                          ? '未分類'
                          : category.first.name;

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
                              controller: _scroll,
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
                  Text(
                    channel.subscriberLabel == null
                        ? categoryLabel
                        : '$categoryLabel・${channel.subscriberLabel}',
                    style: AppText.note,
                  ),
                  if (channel.url.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => openExternalUrl(context, channel.url),
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
            Text(
              // 2026-09-30 使用者指出：叫「最近影片」不準確，往下滑其實
              // 能一路翻到頻道最早的影片，不是只有「最近」這一小段；括號
              // 裡的總數是 `channels.list` 的 `videoCount`（全部類型合計，
              // 不分一般影片／Shorts／直播——API 沒有分類型的統計，見
              // `YoutubeChannelInfo.videoCount` 的說明），還沒問到就先不
              // 顯示數字，不要顯示假的 0。
              channel.videoCount == null
                  ? '全部影片'
                  : '全部影片 (${channel.videoCount})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _refresh(channel),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('重新整理'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink2,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        _buildVideoFilterRow(),
        const SizedBox(height: Gap.sm),
        _buildVideos(channel),
      ],
    );
  }

  /// 類型篩選（全部／一般影片／Shorts／直播，2026-09-30 使用者要求）＋
  /// 「隱藏已看過」／「顯示已隱藏」兩個開關，加一顆「隱藏所有看過的」
  /// 一次性動作。類型篩選跟另外兩個開關概念不一樣（互斥單選 vs 各自
  /// 獨立開關），用 [_Pick]（這個檔案裡挑分類對話框同一顆元件）而不是
  /// `FilterChip`，單選視覺才對。
  Widget _buildVideoFilterRow() {
    // 開關旁邊顯示有幾部可以處理（2026-10-05 使用者要求）：看過幾部、被
    // 隱藏幾部，兩個各算各的——隱藏的影片如果也看過，兩邊都算（使用者
    // 要求一起算）。0 就不顯示數字。「全部」算這個
    // 頻道整份本機快取＋這次新抓的（依影片 ID 去重）；選了特定類型時
    // 快取分不出類型，只能算這個類型已經抓進來的那些。
    final loaded = _typeFilter == _TypeFilter.all
        ? {
            for (final v in [
              ..._cachedChannelVideos,
              ..._firstPage,
              ..._moreVideos,
            ])
              v.videoId: v,
          }.values.toList()
        : _typedVideos;
    final hiddenCount = loaded
        .where((v) => _hiddenVideoIds.contains(v.videoId))
        .length;
    final watchedCount = loaded
        .where((v) => _watchedVideoIds.contains(v.videoId))
        .length;
    String withCount(String label, int n) => n > 0 ? '$label ($n)' : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Pick(
              label: '全部',
              color: AppColors.accentSolid,
              selected: _typeFilter == _TypeFilter.all,
              onTap: () => _switchTypeFilter(_TypeFilter.all),
            ),
            _Pick(
              label: '一般影片',
              color: AppColors.accentSolid,
              selected: _typeFilter == _TypeFilter.regular,
              onTap: () => _switchTypeFilter(_TypeFilter.regular),
            ),
            _Pick(
              label: 'Shorts',
              color: AppColors.accentSolid,
              selected: _typeFilter == _TypeFilter.shorts,
              onTap: () => _switchTypeFilter(_TypeFilter.shorts),
            ),
            _Pick(
              label: '直播',
              color: AppColors.accentSolid,
              selected: _typeFilter == _TypeFilter.live,
              onTap: () => _switchTypeFilter(_TypeFilter.live),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 選中用一般藍色主色，不用 ytAccent 的紅——這兩個是普通篩選開關，
            // 不是危險動作，紅色太搶眼也不合適（2026-09-30 使用者要求，跟
            // 設定頁「儲存」按鈕那次同一個理由）。
            FilterChip(
              label: Text(withCount('隱藏已看過', watchedCount)),
              selected: _hideWatched,
              // 不顯示打勾圖示（2026-09-30 使用者回報：切開/關會多/少那個勾勾
              // 圖示，導致按鈕本身寬度跟著變、旁邊的「顯示已隱藏」也被推著
              // 移動——選中/沒選中已經有底色跟外框顏色可以分辨，不需要再靠
              // 圖示，維持固定寬度比較重要）。
              showCheckmark: false,
              // 點這顆（不管切成開還是關）都重新讀一次「已看過」清單
              // （2026-09-30 使用者要求：看了好幾部之後，這個開關本來
              // 讀進來的清單是舊的，不會包含這個 session 剛看過的，導致
              // 篩選結果很怪；不用跳出頻道頁再回來才更新，點這顆本身
              // 就順便刷新）。
              onSelected: (v) {
                setState(() => _hideWatched = v);
                _loadVideoFilters();
              },
              backgroundColor: AppColors.glassFill,
              selectedColor: AppColors.accentSolid.withValues(alpha: 0.28),
              labelStyle: TextStyle(
                fontSize: 12.5,
                color: _hideWatched ? AppColors.ink : AppColors.ink2,
              ),
              side: BorderSide(
                color: _hideWatched
                    ? AppColors.accentSolid
                    : AppColors.glassEdge,
              ),
            ),
            FilterChip(
              label: Text(withCount('顯示已隱藏', hiddenCount)),
              selected: _showHiddenVideos,
              showCheckmark: false,
              onSelected: (v) => setState(() => _showHiddenVideos = v),
              backgroundColor: AppColors.glassFill,
              selectedColor: AppColors.accentSolid.withValues(alpha: 0.28),
              labelStyle: TextStyle(
                fontSize: 12.5,
                color: _showHiddenVideos ? AppColors.ink : AppColors.ink2,
              ),
              side: BorderSide(
                color: _showHiddenVideos
                    ? AppColors.accentSolid
                    : AppColors.glassEdge,
              ),
            ),
          ],
        ),
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
