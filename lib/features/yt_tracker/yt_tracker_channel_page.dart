import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_channel_log_store.dart';
import '../../data/repositories/yt_display_prefs_store.dart';
import '../../data/repositories/yt_search_recents_store.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/repositories/yt_video_hidden_store.dart';
import '../../data/repositories/yt_video_views.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../data/services/yt_channel_filler.dart';
import '../../data/services/yt_channel_search.dart';
import '../../data/services/yt_removed_video_checker.dart';
import '../../data/services/yt_view_count_refresher.dart';
import '../../data/services/yt_video_type_scanner.dart';
import '../../domain/models/yt_tracker.dart';
import '../../domain/models/yt_video_watch.dart';
import '../../shared/snap_to_edge.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/background_refresh.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'upload_frequency_chart.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';
import 'yt_channel_edit_header.dart';
import 'yt_channel_log_page.dart';
import 'yt_channel_stats.dart';
import 'yt_duration_filter.dart';
import 'yt_video_row.dart';

/// 「影片」清單的類型篩選，跟 `yt_tracker_browse_page.dart` 的
/// `_TypeFilter` 同一個概念、各自獨立一份（2026-09-30 使用者要求：
/// 頻道詳情頁也要能直接篩全部／一般影片／Shorts／直播）。
///
/// [removed]＝「已下架」（2026-10-12 使用者要求）：下架檢查查到有影片
/// 被刪除或改成私人才出現這顆，列出快取裡標了下架的那些，不打 API。
enum _TypeFilter { all, regular, shorts, live, removed }

/// 頻道詳情頁的分頁（2026-10-15 使用者選設計稿
/// `design-history/2026-10-15_YT頻道詳情頁五種設計.html` 第 1 版「YouTube
/// 式分頁」，順序照使用者指定：全部／Shorts／直播／簡介／觀看紀錄）。
enum _ChannelTab {
  all('全部'),
  shorts('Shorts'),
  live('直播'),
  about('簡介'),
  watch('觀看紀錄');

  const _ChannelTab(this.label);
  final String label;
}

/// 影片排序（同一份設計稿第 1 版：分頁下面一排最新／熱門／最舊）。
/// 熱門看觀看次數（見 [YoutubeVideo.viewCount]）。
enum _Sort {
  newest('最新'),
  popular('熱門'),
  oldest('最舊');

  const _Sort(this.label);
  final String label;
}

/// 頻道詳情。基本資料（名稱、分類、網址、簡介）可以編輯（刪除在分類頁長按），網址點
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

  /// 往下滑超過這麼多才出現右下角「回到最上面」（2026-10-12 使用者要求）。
  static const _backToTopAfter = 600.0;
  bool _showBackToTop = false;

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

  /// 「上傳頻率」摺線圖用的近半年影片，跟「最近影片」分開抓、分開快取
  /// ——這支可能要翻好幾頁 API、抓不少影片的時長，比最近影片貴；半年內
  /// 的資料不會突然變，只要同一個頻道同一次進頁面抓過一次就夠，只有手動
  /// 按重新整理（跟最近影片共用那顆按鈕）才會強制重抓。
  Future<List<YoutubeVideo>>? _historyFuture;

  /// 快取有點舊、背景補抓新影片期間，先拿本機資料把圖畫出來的預覽。
  List<YoutubeVideo>? _historyPreview;
  String? _historyLoadedForChannelId;

  /// 「最近影片」清單的顯示篩選（2026-09-30 使用者要求）：預設把已經看
  /// 過的影片收起來，專心看還沒看的；隱藏過的影片預設也不顯示，開關
  /// 開了才連同已隱藏的一起看（給「隱藏所有看過的」用完之後想回頭review
  /// 用）。這兩個集合只在這頁載入一次，個別影片列自己滑動隱藏／取消
  /// 隱藏之後靠 [YtVideoRow.onHiddenChanged] 通知這裡重新讀一次。
  Set<String> _watchedVideoIds = {};
  Set<String> _hiddenVideoIds = {};

  /// 看過紀錄整份（影片 id → 每次點開的時間），頁面讀一次交給每一列，
  /// 不讓每一列自己讀（見 [YtVideoRow.known]）。
  Map<String, YtVideoWatchRecord> _watchedRecords = {};
  bool _hideWatched = true;
  bool _showHiddenVideos = false;

  // 哪些 videoId 這次是從本機快取讀到的、不是真的打 API 抓來的
  // （2026-09-30 使用者要求：想在畫面上看出哪些是秒出來、不用配額的）。
  // 「全部」的 `_loadMoreVideos` 跟類型篩選的 `_openTypedFilter`／
  // `_loadTypedVideos` 都會往這裡加——兩邊都是先查本機快取、快取用完才
  // 打 API（類型篩選 2026-10-05 起也是）。
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
  // 選「全部」以外的類型時，先用快取裡標好這個類型的影片，快取用完才翻
  // 那個類型自己的特殊清單（見 `_openTypedFilter`／`_loadTypedVideos`），
  // 是一份跟「全部」完全分開的分頁狀態——自己的到底旗標、自己那份
  // resume（`YtVideoCacheStore.loadResume` 的 `kind`），不跟 `_firstPage`／
  // `_moreVideos`／「全部」的 resume 共用，兩邊翻頁位置是對應不同清單，
  // 混在一起會對不上。
  _TypeFilter _typeFilter = _TypeFilter.all;
  _ChannelTab _tab = _ChannelTab.all;
  _Sort _sort = _Sort.newest;

  /// 時長篩選（2026-10-06，見 [YtDurationFilter]）。只是把已載入的影片
  /// 篩一遍，不另外打 API；離開頁面就回到「不限」。
  YtDurationFilter _durationFilter = const YtDurationFilter.any();

  // 「篩選完可見清單太短就主動幫忙多抓一批」的保險（見下面
  // `_buildVideos` 裡的說明）沒有設上限——使用者曾問「看過的量一大，
  // 每次打開頻道頁是不是都要燒好幾個配額單位」，答案是本機快取住之後
  // 第二次開多半直接從快取秒出（見 `_loadMoreVideos` 「先查本機快取」
  // 那段），不用真的打 API；第一次確實會真的多打幾次，但使用者決定
  // 這個代價無所謂，不用另外設上限、多一個「再載入」按鈕的麻煩
  // （2026-09-30 使用者要求）。
  List<YoutubeVideo> _typedVideos = const [];
  bool _typeScanRunning = false;

  /// 掃描跑到一半又有人要求重掃（往下捲抓到更早的影片）：記下來，這輪
  /// 跑完馬上再掃一次。以前直接忽略，新抓到的那幾部就一直沒標類型
  /// （2026-10-08 使用者回報偶爾漏標）。
  bool _typeScanAgain = false;
  String? _typeScannedChannelId;
  DateTime? _typeScannedAt;
  bool _typedReachedEnd = false;
  bool _typedLoading = false;
  String? _typedError;

  /// 頻道頁搜尋（2026-10-14 使用者選了設計稿第 1 版「頂部放大鏡」，
  /// YouTube App 頻道頁就是這樣）：點右上角 🔍，整條頂部列變成搜尋框，
  /// 按 Enter 後下面整頁換成結果；← 收起回到原本的頁面、原本的位置。
  /// 怎麼找見 [YtChannelSearch]。
  ///
  /// 2026-10-15 使用者要求：點 🔍 鍵盤就跳出來；打一個字就搜一次（不用按
  /// Enter）；只搜快取，不自己打 API（見 [YtChannelSearch]）。
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _typeDebounce;
  YtChannelSearch? _search;
  List<String> _recents = const [];
  double _scrollBeforeSearch = 0;

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
      _watchedRecords = watched;
      _watchedVideoIds = watched.keys.toSet();
      _hiddenVideoIds = hidden;
    });
  }

  @override
  void dispose() {
    _search?.cancel();
    _search?.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _typeDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSearch() async {
    // 一定要在點下去的當下要焦點，iPhone 才會跳鍵盤（晚一點才要，Safari
    // 會擋）；搜尋框平常就在（看不見），所以這時要得到。
    _searchFocus.requestFocus();
    _scrollBeforeSearch = _scroll.hasClients ? _scroll.offset : 0;
    setState(() => _searchOpen = true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    final recents = await YtSearchRecentsStore(
      ref.read(keyValueStoreProvider),
    ).load();
    if (mounted) setState(() => _recents = recents);
  }

  void _stopSearch() {
    _search?.cancel();
    _search?.dispose();
    _search = null;
  }

  Widget _topBar(YtChannel channel) {
    return AppTopBar(
      title: _draft?.name ?? channel.name,
      // 名字太長走馬燈（2026-10-12 使用者要求）。
      marqueeTitle: true,
      showSettings: !_editing,
      // 順序：編輯、紀錄（2026-10-06 使用者要求紀錄放
      // 編輯右邊）。刪除鈕 2026-10-12 拿掉：分類頁長按
      // 就能刪（使用者要求）。
      actions: _editing
          ? [
              TextButton(
                onPressed: _cancelEdit,
                style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _doneEdit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ]
          : [
              IconButton(
                onPressed: _openSearch,
                icon: const Icon(Icons.search_rounded, size: 21),
                color: AppColors.ink2,
                tooltip: '搜尋這個頻道的影片',
              ),
              IconButton(
                onPressed: () => _startEdit(channel),
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: AppColors.ink2,
                tooltip: '編輯頻道',
              ),
              // 頻道紀錄（2026-10-06）：看影片、換分類、刪除還原…
              IconButton(
                onPressed: () =>
                    context.push('/yt-tracker/channel/${channel.id}/log'),
                icon: const Icon(Icons.history_rounded, size: 20),
                color: AppColors.ink2,
                tooltip: '紀錄',
              ),
            ],
    );
  }

  /// 注音（含聲調）。打字中還有注音＝還沒選字，先不搜（2026-10-15 使用者
  /// 回報）。原本看輸入法「組字中」（底線），但 iPhone 選完字常常還算在
  /// 組字，就一直不搜，所以改成只看有沒有注音。
  static final _bopomofo = RegExp(r'[㄀-ㄯㆠ-ㆿ˙ˊˇˋ]');

  void _onSearchTyped(YtChannel channel, String text) {
    _typeDebounce?.cancel();
    if (_bopomofo.hasMatch(text)) return;
    _typeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !_searchOpen) return;
      _submitSearch(channel, text, typing: true);
    });
  }

  void _closeSearch() {
    _typeDebounce?.cancel();
    _searchFocus.unfocus();
    _stopSearch();
    _searchCtrl.clear();
    setState(() => _searchOpen = false);
    // 回到開搜尋前看到的地方。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
        _scrollBeforeSearch.clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  void _clearSearch() {
    _stopSearch();
    _searchCtrl.clear();
    setState(() {});
  }

  /// [typing]＝邊打邊搜：不收鍵盤、不記進最近搜尋（按 Enter 才記）。
  Future<void> _submitSearch(
    YtChannel channel,
    String query, {
    bool typing = false,
  }) async {
    _typeDebounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) return _clearSearch();
    if (!typing && _searchCtrl.text != q) _searchCtrl.text = q;
    _stopSearch();
    final store = ref.read(keyValueStoreProvider);
    final search = YtChannelSearch(
      channelId: channel.id,
      query: q,
      cache: YtVideoCacheStore(store),
      totalOnYoutube: channel.videoCount,
      fill: () => YtChannelFiller.of(channel.id).current,
    )..addListener(_onSearchChanged);
    setState(() => _search = search);
    if (typing) return search.run();
    FocusManager.instance.primaryFocus?.unfocus();
    final recents = await YtSearchRecentsStore(store).add(q);
    if (mounted) setState(() => _recents = recents);
    await search.run();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// 設定開著才包一層一直顯示、可拖的捲動條（2026-10-12 使用者要求）。
  Widget _withScrollbar(bool show, Widget child) => show
      ? Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          child: child,
        )
      : child;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final showTop = pos.pixels > _backToTopAfter;
    if (showTop != _showBackToTop) setState(() => _showBackToTop = showTop);
    if (_searchOpen) return;
    if (!_isVideoTab || _sort != _Sort.newest) return;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    // 選了特定類型就是翻那個類型自己的清單，跟「全部」是兩份分開的
    // 分頁狀態，見 `_loadTypedVideos` 的說明。
    if (_typeFilter == _TypeFilter.all) {
      _loadMoreVideos();
    } else {
      _loadTypedVideos();
    }
  }

  /// 把快取裡已經標好的類型套到這份影片上。剛從 YouTube 抓下來的影片
  /// 物件本身不帶類型，快取裡那份才有（掃描、翻類型清單時標的）——不套
  /// 的話縮圖左下角的「影片／Shorts／直播」標籤永遠不會出現（2026-10-06
  /// 使用者回報「影片標籤還是沒補上」）。
  static List<YoutubeVideo> _applyTags(
    List<YoutubeVideo> list,
    Map<String, YoutubeVideo> cachedById,
  ) => [
    for (final v in list)
      if (cachedById[v.videoId] case final c?) _copyTags(v, c) else v,
  ];

  static YoutubeVideo _copyTags(YoutubeVideo v, YoutubeVideo from) {
    var r = v;
    if (r.isShort == null && from.isShort != null) {
      r = r.withShort(from.isShort!);
    }
    if (r.isLive == null && from.isLive != null) r = r.withLive(from.isLive!);
    return r;
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

      // 背景正在把整個頻道抓進快取：等它下一頁，再從快取拿（不重複打 API）。
      final filler = YtChannelFiller.of(channelId);
      if (filler.running) {
        await filler.nextTick();
        if (!mounted) return;
        setState(() => _loadingMore = false);
        return _loadMoreVideos();
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
      // 「全部」往更早翻了，Shorts／直播的掃描也跟著往更早延伸。
      if (fresh.isNotEmpty) _scanVideoTypes(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = '$e';
      });
    }
  }

  /// 背景把這個頻道的 Shorts（UUSH）跟直播（UULV）清單翻過，標進影片
  /// 快取的類型（2026-10-05 使用者要求：一開始就把類型標好，類型篩選的
  /// 數字才準，不用等自己去點類型才慢慢補）。
  ///
  /// 只補快取裡還沒標類型的影片，全部都標過就不打 API；怎麼省配額見
  /// [YtVideoTypeScanner]。「全部」往下捲抓到更早的影片時再叫一次（見
  /// [_loadMoreVideos] 最後），補那些新抓到的。
  ///
  /// 等「全部」第一頁跟上傳頻率圖都抓完才開始，不跟它們搶著寫同一份快取；
  /// 失敗（網路、配額）就算了，下次打開再掃，不影響畫面。
  ///
  /// 觸發點在 build 的畫完回呼裡，每次重繪都會叫到，所以同一個頻道
  /// 進頁面只掃一次（2026-10-06 使用者決定：待在頁面上不自動更新）；
  /// [force]（按重新整理、「全部」往下翻到更早）不受這個限制。
  Future<void> _scanVideoTypes({bool force = false}) async {
    if (_typeScanRunning) {
      if (force) _typeScanAgain = true;
      return;
    }
    final sameChannel = _typeScannedChannelId == _loadMoreChannelId;
    if (!force && sameChannel && _typeScannedAt != null) return;
    _typeScannedChannelId = _loadMoreChannelId;
    _typeScannedAt = DateTime.now();
    _typeScanRunning = true;
    try {
      try {
        await _videosFuture;
        await _historyFuture;
      } catch (_) {
        // 它們自己的錯誤自己會顯示，這裡只是等它們跑完。
      }
      final apiKey = ref.read(ytApiKeyProvider);
      final uploadsId = _uploadsId;
      final channelId = _loadMoreChannelId;
      if (!mounted ||
          apiKey == null ||
          apiKey.isEmpty ||
          uploadsId == null ||
          !uploadsId.startsWith('UU') ||
          channelId == null) {
        return;
      }
      final kv = ref.read(keyValueStoreProvider);
      final cache = YtVideoCacheStore(kv);
      await YtVideoTypeScanner(
        YoutubeApiService(apiKey),
        kv,
      ).tagUntagged(channelId: channelId, uploadsId: uploadsId);
      // 不管這次有沒有新標到，都把快取裡的類型套到畫面上的清單（快取
      // 可能早就標好了，例如之前按過「補齊影片類型」）。
      if (mounted && _loadMoreChannelId == channelId) {
        final fresh = await cache.load(channelId);
        // 畫面上已經列出來的影片也換成標好類型的那份，縮圖左下角的
        // 「影片／Shorts／直播」標籤馬上出現，不用離開再進來
        // （2026-10-06 使用者問「新抓到的影片怎麼還是沒有小標籤」）。
        final byId = {for (final v in fresh) v.videoId: v};
        List<YoutubeVideo> retag(List<YoutubeVideo> list) =>
            _applyTags(list, byId);
        if (mounted) {
          setState(() {
            _cachedChannelVideos = fresh;
            _firstPage = retag(_firstPage);
            _moreVideos = retag(_moreVideos);
            _typedVideos = retag(_typedVideos);
          });
        }
      }
    } catch (_) {
      // 背景工作，失敗就下次再掃。
    } finally {
      _typeScanRunning = false;
      if (_typeScanAgain && mounted) {
        _typeScanAgain = false;
        _scanVideoTypes(force: true);
      }
    }
  }

  Future<({YtChannel? channel, List<YtCategory> categories})> _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    // 包含垃圾桶裡的頻道：垃圾桶點頻道也要能進來逛（2026-10-06 使用者
    // 要求垃圾桶跟一般分類頁完全一樣）。
    final channels = await repo.channelsForUpload();
    final categories = await repo.loadCategories();
    final channel = channels.where((c) => c.id == widget.channelId);
    return (
      channel: channel.isEmpty ? null : channel.first,
      categories: categories,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  void _ensureVideosLoaded(YtChannel channel, {bool force = false}) {
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    final sameChannel = _videosLoadedForChannelId == channel.id;
    // 待在這頁上不會自動更新（2026-10-06 使用者決定）：原本超過 5 分鐘
    // 任何一次重繪（隱藏影片、切篩選、往下載入）都會整份清空重抓，捲動
    // 跳回最上面。現在只有進這頁、按重新整理才抓。
    if (!force && sameChannel) return;
    _videosLoadedForChannelId = channel.id;
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
    // 背景把整個頻道抓完（2026-10-14 使用者要求）：先讀快取的狀態（有幾部、
    // 抓完了沒），第一頁出來後再開始，不跟第一頁搶。
    final filler = YtChannelFiller.of(channel.id);
    filler.loadStatus(YtVideoCacheStore(ref.read(keyValueStoreProvider)));
    _videosFuture!.then((_) {
      if (!mounted || _videosLoadedForChannelId != channel.id) return;
      if (!ref.read(ytDisplayPrefsProvider).autoFillChannel) return;
      filler.start(
        cache: YtVideoCacheStore(ref.read(keyValueStoreProvider)),
        api: YoutubeApiService(apiKey),
        uploadsId: () async =>
            _uploadsId ??
            (channel.uploadsPlaylistId.isEmpty
                ? null
                : channel.uploadsPlaylistId),
      );
    }, onError: (_) {});
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
    _scanVideoTypes(force: true);
    // 目前如果正看著特定類型，重新整理也要連那份分開的分頁狀態一起
    // 重抓，不然按了重新整理、類型篩選那份還是舊的。
    if (_typeFilter == _TypeFilter.removed) {
      _showRemovedFromCache();
    } else if (_typeFilter != _TypeFilter.all) {
      setState(() {
        _typedVideos = const [];
        _typedReachedEnd = false;
        _typedLoading = false;
        _typedError = null;
      });
      _openTypedFilter();
    }
  }

  /// 「隱藏已看過」「顯示已隱藏」兩個開關套用後，這支影片要不要出現。
  bool _passesBaseFilters(YoutubeVideo v) {
    if (_hiddenVideoIds.contains(v.videoId)) return _showHiddenVideos;
    return !(_hideWatched && _watchedVideoIds.contains(v.videoId));
  }

  /// 再加上時長篩選。
  bool _passesFilters(YoutubeVideo v) =>
      _passesBaseFilters(v) && _durationFilter.matches(v);

  /// 影片清單：捲到才建（2026-10-06 使用者要求）。原本是 Column 一次把
  /// 所有載入過的影片列全部建出來，往下滑幾批之後頁面上同時掛著兩三百列，
  /// 每次切篩選、隱藏一部、背景補完標籤，全部都要重算一次；改成清單只建
  /// 畫面上看得到的（上下多準備一小段），捲過去的收掉，縮圖有圖片快取，
  /// 捲回來不用重新下載。
  Widget _videoRows(
    YtChannel channel,
    List<YoutubeVideo> list, {
    bool allFromCache = false,
    String? highlight,
    Set<String> justFetched = const {},
    bool forceShowHidden = false,
  }) => SliverList.separated(
    itemCount: list.length,
    separatorBuilder: (_, _) =>
        const Divider(height: 1, color: AppColors.glassEdge),
    itemBuilder: (_, i) => _videoRow(
      channel,
      list[i],
      allFromCache: allFromCache,
      highlight: highlight,
      justFetched: justFetched,
      forceShowHidden: forceShowHidden,
    ),
  );

  Widget _videoRow(
    YtChannel channel,
    YoutubeVideo v, {
    bool allFromCache = false,
    String? highlight,
    Set<String> justFetched = const {},
    bool forceShowHidden = false,
  }) => YtVideoRow(
    // 一定要給明確的 key，理由跟 yt_tracker_browse_page.dart
    // 那邊一樣：篩選開關一切換，清單位置就會洗牌，沒有 key
    // 的話 Flutter 照位置重用 State，「已看過」狀態會錯配到
    // 別支影片上（2026-09-30 使用者回報抓到）。
    key: ValueKey(v.videoId),
    video: v,
    channelId: channel.id,
    channelName: channel.name,
    subtitle: justFetched.contains(v.videoId)
        ? '${ytRelativeTime(v.publishedAt)}・剛從 YouTube 抓到'
        : ytRelativeTime(v.publishedAt),
    highlight: highlight,
    forceShow: forceShowHidden || _hiddenVideoIds.contains(v.videoId),
    known: (
      watched: _watchedRecords[v.videoId],
      hidden: _hiddenVideoIds.contains(v.videoId),
    ),
    // 點開影片：只更新這一筆，不用整份重讀。
    onWatchedChanged: (record) => setState(() {
      _watchedRecords = {..._watchedRecords, v.videoId: record};
      _watchedVideoIds = {..._watchedVideoIds, v.videoId};
    }),
    onHiddenChanged: _loadVideoFilters,
    fromCache: allFromCache || _cachedVideoIds.contains(v.videoId),
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
      _typedReachedEnd = false;
      _typedLoading = false;
      _typedError = null;
    });
    if (next == _TypeFilter.removed) {
      _showRemovedFromCache();
    } else if (next != _TypeFilter.all) {
      _openTypedFilter();
    }
  }

  /// 「已下架」分類：直接列快取裡標了下架的影片，新到舊，不打 API。
  void _showRemovedFromCache() {
    final removed =
        _cachedChannelVideos.where((v) => v.removedAt != null).toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    setState(() {
      _typedVideos = removed;
      _typedReachedEnd = true;
      _typedLoading = false;
      _typedError = null;
    });
  }

  /// 下架檢查（2026-10-12 使用者要求）：超過兩週沒查就背景查一次。只把
  /// 本機儲存跟金鑰交給 [YtRemovedVideoChecker]，不靠這個頁面——點進來
  /// 馬上退出也會跑完、寫回快取。還在這頁的話，查完把畫面上的影片換成
  /// 標好的那份，有新下架的提示一下。
  String? _removedCheckStartedFor;

  /// 觀看次數（2026-10-15 使用者要求）：進頻道才觸發，超過設定天數沒更新
  /// 的影片在背景重抓，不綁頁面（跟下架檢查一樣）。抓到的寫回快取、發布
  /// 到 [YtVideoViews]，畫面上的影片列自己會更新。
  String? _viewsStartedFor;

  void _refreshViewCounts(YtChannel channel) {
    if (_viewsStartedFor == channel.id) return;
    _viewsStartedFor = channel.id;
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    final days = ref.read(ytDisplayPrefsProvider).viewsRefreshDays;
    if (days <= 0) return;
    YtViewCountRefresher(
      ref.read(keyValueStoreProvider),
      YoutubeApiService(apiKey),
    ).refreshIfDue(channel.id, every: Duration(days: days)).catchError((_) {
      // 配額用完、沒網路：下次進來再說。
      return 0;
    });
  }

  Future<void> _checkRemovedVideos(YtChannel channel) async {
    if (_removedCheckStartedFor == channel.id) return;
    _removedCheckStartedFor = channel.id;
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    // 多久查一次照設定（0＝不檢查）。
    final days = ref.read(ytDisplayPrefsProvider).removedCheckDays;
    if (days <= 0) return;
    final kv = ref.read(keyValueStoreProvider);
    int? found;
    try {
      found = await YtRemovedVideoChecker(
        kv,
        YoutubeApiService(apiKey),
      ).checkIfDue(channel.id, every: Duration(days: days));
    } catch (_) {
      // 配額用完、沒網路：這次就不查，下次打開再說，不打擾使用者。
      return;
    }
    if (found == null || !mounted || _loadMoreChannelId != channel.id) return;
    final fresh = await YtVideoCacheStore(kv).load(channel.id);
    if (!mounted || _loadMoreChannelId != channel.id) return;
    final byId = {for (final v in fresh) v.videoId: v};
    List<YoutubeVideo> swap(List<YoutubeVideo> list) => [
      for (final v in list) byId[v.videoId] ?? v,
    ];
    setState(() {
      _cachedChannelVideos = fresh;
      _cachePreview = swap(_cachePreview);
      _firstPage = swap(_firstPage);
      _moreVideos = swap(_moreVideos);
      _typedVideos = swap(_typedVideos);
    });
    if (_typeFilter == _TypeFilter.removed) _showRemovedFromCache();
    if (found > 0) {
      showAppNotice(
        context,
        '發現 $found 部影片已下架',
        detail: '被刪除或改成私人，點「已下架」看是哪幾部',
      );
    }
  }

  String? _typedPlaylistId() {
    final uploadsId = _uploadsId;
    if (uploadsId == null || !uploadsId.startsWith('UU')) return null;
    final rest = uploadsId.substring(2);
    return switch (_typeFilter) {
      _TypeFilter.shorts => 'UUSH$rest',
      _TypeFilter.live => 'UULV$rest',
      _TypeFilter.regular => 'UULF$rest',
      _TypeFilter.all || _TypeFilter.removed => null,
    };
  }

  /// 快取裡這部影片是不是 [type] 這個類型（看類型標籤，還沒標的不算）。
  bool _isOfType(YoutubeVideo v, _TypeFilter type) => switch (type) {
    _TypeFilter.all => true,
    _TypeFilter.shorts => v.isShort == true,
    _TypeFilter.live => v.isLive == true,
    _TypeFilter.regular => v.isShort == false && v.isLive == false,
    _TypeFilter.removed => v.removedAt != null,
  };

  /// 從類型清單抓到的影片，標上它所屬的類型。
  YoutubeVideo _tagAs(YoutubeVideo v, _TypeFilter type) => switch (type) {
    _TypeFilter.shorts => v.withShort(true).withLive(false),
    _TypeFilter.live => v.withShort(false).withLive(true),
    _TypeFilter.regular => v.withShort(false).withLive(false),
    _TypeFilter.all || _TypeFilter.removed => v,
  };

  /// 打開某個類型（2026-10-05 使用者要求：跟「全部」一樣先用快取，再檢查
  /// 有沒有新影片補上去，不要每次都整頁重打 API）：
  /// 1. 先把快取裡已經標成這個類型的影片拿出來顯示，不打 API。
  /// 2. 從這個類型清單最新的那頁往下翻，碰到快取已經有的影片就停，新的
  ///    補時長、存快取、插進畫面。快取裡這類型一部都沒有（第一次看）
  ///    就只翻 1 頁當第一頁，不一路翻到底。
  /// 往下捲要更早的交給 [_loadTypedVideos]。
  Future<void> _openTypedFilter() async {
    final type = _typeFilter;
    final channelId = _loadMoreChannelId;
    final playlistId = _typedPlaylistId();
    final apiKey = ref.read(ytApiKeyProvider);
    if (channelId == null ||
        playlistId == null ||
        apiKey == null ||
        apiKey.isEmpty) {
      return;
    }
    setState(() => _typedLoading = true);
    final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    final cached = await cache.load(channelId);
    final ofType = cached.where((v) => _isOfType(v, type)).toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final fromCache = ofType.take(_loadMoreBatch).toList();
    if (!mounted || _typeFilter != type) return;
    setState(() {
      _typedVideos = fromCache;
      _cachedVideoIds.addAll(fromCache.map((v) => v.videoId));
    });

    try {
      final service = YoutubeApiService(apiKey);
      final known = {for (final v in cached) v.videoId};
      final fresh = <YoutubeVideo>[];
      String? token;
      var offset = 0;
      var end = false;
      final maxPages = ofType.isEmpty ? 1 : 5;
      try {
        for (var i = 0; i < maxPages; i++) {
          final page = await service.fetchVideosPage(
            playlistId,
            pageToken: token,
            maxResults: _loadMoreBatch,
          );
          offset += page.videos.length;
          final newOnes = [
            for (final v in page.videos)
              if (!known.contains(v.videoId)) _tagAs(v, type),
          ];
          fresh.addAll(await _withDurations(service, newOnes));
          token = page.nextPageToken;
          end = token == null;
          if (end || newOnes.length < page.videos.length) break;
        }
      } on YoutubeApiException catch (e) {
        // 404：這個頻道真的沒有這個類型（例如從沒開過直播），不是錯誤。
        if (e.status != 404) rethrow;
        end = true;
      }
      if (fresh.isNotEmpty) await cache.upsertVideos(channelId, fresh);
      // 第一次看這個類型（快取一部都沒有）時，剛翻的這頁就是起點，記下
      // 位置給往下捲接著翻；整份清單都翻完了也記下來，之後不用再翻。
      if (ofType.isEmpty || end) {
        await cache.saveResumeIfDeeper(
          channelId,
          YtResume(token: token, offset: offset, end: end),
          kind: type.name,
        );
      }
      if (!mounted || _typeFilter != type) return;
      setState(() {
        _typedVideos =
            {
                for (final v in [...fresh, ..._typedVideos]) v.videoId: v,
              }.values.toList()
              ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        _typedReachedEnd = end && ofType.length <= fromCache.length;
        _typedLoading = false;
      });
    } catch (e) {
      if (!mounted || _typeFilter != type) return;
      setState(() {
        _typedLoading = false;
        _typedError = '$e';
      });
    }
  }

  /// 類型篩選往下捲載入更早的影片，跟「全部」的 [_loadMoreVideos] 同一套：
  /// 1. 先拿快取裡這個類型、比畫面上最舊那部更早的影片，不打 API。
  /// 2. 快取用完才從記下的位置（這個類型自己那份 [YtResume]）接著翻這個
  ///    類型的清單，快取已經有的跳過，最多連翻 5 頁找新的。
  Future<void> _loadTypedVideos() async {
    final type = _typeFilter;
    final apiKey = ref.read(ytApiKeyProvider);
    final playlistId = _typedPlaylistId();
    final channelId = _loadMoreChannelId;
    if (_typedLoading ||
        _typedError != null ||
        _typedReachedEnd ||
        playlistId == null ||
        channelId == null ||
        apiKey == null ||
        apiKey.isEmpty) {
      return;
    }
    setState(() => _typedLoading = true);
    try {
      final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
      final shownIds = {for (final v in _typedVideos) v.videoId};
      final oldestShown = _typedVideos.isEmpty
          ? null
          : _typedVideos
                .map((v) => v.publishedAt)
                .reduce((a, b) => a.isBefore(b) ? a : b);

      // 1. 本機快取
      final cached = await cache.load(channelId);
      final older = [
        for (final v in cached)
          if (_isOfType(v, type) &&
              !shownIds.contains(v.videoId) &&
              (oldestShown == null || v.publishedAt.isBefore(oldestShown)))
            v,
      ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      if (older.isNotEmpty) {
        final batch = older.take(_loadMoreBatch).toList();
        if (!mounted || _typeFilter != type) return;
        setState(() {
          _typedVideos = [..._typedVideos, ...batch];
          _cachedVideoIds.addAll(batch.map((v) => v.videoId));
          _typedLoading = false;
        });
        return;
      }

      // 2. 打 API，從這個類型記下的位置續抓
      final resume = await cache.loadResume(channelId, kind: type.name);
      if (resume != null && resume.end) {
        if (!mounted || _typeFilter != type) return;
        setState(() {
          _typedReachedEnd = true;
          _typedLoading = false;
        });
        return;
      }
      final service = YoutubeApiService(apiKey);
      var token = resume?.token;
      var offset = resume?.offset ?? 0;
      var end = false;
      final known = {...shownIds, for (final v in cached) v.videoId};
      final fresh = <YoutubeVideo>[];
      try {
        for (var i = 0; i < 5 && fresh.isEmpty && !end; i++) {
          final page = await service.fetchVideosPage(
            playlistId,
            pageToken: token,
            maxResults: _loadMoreBatch,
          );
          offset += page.videos.length;
          final newOnes = [
            for (final v in page.videos)
              if (!known.contains(v.videoId)) _tagAs(v, type),
          ];
          final withDurations = await _withDurations(service, newOnes);
          await cache.upsertVideos(channelId, withDurations);
          token = page.nextPageToken;
          end = token == null;
          await cache.saveResumeIfDeeper(
            channelId,
            YtResume(token: token, offset: offset, end: end),
            kind: type.name,
          );
          fresh.addAll(withDurations);
        }
      } on YoutubeApiException catch (e) {
        if (e.status != 404) rethrow;
        end = true;
      }
      if (!mounted || _typeFilter != type) return;
      setState(() {
        _typedVideos = [..._typedVideos, ...fresh];
        _typedReachedEnd = end && fresh.isEmpty;
        _typedLoading = false;
      });
    } catch (e) {
      if (!mounted || _typeFilter != type) return;
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
    final tagged = _applyTags(result, {
      for (final v in await cache.load(channel.id)) v.videoId: v,
    });
    // 用 setState：篩選開關上的數字（看過幾部、隱藏幾部）是從這份清單
    // 算的，第一頁進來時要跟著更新。
    if (mounted) setState(() => _firstPage = tagged);
    return tagged;
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

  /// 回傳的是 sliver（放在頁面的 CustomScrollView 裡），影片清單本身
  /// 才能捲到才建，見 [_videoRows]。
  Widget _buildVideos(YtChannel channel) {
    final apiKey = ref.watch(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
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
        ),
      );
    }
    if (_videosFuture == null) {
      return const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
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
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ThinRefreshBar(),
                    const SizedBox(height: Gap.sm),
                    RefreshingPill(
                      label: preview.isEmpty ? '正在向 YouTube 拿影片…' : '正在檢查新影片…',
                    ),
                    const SizedBox(height: Gap.xs),
                    if (preview.isEmpty) const SizedBox(height: 120),
                  ],
                ),
              ),
              if (preview.isNotEmpty)
                _videoRows(channel, preview, allFromCache: true),
            ],
          );
        }
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: InlineEmptyCard(
              title: '影片抓不下來',
              message: '${snap.error}',
              actions: [EmptyAction('重新整理', () => _refresh(channel))],
            ),
          );
        }
        // 用 [_firstPage] 不用 snap.data：背景掃完類型後換上的是
        // [_firstPage]（見 [_scanVideoTypes]），snap.data 還是當初抓回來、
        // 沒標類型的那份——之前就是讀錯這份，第一頁的「影片／Shorts／
        // 直播」標籤要離開再進來才出現（2026-10-06 使用者回報）。
        final firstPage = _firstPage.isNotEmpty
            ? _firstPage
            : (snap.data ?? const <YoutubeVideo>[]);
        if (firstPage.isEmpty) {
          return SliverToBoxAdapter(
            child: InlineEmptyCard(
              title: '這個頻道抓不到影片',
              message: '可能還沒發過公開影片',
              actions: [EmptyAction('重新整理', () => _refresh(channel))],
            ),
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
        final sorted = _sort != _Sort.newest;
        final views = YtVideoViews.notifier.value;
        int viewsOf(YoutubeVideo v) => v.viewCount ?? views[v.videoId] ?? -1;
        final visibleVideos = sorted
            ? ({
                for (final v in [
                  ..._cachedChannelVideos.where(
                    (v) => _isOfType(v, _typeFilter),
                  ),
                  ...videos,
                ])
                  v.videoId: v,
              }.values.where(_passesFilters).toList()..sort(
                (a, b) => _sort == _Sort.popular
                    ? viewsOf(b).compareTo(viewsOf(a))
                    : a.publishedAt.compareTo(b.publishedAt),
              ))
            : videos.where(_passesFilters).toList();
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
        if (!sorted &&
            visibleVideos.length < _loadMoreBatch &&
            !reachedEnd &&
            !loading &&
            error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) loadMore();
          });
        }
        // 整頁是一個 CustomScrollView（簡介／圖表／影片一起滑動，見 build()
        // 的說明），影片清單是其中一段 sliver，捲到才建。
        return SliverMainAxisGroup(
          slivers: [
            if (visibleVideos.isEmpty && !loading)
              SliverToBoxAdapter(
                child: _filteredEmptyCard(channel, videos, isTyped),
              ),
            _videoRows(channel, visibleVideos),
            // 往下滑到底會自動載入更早的影片；載入中轉圈、失敗給重試、
            // 沒有更多了就說一聲。
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: sorted
                    ? Center(
                        child: Text(
                          '依抓過的 ${visibleVideos.length} 部排序'
                          '${YtChannelFiller.of(channel.id).complete ? '' : '（整個頻道還在背景抓）'}',
                          style: AppText.note,
                        ),
                      )
                    : loading
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
      if (!_durationFilter.isAny && loaded.isNotEmpty)
        '時長「${_durationFilter.rangeLabel}」裡沒有影片',
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
        if (!_durationFilter.isAny)
          EmptyAction(
            '不限時長',
            () =>
                setState(() => _durationFilter = const YtDurationFilter.any()),
          ),
        EmptyAction('重新整理', () => _refresh(channel)),
      ],
    );
  }

  // ── 編輯頻道：頻道頁本身直接點著改（2026-10-12 使用者挑設計稿第 5 版，
  // 最終版見 design-history/已選擇完成/2026-10-12_YT編輯頻道最終版
  // （頁面上直接改）.html）。按 ✏️ 進編輯，頭部換成
  // [YtChannelEditHeader]，改不到的區塊淡掉，有改東西底部浮出儲存列，
  // 一次存。原本的編輯對話框拿掉了。──

  /// 編輯中的草稿；null＝沒在編輯。
  YtChannel? _draft;

  /// 進編輯時的樣子，拿來算改了幾項、按「還原」回到這裡。
  YtChannel? _editBase;

  /// 原本的名稱（2026-10-12 使用者要求：改過名也要知道原本叫啥）：頻道
  /// 紀錄裡最早那次改名的「改之前」；沒改過名就是進編輯時的名字。
  String _originalName = '';

  /// 每次進編輯換一個 key，頭部的輸入框從草稿重新開始。
  int _editSession = 0;

  bool get _editing => _draft != null;

  int get _changedCount {
    final d = _draft, b = _editBase;
    if (d == null || b == null) return 0;
    return [
      d.name != b.name,
      d.categoryId != b.categoryId,
      d.url != b.url,
      d.avatarImageUrl != b.avatarImageUrl,
      d.description != b.description,
    ].where((x) => x).length;
  }

  Future<void> _startEdit(YtChannel channel) async {
    // 在很下面按編輯時，捲回最上面才看得到要改的頭像、名稱（2026-10-14
    // 使用者要求）。
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
    final renames =
        (await YtChannelLogStore(
              ref.read(keyValueStoreProvider),
            ).forChannel(channel.id))
            .where(
              (e) =>
                  e.type == YtChannelEventType.renamed &&
                  (e.detail['from'] ?? '').isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    if (!mounted) return;
    setState(() {
      _originalName = renames.isEmpty
          ? channel.name
          : renames.first.detail['from']!;
      _draft = channel;
      _editBase = channel;
      _editSession++;
    });
  }

  Future<bool> _confirmDiscard() => showAppConfirmDialog(
    context,
    title: '有改過的東西還沒存',
    message: '要放棄這些修改嗎？',
    confirmLabel: '放棄',
    cancelLabel: '繼續改',
  );

  /// 「取消」跟編輯中按返回（2026-10-15 使用者要求：返回先取消編輯，
  /// 離開編輯以後再按才是回上一頁）：沒改東西直接離開編輯；有改就先問
  /// 要不要放棄。
  Future<void> _cancelEdit() async {
    if (_changedCount > 0 && !await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() => _draft = null);
  }

  /// 「完成」：有改就存，沒改就直接離開編輯（iOS 主流：左取消、右完成）。
  Future<void> _doneEdit() async {
    if (_changedCount > 0) return _saveEdit();
    setState(() => _draft = null);
  }

  Future<void> _saveEdit() async {
    final d = _draft;
    if (d == null) return;
    final name = d.name.trim();
    if (name.isEmpty) {
      showAppNotice(context, '名稱不能空白', isError: true);
      return;
    }
    // copyWith 保留已解析的頻道 ID／上傳清單 ID／訂閱人數；改名、換分類
    // 照舊由 repository 寫進頻道紀錄。
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(
          d.copyWith(
            name: name,
            url: d.url.trim(),
            avatarImageUrl: d.avatarImageUrl.trim(),
            description: d.description.trim(),
          ),
        );
    if (!mounted) return;
    setState(() => _draft = null);
    _reload();
    showAppNotice(context, '已儲存');
  }

  /// 點頭像：從下面滑出「換頭像」——從頻道網址重新抓、貼圖片網址、不用
  /// 圖片。換到草稿上，跟其他欄位一起在儲存列存。
  Future<void> _pickAvatar() async {
    final picked = await showModalBottomSheet<_AvatarChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _AvatarSheet(current: _draft!),
      ),
    );
    if (picked == null || !mounted || _draft == null) return;
    if (!picked.refetch) {
      setState(() => _draft = _draft!.copyWith(avatarImageUrl: picked.url));
      return;
    }
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) {
      showAppNotice(context, '要先設定 API 金鑰才能抓頭像', isError: true);
      return;
    }
    final handle = YoutubeApiService.parseHandle(_draft!.url);
    if (handle == null) {
      showAppNotice(context, '頻道網址裡找不到 @帳號，先改網址', isError: true);
      return;
    }
    try {
      final info = await YoutubeApiService(apiKey).fetchChannelInfo(handle);
      if (!mounted || _draft == null) return;
      setState(() => _draft = _draft!.copyWith(avatarImageUrl: info.avatarUrl));
      showAppNotice(context, '已抓到頭像，記得按儲存');
    } catch (e) {
      if (!mounted) return;
      showAppNotice(context, '頭像抓不到', detail: '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 編輯中按返回：先取消編輯（有改過先問），不離開頁面。
    return PopScope(
      canPop: !_editing && !_searchOpen,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 搜尋中按返回：先收起搜尋，不離開頁面。
        if (_searchOpen) return _closeSearch();
        if (_editing) return _cancelEdit();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
                      final prefs = ref.watch(ytDisplayPrefsProvider);
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
                        _scanVideoTypes();
                        _checkRemovedVideos(channel);
                        _refreshViewCounts(channel);
                      });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 搜尋框一直放著、沒開時看不見：點 🔍 的當下就能
                          // 要到焦點，iPhone 才會跳鍵盤。
                          Stack(
                            children: [
                              Visibility(
                                visible: !_searchOpen,
                                maintainState: true,
                                maintainAnimation: true,
                                maintainSize: true,
                                child: _topBar(channel),
                              ),
                              Positioned.fill(
                                child: Visibility(
                                  visible: _searchOpen,
                                  maintainState: true,
                                  maintainAnimation: true,
                                  maintainSize: true,
                                  maintainFocusability: true,
                                  child: Center(
                                    child: _SearchBar(
                                      controller: _searchCtrl,
                                      focusNode: _searchFocus,
                                      onBack: _closeSearch,
                                      onClear: _clearSearch,
                                      onChanged: (q) =>
                                          _onSearchTyped(channel, q),
                                      onSubmit: (q) =>
                                          _submitSearch(channel, q),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.md),
                          // 編輯中最上面原本有一行「點有虛線的地方直接改」，
                          // 2026-10-15 使用者要求拿掉（虛線本身就看得懂）。
                          // 從垃圾桶點進來的頻道：最上面提示一下，旁邊就能還原。
                          if (channel.deletedAt != null &&
                              channel.purgedAt == null) ...[
                            _TrashBanner(
                              onRestore: () async {
                                await ref
                                    .read(ytTrackerRepositoryProvider)
                                    .restoreChannel(channel.id);
                                if (!context.mounted) return;
                                _reload();
                                showAppNotice(context, '已還原「${channel.name}」');
                              },
                            ),
                            const SizedBox(height: Gap.sm),
                          ],
                          // 簡介／上傳頻率圖／最近影片全部包進同一個可捲動
                          // 區域，不要只有最近影片自己捲、上面的內容固定
                          // 不動——不然滑最近影片清單時，簡介跟圖表卻停在
                          // 原地不會一起往上滑，體驗很奇怪（2026-09-23
                          // 使用者回報）。只有頂部列固定在外面。
                          //
                          // 右側一直顯示捲動條、可以拖（2026-10-12 使用者
                          // 要求）；滑下去一段右下角出「回到最上面」。
                          Expanded(
                            child: Stack(
                              children: [
                                // 捲動條自己畫，關掉 App 預設的（網頁桌機版
                                // 預設會有一條），設定關掉就完全不顯示。
                                ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(
                                    context,
                                  ).copyWith(scrollbars: false),
                                  child: _withScrollbar(
                                    prefs.showScrollbar,
                                    CustomScrollView(
                                      controller: _scroll,
                                      slivers: [
                                        ...(_searchOpen
                                            ? _buildSearch(channel)
                                            : [
                                                SliverToBoxAdapter(
                                                  child: _buildChannelBody(
                                                    channel,
                                                    categories,
                                                    categoryLabel,
                                                  ),
                                                ),
                                                // 分頁列往上滑會黏在最上面。
                                                SliverPersistentHeader(
                                                  pinned: true,
                                                  delegate: _TabBarDelegate(
                                                    selected: _tab,
                                                    onTap: _selectTab,
                                                    dim: _editing,
                                                  ),
                                                ),
                                                if (_editing)
                                                  SliverIgnorePointer(
                                                    sliver: SliverOpacity(
                                                      opacity: 0.3,
                                                      sliver: _buildTabBody(
                                                        channel,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  _buildTabBody(channel),
                                              ]),
                                        // 底部浮動分頁列擋住的高度（2026-10-14）。
                                        SliverToBoxAdapter(
                                          child: SizedBox(
                                            height: FloatingNavInset.of(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // 編輯中先藏起來，不跟儲存列擠。
                                if (prefs.showBackToTop && !_editing)
                                  Positioned.fill(
                                    child: _BackToTopLayer(
                                      visible: _showBackToTop,
                                      onTap: () => _scroll.animateTo(
                                        0,
                                        duration: const Duration(
                                          milliseconds: 400,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                  ),
                                if (_editing && _changedCount > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 12,
                                    child: _EditSaveBar(
                                      count: _changedCount,
                                      onRevert: () =>
                                          setState(() => _draft = _editBase),
                                      onSave: _saveEdit,
                                    ),
                                  ),
                              ],
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

  /// 搜尋頁的內容：還沒搜是最近搜尋；搜了是狀態列＋結果。
  List<Widget> _buildSearch(YtChannel channel) {
    final search = _search;
    if (search == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
            child: Text(
              _recents.isEmpty ? '輸入關鍵字，按 Enter 搜尋這個頻道的影片標題' : '最近搜尋',
              style: AppText.note,
            ),
          ),
        ),
        SliverList.list(
          children: [
            for (final r in _recents)
              InkWell(
                onTap: () => _submitSearch(channel, r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppColors.ink3,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: Text(r, style: AppText.bodyDim)),
                      IconButton(
                        onPressed: () async {
                          final next = await YtSearchRecentsStore(
                            ref.read(keyValueStoreProvider),
                          ).remove(r);
                          if (mounted) setState(() => _recents = next);
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: AppColors.ink3,
                        tooltip: '刪掉這筆',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ];
    }
    final prefs = ref.watch(ytDisplayPrefsProvider);
    final results = prefs.searchShowAll
        ? search.matches
        : search.matches.where(_passesBaseFilters).toList();
    final filteredOut = search.matches.length - results.length;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: _SearchStatus(
            search: search,
            shown: results.length,
            filteredOut: filteredOut,
            onRetry: search.run,
          ),
        ),
      ),
      if (results.isEmpty && search.done)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                YtChannelFiller.of(channel.id).complete
                    ? '「${search.query}」整個頻道都找不到'
                    : '抓過的影片裡找不到「${search.query}」',
                style: AppText.note,
              ),
            ),
          ),
        ),
      _videoRows(
        channel,
        results,
        highlight: search.query,
        justFetched: search.fetchedIds,
        forceShowHidden: prefs.searchShowAll,
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ];
  }

  Widget _buildChannelBody(
    YtChannel channel,
    List<YtCategory> categories,
    String categoryLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editing)
          YtChannelEditHeader(
            key: ValueKey(_editSession),
            draft: _draft!,
            base: _editBase!,
            categories: categories,
            originalName: _originalName,
            onChanged: (d) => setState(() => _draft = d),
            onTapAvatar: _pickAvatar,
          )
        else ...[
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
                    // 影片數（2026-10-14 使用者要求）：整個頻道都抓進快取了
                    // 才寫「共 N 部」；還在背景抓就寫抓到幾部。之後進來有新片
                    // 數字跟著變，沒有就維持。
                    ListenableBuilder(
                      listenable: YtChannelFiller.of(channel.id),
                      builder: (context, _) {
                        final f = YtChannelFiller.of(channel.id);
                        final text = f.complete
                            ? '共 ${_fmtCount(f.cached)} 部影片'
                            : f.running
                            ? '正在抓全部影片…已有 ${_fmtCount(f.cached)} 部'
                            : null;
                        if (text == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            text,
                            style: AppText.note.copyWith(
                              color: f.complete
                                  ? AppColors.ink2
                                  : AppColors.accent,
                            ),
                          ),
                        );
                      },
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
        ],
        const SizedBox(height: Gap.sm),
      ],
    );
  }

  bool get _isVideoTab =>
      _tab == _ChannelTab.all ||
      _tab == _ChannelTab.shorts ||
      _tab == _ChannelTab.live;

  void _selectTab(_ChannelTab tab) {
    if (tab == _tab && _typeFilter != _TypeFilter.removed) return;
    setState(() => _tab = tab);
    switch (tab) {
      case _ChannelTab.all:
        _switchTypeFilter(_TypeFilter.all);
      case _ChannelTab.shorts:
        _switchTypeFilter(_TypeFilter.shorts);
      case _ChannelTab.live:
        _switchTypeFilter(_TypeFilter.live);
      case _ChannelTab.watch:
        // 剛看過的也要出現。
        _loadVideoFilters();
      case _ChannelTab.about:
        _reloadCache();
    }
  }

  /// 熱門／最舊要看整個頻道，不是只看往下捲載入的那幾頁：先重讀一次
  /// 快取（背景一直在抓全部影片）。
  Future<void> _setSort(_Sort sort) async {
    setState(() => _sort = sort);
    if (sort == _Sort.newest) return;
    await _reloadCache();
  }

  Future<void> _reloadCache() async {
    final id = _loadMoreChannelId;
    if (id == null) return;
    final cached = await YtVideoCacheStore(
      ref.read(keyValueStoreProvider),
    ).load(id);
    if (mounted && _loadMoreChannelId == id) {
      setState(() => _cachedChannelVideos = cached);
    }
  }

  /// 分頁內容。
  Widget _buildTabBody(YtChannel channel) => switch (_tab) {
    _ChannelTab.about => SliverToBoxAdapter(child: _buildAbout(channel)),
    _ChannelTab.watch => _buildWatchTab(channel),
    _ => SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _buildVideoFilterRow(channel)),
        _buildVideos(channel),
      ],
    ),
  };

  /// 「簡介」分頁（2026-10-15）：原本頭部的簡介、上傳頻率圖搬過來，再加
  /// 使用者要的「豐富一點」——全部從本機影片快取算（見 [YtChannelStats]），
  /// 不多打 API。訂閱、影片數、追蹤日期放最上面（使用者要求）。
  Widget _buildAbout(YtChannel channel) {
    String two(int n) => n.toString().padLeft(2, '0');
    String ymd(DateTime d) => '${d.year}/${two(d.month)}/${two(d.day)}';
    final views = YtVideoViews.notifier.value;
    final stats = YtChannelStats.from(
      _cachedChannelVideos,
      viewsOf: (v) => v.viewCount ?? views[v.videoId],
      lastWatchedOf: (id) => _watchedRecords[id]?.lastOpenedAt,
    );
    final filler = YtChannelFiller.of(channel.id);
    Widget card(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelLabel(label),
            const SizedBox(height: Gap.xs),
            child,
          ],
        ),
      ),
    );
    final wd = stats.busiestWeekday, slot = stats.busiestSlot;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 最上面三格：訂閱、YouTube 上幾部、追蹤多久。
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              children: [
                _AboutStat(
                  value: switch (channel.subscriberLabel) {
                    null => '—',
                    '訂閱數未公開' => '未公開',
                    final l =>
                      l.replaceAll('約 ', '').replaceAll('位訂閱', '').trim(),
                  },
                  label: '訂閱',
                ),
                const SizedBox(width: Gap.sm),
                _AboutStat(
                  value: channel.videoCount == null
                      ? '—'
                      : _fmtCount(channel.videoCount!),
                  label: 'YouTube 上的影片',
                ),
                const SizedBox(width: Gap.sm),
                _AboutStat(value: ymd(channel.addedAt), label: '開始追蹤'),
              ],
            ),
          ),
          card(
            '簡介',
            Text(
              channel.description.isEmpty
                  ? '沒有簡介（右上角編輯可以補）'
                  : channel.description,
              style: AppText.bodyDim,
            ),
          ),
          card('上傳頻率（近半年）', _buildHistoryChart(channel)),
          // 平均每月、最早一部、最熱門這些要看整個頻道，抓完全部影片才顯示，
          // 還在抓就轉圈（2026-10-15 使用者要求：只抓到一部分算出來的不準）。
          ListenableBuilder(
            listenable: filler,
            builder: (context, _) {
              if (!filler.complete) {
                return card('這個頻道', _fillPending(channel, filler));
              }
              // 剛抓完：重讀一次快取，數字才是整個頻道的。
              if (_aboutFullFor != channel.id) {
                _aboutFullFor = channel.id;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _reloadCache();
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stats.total > 0) ...[
                    card(
                      '這個頻道',
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.sm,
                        children: [
                          _AboutFact(
                            '影片類型',
                            '一般 ${stats.regular}・Shorts ${stats.shorts}・直播 ${stats.live}',
                          ),
                          if (stats.avgDuration != null)
                            _AboutFact(
                              '平均長度',
                              formatVideoDuration(stats.avgDuration!),
                            ),
                          if (stats.perMonth != null)
                            _AboutFact(
                              '平均每月',
                              '${stats.perMonth!.toStringAsFixed(stats.perMonth! < 10 ? 1 : 0)} 部',
                            ),
                          if (stats.latest != null)
                            _AboutFact('最近上傳', ytRelativeTime(stats.latest!)),
                          if (stats.first != null)
                            _AboutFact('最早一部', ymd(stats.first!)),
                          if (stats.totalViews != null)
                            _AboutFact(
                              '觀看次數合計',
                              formatViewCount(stats.totalViews!),
                            ),
                        ],
                      ),
                    ),
                    card(
                      '什麼時候發片',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wd != null)
                            Text(
                              '最常在星期${YtChannelStats.weekdayLabels[wd]}'
                              '${slot == null ? '' : '・${YtChannelStats.slotLabels[slot]}'}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          const SizedBox(height: Gap.sm),
                          _AboutBars(
                            labels: YtChannelStats.weekdayLabels,
                            counts: stats.weekdays,
                          ),
                          const SizedBox(height: Gap.sm),
                          _AboutBars(
                            labels: YtChannelStats.slotLabels,
                            counts: stats.slots,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (stats.top.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: PanelLabel('最熱門'),
                            ),
                            for (final v in stats.top) _videoRow(channel, v),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          card(
            '你看過',
            Text(
              stats.watched == 0
                  ? '還沒看過這個頻道的影片'
                  : [
                      '看過 ${stats.watched} 部'
                          '${stats.total == 0 || !filler.complete ? '' : '（${(stats.watched * 100 / stats.total).round()}%）'}',
                      if (stats.lastWatched != null)
                        '最近一次 ${ytRelativeTime(stats.lastWatched!)}',
                    ].join('・'),
              style: AppText.bodyDim,
            ),
          ),
        ],
      ),
    );
  }

  /// 簡介分頁要等整個頻道抓完的那幾塊（[_buildAbout]）：哪個頻道已經
  /// 重讀過抓完後的快取。
  String? _aboutFullFor;

  /// 還沒抓完整個頻道時，簡介分頁那塊顯示的東西。
  Widget _fillPending(YtChannel channel, YtChannelFiller filler) {
    if (filler.running) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              '正在抓整個頻道的影片…已有 ${_fmtCount(filler.cached)} 部\n'
              '抓完才算得出平均每月、最早一部、最熱門',
              style: AppText.note,
            ),
          ),
        ],
      );
    }
    final apiKey = ref.read(ytApiKeyProvider);
    final canFetch = apiKey != null && apiKey.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Text(
            canFetch
                ? '要先抓完整個頻道的影片才算得出平均每月、最早一部、最熱門'
                : '要先設定 API 金鑰、抓完整個頻道的影片才算得出來',
            style: AppText.note,
          ),
        ),
        if (canFetch)
          TextButton(
            onPressed: () => filler.start(
              cache: YtVideoCacheStore(ref.read(keyValueStoreProvider)),
              api: YoutubeApiService(apiKey),
              uploadsId: () async =>
                  _uploadsId ??
                  (channel.uploadsPlaylistId.isEmpty
                      ? null
                      : channel.uploadsPlaylistId),
            ),
            child: const Text('現在抓'),
          ),
      ],
    );
  }

  /// 「觀看紀錄」分頁：這個頻道看過的影片，照看的時間、每天一組，跟
  /// 頻道紀錄頁的觀看紀錄長得一樣（2026-10-15 使用者要求加這個分頁）。
  Widget _buildWatchTab(YtChannel channel) {
    final watched = [
      for (final v in _cachedChannelVideos)
        if (_watchedRecords[v.videoId] case final r?)
          (video: v, openedAt: r.openedAt),
    ];
    final items = buildYtChannelLog(
      channel: channel,
      events: const [],
      watched: watched,
    ).where((i) => i.isWatch).toList()..sort((a, b) => b.at.compareTo(a.at));
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: Gap.md),
          child: InlineEmptyCard(title: '還沒看過這個頻道的影片', message: '點影片看過之後會記在這裡'),
        ),
      );
    }
    final rows = ytLogTimelineRows(items);
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  /// 影片分頁上面那兩排（2026-10-15 改成設計稿第 1 版的位置）：
  /// - 第一排：最新／熱門／最舊，右邊時長篩選（圖示跟跳出來的選單照舊，
  ///   使用者要求）＋重新整理。
  /// - 第二排：「隱藏已看過」「顯示已隱藏」兩個開關（旁邊數字＝有幾部），
  ///   有查到下架的影片才多一顆「已下架」。
  Widget _buildVideoFilterRow(YtChannel channel) {
    bool ofType(YoutubeVideo v) => _isOfType(v, _typeFilter);
    final removedCount = _cachedChannelVideos
        .where((v) => v.removedAt != null)
        .length;
    final loaded = {
      for (final v in [
        ..._cachedChannelVideos.where(ofType),
        if (_typeFilter == _TypeFilter.all) ...[
          ..._firstPage,
          ..._moreVideos,
        ] else
          ..._typedVideos,
      ])
        v.videoId: v,
    }.values.toList();
    final hiddenCount = loaded
        .where((v) => _hiddenVideoIds.contains(v.videoId))
        .length;
    final watchedCount = loaded
        .where((v) => _watchedVideoIds.contains(v.videoId))
        .length;
    String withCount(String label, int n) => n > 0 ? '$label ($n)' : label;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final s in _Sort.values) ...[
                _Pick(
                  label: s.label,
                  color: AppColors.accentSolid,
                  selected: _sort == s,
                  onTap: () => _setSort(s),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              YtDurationChip(
                filter: _durationFilter,
                countOf: (f) => loaded
                    .where((v) => _passesBaseFilters(v) && f.matches(v))
                    .length,
                onChanged: (f) => setState(() => _durationFilter = f),
              ),
              IconButton(
                onPressed: () => _refresh(channel),
                icon: const Icon(Icons.refresh, size: 18),
                color: AppColors.ink2,
                tooltip: '重新整理',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              // 「已下架」：有查到下架的影片才出現（2026-10-12 使用者要求），
              // 再點一次回到這個分頁的類型。
              if (removedCount > 0 || _typeFilter == _TypeFilter.removed)
                _Pick(
                  label: '已下架 ($removedCount)',
                  color: AppColors.ink3,
                  selected: _typeFilter == _TypeFilter.removed,
                  onTap: () => _typeFilter == _TypeFilter.removed
                      ? _selectTab(_tab)
                      : _switchTypeFilter(_TypeFilter.removed),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 垃圾桶裡的頻道詳情頁最上面那條提示＋還原鈕（2026-10-06）。
class _TrashBanner extends StatelessWidget {
  const _TrashBanner({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.bad.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bad.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.delete_outline_rounded,
            size: 16,
            color: AppColors.bad,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '這個頻道在垃圾桶裡',
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
          ),
          TextButton(onPressed: onRestore, child: const Text('還原')),
        ],
      ),
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

/// 「回到最上面」可以拖到想要的位置（2026-10-12 使用者要求：起始位置
/// 靠上一點、最好可以拖）。拖的時候跟著手指走，放開存進
/// [YtDisplayPrefs]（跨裝置同步）；只在頁面範圍內，不會拖出畫面。
/// 只有按鈕本身接手勢，其他地方照樣點得到底下的影片。
class _BackToTopLayer extends ConsumerStatefulWidget {
  const _BackToTopLayer({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  ConsumerState<_BackToTopLayer> createState() => _BackToTopLayerState();
}

class _BackToTopLayerState extends ConsumerState<_BackToTopLayer>
    with SingleTickerProviderStateMixin {
  static const _size = 44.0;

  /// 吸到邊之後離邊多遠。
  static const _margin = 10.0;

  /// 位置一律用「離右邊、離下面多遠」表示（跟設定存的一樣）。
  /// 拖動中跟著手指的位置；null＝沒在拖。
  Offset? _dragging;

  /// 放開後滑去吸邊的動畫（像 iPhone 輔助觸控小圓點，2026-10-12 使用者
  /// 要求：要絲滑；2026-10-15 改成只吸左右、上下停在放開的地方）。
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Offset _snapFrom = Offset.zero, _snapTo = Offset.zero;

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  Future<void> _save(double right, double bottom) async {
    final next = ref
        .read(ytDisplayPrefsProvider)
        .copyWith(backToTopRight: right, backToTopBottom: bottom);
    ref.read(ytDisplayPrefsProvider.notifier).state = next;
    final saved = await YtDisplayPrefsStore(
      ref.read(keyValueStoreProvider),
    ).save(next);
    if (mounted) ref.read(ytDisplayPrefsProvider.notifier).state = saved;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(ytDisplayPrefsProvider);
    return LayoutBuilder(
      builder: (context, c) {
        final maxRight = (c.maxWidth - _size).clamp(0.0, double.infinity);
        final maxBottom = (c.maxHeight - _size).clamp(0.0, double.infinity);
        // 離底部至少一段距離：浮動分頁列上面再留 24（2026-10-15 使用者
        // 要求：吸在下面時太靠近底部）。
        final minBottom = (FloatingNavInset.of(context) + 24).clamp(
          _margin,
          maxBottom,
        );
        Offset clampPos(Offset o) =>
            Offset(o.dx.clamp(0.0, maxRight), o.dy.clamp(minBottom, maxBottom));
        return AnimatedBuilder(
          animation: _snap,
          builder: (context, _) {
            final Offset pos;
            if (_dragging != null) {
              pos = _dragging!;
            } else if (_snap.isAnimating) {
              pos = Offset.lerp(
                _snapFrom,
                _snapTo,
                Curves.easeOutBack.transform(_snap.value),
              )!;
            } else {
              pos = clampPos(
                Offset(prefs.backToTopRight, prefs.backToTopBottom),
              );
            }
            return Stack(
              children: [
                Positioned(
                  right: pos.dx,
                  bottom: pos.dy,
                  child: GestureDetector(
                    onPanStart: widget.visible
                        ? (_) {
                            _snap.stop();
                            setState(() => _dragging = pos);
                          }
                        : null,
                    onPanUpdate: widget.visible
                        ? (d) => setState(
                            () => _dragging = clampPos(
                              Offset(
                                _dragging!.dx - d.delta.dx,
                                _dragging!.dy - d.delta.dy,
                              ),
                            ),
                          )
                        : null,
                    onPanEnd: widget.visible
                        ? (_) {
                            final from = _dragging!;
                            final to = snapToNearestEdge(
                              from,
                              maxRight: maxRight,
                              maxBottom: maxBottom,
                              margin: _margin,
                              minBottom: minBottom,
                            );
                            setState(() {
                              _dragging = null;
                              _snapFrom = from;
                              _snapTo = to;
                            });
                            _snap.forward(from: 0);
                            _save(to.dx, to.dy);
                          }
                        : null,
                    // 拖的時候放大一點，手指知道抓到了。
                    child: AnimatedScale(
                      scale: _dragging != null ? 1.12 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: _BackToTopButton(
                        visible: widget.visible,
                        onTap: widget.onTap,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 頻道詳情頁右下角的「回到最上面」（2026-10-12 使用者要求：影片滑下去
/// 以後一般 App 都有的那顆）。沒出現時縮小淡出、也點不到。
class _BackToTopButton extends StatelessWidget {
  const _BackToTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.6,
        duration: const Duration(milliseconds: 180),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Tooltip(
            message: '回到最上面',
            // 再透一點淡一點（2026-10-15 使用者要求），像 iOS 小圓點。
            child: Material(
              color: AppColors.ytAccent.withValues(alpha: 0.38),
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
              elevation: 2,
              shadowColor: Colors.black38,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 28,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 編輯中有改東西時浮在底部的「已改 N 項・還原・儲存」。
class _EditSaveBar extends StatelessWidget {
  const _EditSaveBar({
    required this.count,
    required this.onRevert,
    required this.onSave,
  });

  final int count;
  final VoidCallback onRevert;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF51E1E2E),
      elevation: 8,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: Row(
          children: [
            Text(
              '已改 $count 項',
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const Spacer(),
            TextButton(onPressed: onRevert, child: const Text('還原')),
            const SizedBox(width: 4),
            FilledButton(onPressed: onSave, child: const Text('儲存')),
          ],
        ),
      ),
    );
  }
}

/// 換頭像選了什麼：[refetch] 是「從頻道網址重新抓」（要打 API，交給頁面
/// 做）；不然就是直接用 [url]（空字串＝不用圖片）。
class _AvatarChoice {
  const _AvatarChoice.refetch() : refetch = true, url = '';
  const _AvatarChoice.url(this.url) : refetch = false;

  final bool refetch;
  final String url;
}

/// 點頭像滑出來的「換頭像」表單（編輯頻道最終版設計稿）。
class _AvatarSheet extends StatefulWidget {
  const _AvatarSheet({required this.current});

  final YtChannel current;

  @override
  State<_AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends State<_AvatarSheet> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String note,
    required VoidCallback onTap,
    bool selected = false,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: AppColors.ink2),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(note, style: AppText.note),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_rounded, size: 20, color: AppColors.accent),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final noImage = widget.current.avatarImageUrl.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          Row(
            children: [
              YtChannelAvatar(channel: widget.current, radius: 22),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '換頭像',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    Text('換好後跟其他修改一起按儲存', style: AppText.note),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          _option(
            icon: Icons.refresh_rounded,
            title: '從頻道網址重新抓',
            note: '跟新增頻道一樣，自動抓 YouTube 上的頭像',
            onTap: () => Navigator.pop(context, const _AvatarChoice.refetch()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: AppColors.ink2,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: TextField(
                    controller: _url,
                    style: const TextStyle(fontSize: 13, color: AppColors.ink),
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      Navigator.pop(context, _AvatarChoice.url(v.trim()));
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '貼圖片網址',
                      hintText: 'https://…jpg',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '貼上',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.content_paste_go_rounded,
                              size: 18,
                            ),
                            onPressed: () async {
                              String? text;
                              try {
                                text = (await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                ))?.text?.trim();
                              } catch (_) {
                                // 權限被擋：當沒讀到。
                              }
                              if (text == null || text.isEmpty) return;
                              _url.text = text;
                            },
                          ),
                          TextButton(
                            onPressed: () {
                              final v = _url.text.trim();
                              if (v.isEmpty) return;
                              Navigator.pop(context, _AvatarChoice.url(v));
                            },
                            child: const Text('用這張'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _option(
            icon: Icons.hide_image_outlined,
            title: '不用圖片',
            note: '顯示預設的頻道圖示',
            selected: noImage,
            onTap: () => Navigator.pop(context, const _AvatarChoice.url('')),
          ),
        ],
      ),
    );
  }
}

/// 搜尋時取代頂部列的搜尋框（設計稿第 1 版）：左邊 ← 收起，鍵盤直接跳出，
/// 打字就搜。
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onBack,
    required this.onClear,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.ink2,
          tooltip: '收起搜尋',
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmit,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜尋這個頻道的影片',
                hintStyle: const TextStyle(color: AppColors.ink3),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: AppColors.ink3,
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded, size: 17),
                        color: AppColors.ink3,
                        tooltip: '清掉',
                      ),
                filled: true,
                fillColor: AppColors.glassFill,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.glassEdge),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.glassEdge),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.xs),
      ],
    );
  }
}

/// 搜尋狀態：快取找到幾部、YouTube 抓到哪了、是不是整個頻道都找過了。
class _SearchStatus extends StatelessWidget {
  const _SearchStatus({
    required this.search,
    required this.shown,
    required this.filteredOut,
    required this.onRetry,
  });

  final YtChannelSearch search;
  final int shown;
  final int filteredOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = search;
    final found = TextSpan(
      text: '$shown',
      style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
    );
    final hiddenNote = filteredOut > 0
        ? '（另有 $filteredOut 部被「隱藏已看過／顯示已隱藏」篩掉）'
        : '';
    final List<InlineSpan> text;
    double? progress;
    var showBar = false;
    if (s.error != null) {
      text = [
        TextSpan(text: '抓到一半失敗：${s.error}・目前找到 '),
        found,
        const TextSpan(text: ' 部'),
      ];
    } else if (!s.usesApi) {
      text = [
        TextSpan(text: '搜抓過的 ${s.cachedCount} 部・找到 '),
        found,
        TextSpan(text: ' 部$hiddenNote'),
      ];
    } else if (!s.done) {
      final total = s.totalOnYoutube;
      showBar = true;
      if (total != null && total > 0) {
        progress = (s.scanned / total).clamp(0.0, 1.0);
      }
      text = [
        TextSpan(
          text: s.scanned == s.cachedCount
              ? '快取找完，這個頻道其他影片還在背景抓…'
              : '這個頻道其他影片還在背景抓… ${s.scanned}'
                    '${total == null ? '' : '／$total'} 部',
        ),
        const TextSpan(text: '・目前找到 '),
        found,
        TextSpan(text: ' 部$hiddenNote'),
      ];
    } else {
      text = [
        TextSpan(
          text: '✓ 整個頻道 ${s.scanned} 部都找過了',
          style: const TextStyle(color: AppColors.ok),
        ),
        const TextSpan(text: '・找到 '),
        found,
        TextSpan(text: ' 部$hiddenNote'),
      ];
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: text),
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),
          ),
          if (showBar) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: AppColors.accent,
                backgroundColor: const Color(0xFF23233A),
              ),
            ),
          ],
          if (s.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onRetry, child: const Text('重試')),
            ),
        ],
      ),
    );
  }
}

/// 1,240 這種千分位。
String _fmtCount(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// 頻道詳情頁黏在上面的分頁列（設計稿第 1 版：粗字、選中的下面一條線）。
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({
    required this.selected,
    required this.onTap,
    required this.dim,
  });

  final _ChannelTab selected;
  final ValueChanged<_ChannelTab> onTap;
  final bool dim;

  static const _height = 44.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return IgnorePointer(
      ignoring: dim,
      child: Opacity(
        opacity: dim ? 0.3 : 1,
        child: Container(
          color: AppColors.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final t in _ChannelTab.values)
                        InkWell(
                          onTap: () => onTap(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  width: 2,
                                  color: t == selected
                                      ? AppColors.ink
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Text(
                              t.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t == selected
                                    ? AppColors.ink
                                    : AppColors.ink2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.glassEdge),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.selected != selected || old.dim != dim;
}

/// 簡介分頁最上面的一格數字。
class _AboutStat extends StatelessWidget {
  const _AboutStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.note),
        ],
      ),
    ),
  );
}

/// 「這個頻道」卡片裡的一小格：上面灰色標題、下面數字。
class _AboutFact extends StatelessWidget {
  const _AboutFact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 96),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppText.note),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

/// 一排小長條：每個標籤一條，最多的那條最高、顏色最亮。
class _AboutBars extends StatelessWidget {
  const _AboutBars({required this.labels, required this.counts});

  final List<String> labels;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final most = counts.fold(0, (m, c) => c > m ? c : m);
    return SizedBox(
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${counts[i]}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.ink3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: most == 0 ? 2 : 2 + 26 * counts[i] / most,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(
                          alpha: counts[i] == most && most > 0 ? 0.95 : 0.4,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(labels[i], style: AppText.note),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
