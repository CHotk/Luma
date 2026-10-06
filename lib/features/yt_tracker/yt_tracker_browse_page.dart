import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_subscriber_history_store.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_subscriber_snapshot.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/background_refresh.dart';
import '../../shared/widgets/bubble_menu.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'yt_api_key_dialog.dart';
import 'yt_channel_avatar.dart';
import 'yt_tracker_home_page.dart'
    show YtCategoryImage, deleteYtCategory, runYtChannelDiscovery;
import 'yt_video_row.dart';

enum _ViewMode { channel, video }

/// 「依影片顯示」的類型篩選——API 本身沒有標「這是 Shorts」的欄位，
/// 靠 [YoutubeVideo.isLikelyShort] 的時長啟發式判斷來分（2026-09-23
/// 使用者問「api給的資料有區分嗎」，這是能做到的最接近做法）。
enum _TypeFilter { all, regular, shorts, live }

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
  const YtTrackerBrowsePage({
    super.key,
    required this.initialCategoryIds,
    this.trash = false,
  });

  final Set<String> initialCategoryIds;

  /// 垃圾桶模式（2026-10-06 使用者要求：垃圾桶點進分類後要跟一般分類頁
  /// 完全一樣，能照樣逛、點進頻道看影片、照樣打 API，只是多了「還原」
  /// 跟「永久刪除」）。原本垃圾桶自己刻了一份陽春清單
  /// （`yt_trash_browse_page.dart`，已拿掉），現在直接共用這一頁：
  /// - 資料換成被刪除的頻道（[YtTrackerRepository.loadDeletedChannels]）。
  /// - 長按／⋮ 選單的「刪除」換成「還原」＋「永久刪除」。
  /// - 標題前面加「垃圾桶・」；不給新增頻道、挖掘、刪除分類這些按鈕。
  final bool trash;

  @override
  ConsumerState<YtTrackerBrowsePage> createState() =>
      _YtTrackerBrowsePageState();
}

class _YtTrackerBrowsePageState extends ConsumerState<YtTrackerBrowsePage> {
  late Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _future;
  late final Set<String> _selected = {...widget.initialCategoryIds};
  // 每個分類（含「全部」）點進去都預設「依頻道顯示」（2026-09-24 使用者
  // 要求；之前分類預設依影片，但一進去就要抓影片，太慢）。切換鈕是
  // 頻道在左、影片在右（2026-10-06 使用者要求對調成這個順序）。
  _ViewMode _mode = _ViewMode.channel;
  _TypeFilter _typeFilter = _TypeFilter.all;
  // 預設依訂閱人數排序，不是加入順序（2026-09-29 使用者要求：每個分類
  // 預設頻道排序要照訂閱人數）。使用者還是能用排序鈕切回原本順序或
  // 升冪，這裡只是改預設值。
  _ChannelSort _sort = _ChannelSort.subsDesc;

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

  Future<({List<YtCategory> categories, List<YtChannel> channels})>
  _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final categories = await repo.loadCategories();
    final channels = widget.trash
        ? await repo.loadDeletedChannels()
        : await repo.loadChannels();
    return (categories: categories, channels: channels);
  }

  void _reload() => setState(() {
    _future = _load();
  });

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
    // 篩選沒變、只是放太久要自動更新：背景抓，抓完整份直接換上去，
    // 不清空、不跳回載入中畫面——原本會整個清單換成「載入中」再換回來，
    // 捲動位置歸零跳回最上面（2026-10-06 使用者回報隱藏影片時「整個畫面
    // 重新加載、跳到最上面」：隱藏觸發重繪，剛好碰到超過 5 分鐘）。
    // 抓失敗就留著舊的，不打擾。
    if (!force && sameSelection) {
      _fetchVideos(channels, apiKey).then((fresh) {
        if (!mounted || !_listEquals(_videosLoadedFor ?? const [], ids)) {
          return;
        }
        setState(() => _videosFuture = SynchronousFuture(fresh));
      }, onError: (_) {});
      return;
    }
    setState(() {
      _videosFuture = _fetchVideos(channels, apiKey);
      _videoPreview = const [];
    });
    _loadVideoPreview(channels, ids);
  }

  /// 「依影片顯示」還在向 YouTube 拿的時候先秀的本機快取（2026-10-02
  /// 使用者選了「先顯示舊的、背景更新」）：每個頻道從快取拿最新
  /// [_videosPerChannel] 部，跟真的抓回來的一樣依上傳時間排。快取裡
  /// 分不準類型，選了特定類型就不秀預覽、只秀進度條跟膠囊。
  List<_ChannelVideo> _videoPreview = const [];

  Future<void> _loadVideoPreview(
    List<YtChannel> channels,
    List<String> forIds,
  ) async {
    if (_typeFilter != _TypeFilter.all) return;
    final cache = YtVideoCacheStore(ref.read(keyValueStoreProvider));
    final preview = <_ChannelVideo>[];
    for (final c in channels) {
      final cached = [...await cache.load(c.id)]
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      for (final v in cached.take(_videosPerChannel)) {
        preview.add(_ChannelVideo(video: v, channel: c));
      }
    }
    preview.sort((a, b) => b.video.publishedAt.compareTo(a.video.publishedAt));
    // 這段讀快取期間篩選範圍可能已經換了，換了就不要蓋上去。
    if (!mounted || _videosLoadedFor != forIds) return;
    setState(() => _videoPreview = preview);
  }

  /// 依目前排序方式排好的頻道，分四層：置頂排最前面（2026-09-30）、
  /// 一般、冷藏（2026-10-02，見 [YtChannel.coldAt]）、待評鑑排最後。
  /// 每一區裡面都套同一個排序方式，切排序時各區一致——置頂區原本固定
  /// 照置頂時間新到舊，2026-10-06 使用者要求改成也照當下的排序方式。
  /// 訂閱人數沒資料（沒更新到、或隱藏）的排最後，同人數的維持原本順序
  /// （[List.sort] 不保證穩定，所以自己帶原始位置比）。
  List<YtChannel> _sortedChannels(List<YtChannel> channels) {
    final pinned = _bySort([
      for (final c in channels)
        if (c.pinnedAt != null) c,
    ]);
    final rest = [
      for (final c in channels)
        if (c.pinnedAt == null && c.coldAt == null && !c.pendingReview) c,
    ];
    final cold = [
      for (final c in channels)
        if (c.pinnedAt == null && c.coldAt != null) c,
    ];
    // 待評鑑排最後（2026-10-06 使用者要求：放在比冷藏還下面）。
    final pending = [
      for (final c in channels)
        if (c.pendingReview) c,
    ];
    return [...pinned, ..._bySort(rest), ..._bySort(cold), ..._bySort(pending)];
  }

  List<YtChannel> _bySort(List<YtChannel> list) {
    if (_sort == _ChannelSort.normal) return list;
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
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

  /// [channels] 只是用來排程「現在有畫面正在顯示，該檢查一下了」的觸發
  /// 時機，實際挑哪些頻道要更新是共用函式 [refreshYtSubscriberStats] 另外
  /// 抓「全部」（含垃圾桶、看過但不喜歡）來看——2026-09-29 使用者要求：
  /// 不管有沒有刪除、喜不喜歡都要記一份訂閱數歷史／定期更新，不能因為
  /// 丟進垃圾桶或分到不喜歡就斷了更新。
  Future<void> _ensureStats(List<YtChannel> channels) async {
    if (_statsInFlight) return;
    final apiKey = ref.read(ytApiKeyProvider);
    if (apiKey == null || apiKey.isEmpty) return;
    _statsInFlight = true;
    try {
      final result = await refreshYtSubscriberStats(ref, skipIds: _statsTried);
      _statsTried.addAll(result.attempted);
      if (mounted && result.updated.isNotEmpty) _reload();
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

  /// 抓某個特殊清單（UUSH／UULV）裡的影片 id 集合，純粹拿來核對「這部
  /// 影片是不是這個類型」用，不是拿來當顯示內容的來源——「全部」一律用
  /// 原始上傳清單當底，這個只補標籤，抓失敗（404／其他錯誤）就當空
  /// 集合，頂多這批影片分類不出來，不影響原始清單照樣顯示。
  Future<Set<String>> _fetchTypedIds(
    YoutubeApiService service,
    String playlistId,
    YtChannel channel,
  ) async {
    try {
      final videos = await service.fetchRecentVideos(
        playlistId,
        maxResults: 50,
      );
      return {for (final v in videos) v.videoId};
    } on YoutubeApiException catch (e) {
      if (e.status != 404) {
        AppLog.add(
          '[YT] 核對「${channel.name}」的 $playlistId 清單失敗（分類可能不準）：$e',
          isError: true,
        );
      }
      return const {};
    }
  }

  Future<List<_ChannelVideo>> _fetchVideos(
    List<YtChannel> channels,
    String apiKey,
  ) async {
    final service = YoutubeApiService(apiKey);
    final repo = ref.read(ytTrackerRepositoryProvider);
    final type = _typeFilter;
    final results = <_ChannelVideo>[];
    for (final original in channels) {
      var channel = original;
      if (channel.uploadsPlaylistId.isEmpty) {
        final handle = YoutubeApiService.parseHandle(channel.url);
        if (handle == null) continue; // 沒網址／沒 @handle，這個頻道跳過
        final info = await service.fetchChannelInfo(handle);
        channel = channel.copyWith(
          // 順便拿這次呼叫本來就有的官方頭貼——但只在使用者自己沒貼過
          // 圖片網址時才覆蓋，不要蓋掉使用者手動選的圖。
          avatarImageUrl: channel.avatarImageUrl.isEmpty
              ? info.avatarUrl
              : null,
          youtubeChannelId: info.channelId,
          uploadsPlaylistId: info.uploadsPlaylistId,
          subscriberCount: info.subscriberCount,
          subscribersHidden: info.subscribersHidden,
          statsUpdatedAt: DateTime.now(),
        );
        // 解析結果快取回本機，下次同一個頻道不用再打一次 channels.list。
        await repo.updateChannel(channel);
      }
      final uploads = channel.uploadsPlaylistId;
      if (type == _TypeFilter.all || !uploads.startsWith('UU')) {
        // 「全部」一定要抓原始上傳清單當底——這個清單定義上就是「全部」，
        // 不會漏（2026-09-30 使用者提議：抓全部再拿 UUSH／UULV 的 id 去比
        // 對貼標籤，比「UULF+UUSH+UULV 組合起來當作全部」更保險——組合
        // 起來要是哪個特殊清單漏了誰，全部就會跟著漏；用原始清單當底、
        // 特殊清單只拿來「貼標籤」，就算特殊清單有漏，頂多是那部影片
        // 分類不出來，不會整部影片憑空消失）。組不出特殊清單 id 的頻道
        // （少數不是 `UU` 開頭的）也一樣，只是貼不了標籤。
        final videos = await service.fetchRecentVideos(
          uploads,
          maxResults: _videosPerChannel,
        );
        if (videos.isEmpty || !uploads.startsWith('UU')) {
          for (final v in videos) {
            results.add(_ChannelVideo(video: v, channel: channel));
          }
          continue;
        }
        final rest = uploads.substring(2);
        // 特殊清單只拿來核對「這部是不是 Shorts／直播」，抓寬一點
        // （50 部，quota 一樣是 1 單位不會比較貴）讓比對範圍盡量蓋過
        // 原始清單抓到的這幾部，同一招在 `yt_tracker_channel_page.dart`
        // 的上傳頻率圖已經用過。
        final shortIds = await _fetchTypedIds(service, 'UUSH$rest', channel);
        final liveIds = await _fetchTypedIds(service, 'UULV$rest', channel);
        for (final v in videos) {
          final isLive = liveIds.contains(v.videoId);
          final isShort = !isLive && shortIds.contains(v.videoId);
          results.add(
            _ChannelVideo(
              video: v.withShort(isShort).withLive(isLive),
              channel: channel,
            ),
          );
        }
        continue;
      }
      // 選了特定類型：直接抓那個類型自己的特殊清單，比「抓全部再篩」
      // 更準——你要看的就是那個清單本身的內容，不是「剛好落在最近幾部
      // 範圍內又符合條件」的子集合。
      final rest = uploads.substring(2);
      final prefix = switch (type) {
        _TypeFilter.shorts => 'UUSH',
        _TypeFilter.live => 'UULV',
        _ => 'UULF',
      };
      List<YoutubeVideo> videos;
      try {
        videos = await service.fetchRecentVideos(
          '$prefix$rest',
          maxResults: _videosPerChannel,
        );
      } on YoutubeApiException catch (e) {
        // 404 是明確答案：這個頻道真的沒有這個類型（例如從沒開過直播、
        // 沒發過 Shorts），這個頻道這次篩選就是 0 部。其他錯誤（網路、
        // 配額、暫時性問題）當這個頻道這次抓不到，跳過就好，不要讓一次
        // 暫時性錯誤擋掉其他頻道都顯示不出來（2026-09-30 使用者糾正：
        // 404 本身就是判斷結果，不需要用時長瞎猜）。
        videos = const [];
        if (e.status != 404) {
          AppLog.add('[YT] 抓「${channel.name}」的$prefix清單失敗：$e', isError: true);
        }
      }
      for (final v in videos) {
        final tagged = switch (type) {
          _TypeFilter.shorts => v.withShort(true).withLive(false),
          _TypeFilter.live => v.withShort(false).withLive(true),
          _ => v.withShort(false).withLive(false),
        };
        results.add(_ChannelVideo(video: tagged, channel: channel));
      }
    }
    // 時長要多打一次 videos.list，這裡混了好幾個頻道，一次把所有影片
    // id 湊在一起問，不要每個頻道各打一次——省配額，最多一次 50 個 id
    // 這個 App 用量遠遠用不到那個上限。這次失敗就算了，清單照樣顯示，
    // 只是沒有時長角標。
    try {
      final durations = await service.fetchDurations([
        for (final r in results) r.video.videoId,
      ]);
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

  /// 只選一個分類、而且那個分類有底圖時，標題前面的小圖；其餘回 null。
  Widget? _titleImage(List<YtCategory> categories) {
    if (_selected.length != 1) return null;
    final match = categories.where((c) => c.id == _selected.single);
    if (match.isEmpty || match.first.imageUrl.isEmpty) return null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 22,
        height: 22,
        child: YtCategoryImage(
          url: match.first.imageUrl,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  String _title(List<YtCategory> categories) {
    final title = _plainTitle(categories);
    return widget.trash ? '垃圾桶・$title' : title;
  }

  String _plainTitle(List<YtCategory> categories) {
    if (_selected.isEmpty) return '全部頻道';
    if (_selected.length == 1) {
      if (_selected.first == ytUncategorizedId) return '未分類';
      final match = categories.where((c) => c.id == _selected.first);
      if (match.isNotEmpty) return match.first.name;
    }
    return '已選 ${_selected.length} 個分類';
  }

  Future<void> _showAddChannelDialog(List<YtCategory> categories) async {
    final added = await showAddYtChannelDialog(
      context,
      ref,
      categories: categories,
      initialCategoryId:
          _selected.length == 1 && _selected.first != ytUncategorizedId
          ? _selected.first
          : null,
    );
    if (added && mounted) _reload();
  }

  Future<void> _moveChannel(YtChannel c, List<YtCategory> categories) async {
    final result = await showDialog<({String? id})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text(
          '「${c.name}」移到…',
          style: const TextStyle(color: AppColors.ink, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CategoryPickChip(
                label: '未分類',
                color: AppColors.ink3,
                selected: c.categoryId == null,
                onTap: () => Navigator.pop(dialogContext, (id: null)),
              ),
              for (final cat in categories)
                _CategoryPickChip(
                  label: cat.name,
                  color: cat.color,
                  selected: c.categoryId == cat.id,
                  onTap: () => Navigator.pop(dialogContext, (id: cat.id)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(c.copyWith(categoryId: result.id));
    if (mounted) _reload();
  }

  Future<void> _deleteChannel(YtChannel c) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '刪除「${c.name}」？',
      message: '刪除後挖掘新頻道也不會再挖到它。',
      confirmLabel: '刪除',
    );
    if (!ok) return;
    await ref.read(ytTrackerRepositoryProvider).deleteChannel(c.id);
    if (mounted) _reload();
  }

  /// 垃圾桶模式：從垃圾桶還原。
  Future<void> _restoreChannel(YtChannel c) async {
    await ref.read(ytTrackerRepositoryProvider).restoreChannel(c.id);
    if (!mounted) return;
    _reload();
    showAppNotice(context, '已還原「${c.name}」');
  }

  /// 垃圾桶模式：永久刪除（不能再還原，一定要確認）。
  Future<void> _purgeChannel(YtChannel c) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '永久刪除「${c.name}」？',
      message:
          '之後垃圾桶就看不到它了，不能再還原。\n（如果還有別台裝置沒同步過這次刪除，'
          '之後同步時它可能又會出現在垃圾桶裡。）',
      confirmLabel: '永久刪除',
    );
    if (!ok) return;
    await ref.read(ytTrackerRepositoryProvider).purgeChannel(c.id);
    if (mounted) _reload();
  }

  /// 置頂／取消置頂（2026-09-30 使用者要求）。[YtChannel.pinnedAt] 本來
  /// 就跟著頻道一起同步，這裡只是切換那個欄位、存檔，不用另外處理
  /// 同步邏輯。
  Future<void> _togglePin(YtChannel c) async {
    final pinning = c.pinnedAt == null;
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(
          c.copyWith(
            pinnedAt: pinning ? DateTime.now() : null,
            // 置頂跟冷藏互斥：冷藏的頻道直接按置頂，就是把它拉回最上面，
            // 不用先移出冷藏再置頂兩步。
            coldAt: pinning ? null : c.coldAt,
            // 分過區就算評鑑過，之後取消置頂回到一般，不會掉回待評鑑。
            reviewedAt: c.reviewedAt ?? DateTime.now(),
          ),
        );
    if (mounted) _reload();
  }

  /// 放進／移出冷藏區（2026-10-02 使用者要求：不常看、但也還不想刪的
  /// 頻道放到分類頁最下面，見 [YtChannel.coldAt]）。跟置頂互斥。
  Future<void> _toggleCold(YtChannel c) async {
    final freezing = c.coldAt == null;
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(
          c.copyWith(
            coldAt: freezing ? DateTime.now() : null,
            pinnedAt: freezing ? null : c.pinnedAt,
            reviewedAt: c.reviewedAt ?? DateTime.now(),
          ),
        );
    if (mounted) _reload();
  }

  /// 放到「一般」區（2026-10-06：待評鑑的頻道要自己分過去；置頂、冷藏
  /// 的也能直接一步放回一般）。
  Future<void> _setNormal(YtChannel c) async {
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(
          c.copyWith(pinnedAt: null, coldAt: null, reviewedAt: DateTime.now()),
        );
    if (mounted) _reload();
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
      return SingleChildScrollView(
        child: InlineEmptyCard(
          title: '這個分類還沒有頻道',
          message: '換個分類看看，或到首頁新增頻道',
          actions: [
            if (_selected.isNotEmpty)
              EmptyAction('看全部分類', () => setState(_selected.clear)),
          ],
        ),
      );
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
                  _TypeChip(
                    label: '直播',
                    selected: _typeFilter == _TypeFilter.live,
                    onTap: () => setState(() => _typeFilter = _TypeFilter.live),
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
                      // 先顯示舊的、背景更新（2026-10-02 使用者選的第 5 版）。
                      final preview = _videoPreview;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ThinRefreshBar(),
                          const SizedBox(height: Gap.sm),
                          RefreshingPill(
                            label: preview.isEmpty
                                ? '正在向 YouTube 拿影片…'
                                : '正在檢查新影片…',
                          ),
                          const SizedBox(height: Gap.xs),
                          if (preview.isNotEmpty)
                            Expanded(
                              child: ListView.separated(
                                itemCount: preview.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: AppColors.glassEdge,
                                ),
                                itemBuilder: (_, i) => YtVideoRow(
                                  key: ValueKey(preview[i].video.videoId),
                                  video: preview[i].video,
                                  subtitle:
                                      '${preview[i].channel.name}・${ytRelativeTime(preview[i].video.publishedAt)}',
                                  fromCache: true,
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    if (snap.hasError) {
                      return SingleChildScrollView(
                        child: InlineEmptyCard(
                          title: '影片抓不下來',
                          message: '${snap.error}',
                          actions: [
                            EmptyAction(
                              '重新整理',
                              () => _ensureVideosLoaded(channels, force: true),
                            ),
                          ],
                        ),
                      );
                    }
                    // 類型篩選已經在抓的時候做掉了（見 _fetchVideos），這裡直接用。
                    final videos = snap.data ?? const [];
                    if (videos.isEmpty) {
                      final typed = _typeFilter != _TypeFilter.all;
                      return SingleChildScrollView(
                        child: InlineEmptyCard(
                          title: '這裡空空的',
                          message: typed
                              ? '這些頻道最近沒有這個類型的影片'
                              : '這些頻道抓不到影片，可能還沒發過公開影片',
                          actions: [
                            if (typed)
                              EmptyAction(
                                '看全部類型',
                                () => setState(
                                  () => _typeFilter = _TypeFilter.all,
                                ),
                              ),
                            EmptyAction(
                              '重新整理',
                              () => _ensureVideosLoaded(channels, force: true),
                            ),
                          ],
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
                          // 一定要給明確的 key，不然排序／篩選讓清單位置
                          // 洗牌時，Flutter 會照位置重用 State，導致
                          // 「已看過」「隱藏」這些各自獨立的內部狀態被
                          // 錯配到別支影片上（2026-09-30 使用者回報：
                          // 已看過的標籤重新整理後不見了，就是這個坑）。
                          key: ValueKey(item.video.videoId),
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

                      // 選中剛好一個「真的」分類（不是未分類、也不是挖掘
                      // 新頻道那個系統用的特殊分類）才給「刪除分類」按鈕
                      // （2026-09-29 使用者要求：進了分類頁上面也要能直接
                      // 刪，不是只有 YT 首頁長按才刪得到）。
                      YtCategory? selectedCategory;
                      if (_selected.length == 1 &&
                          _selected.single != ytUncategorizedId &&
                          _selected.single != ytDiscoverCategoryId) {
                        for (final c in categories) {
                          if (c.id == _selected.single) {
                            selectedCategory = c;
                            break;
                          }
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTopBar(
                            title: _title(categories),
                            // 單看一個分類：標題前面放那個分類的底圖，縮成
                            // 跟功能標題圖示一樣小（2026-10-06 使用者要求）；
                            // 其他情況放 YT 的紅色圖示。
                            titleIcon: widget.trash
                                ? Icons.delete_outline_rounded
                                : Icons.subscriptions_rounded,
                            titleIconColor: AppColors.ytAccent,
                            titleLeading: _titleImage(categories),
                            actions: [
                              // 垃圾桶模式不給新增頻道、挖掘、刪除分類。
                              if (!widget.trash) ...[
                                // 「挖掘新頻道」是特別的分類，只是用來放挖到的頻道，
                                // 不是使用者自己手動整理的地方，所以不給「新增頻道」
                                // （2026-09-29 使用者要求），改給「挖掘新頻道」按鈕
                                // ——本來只有 YT 首頁有，進了這個分類頁還要回首頁
                                // 才能再挖一次太繞（2026-09-29 使用者要求）。
                                if (_selected.length == 1 &&
                                    _selected.single == ytDiscoverCategoryId)
                                  IconButton(
                                    onPressed: () => runYtChannelDiscovery(
                                      context,
                                      ref,
                                      onDone: _reload,
                                    ),
                                    icon: const Icon(
                                      Icons.travel_explore_rounded,
                                      size: 20,
                                    ),
                                    color: AppColors.ink2,
                                    tooltip: '挖掘新頻道',
                                  )
                                else
                                  IconButton(
                                    onPressed: () =>
                                        _showAddChannelDialog(categories),
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                    ),
                                    color: AppColors.ink2,
                                    tooltip: '新增頻道',
                                  ),
                              ],
                              // 這個分類（或選的幾個分類）的頻道紀錄（2026-10-06
                              // 使用者要求：分類頁也要有；放在新增頻道右邊、
                              // 刪除分類左邊）。
                              IconButton(
                                onPressed: () => context.push(
                                  '/yt-tracker/log',
                                  extra: {..._selected},
                                ),
                                icon: const Icon(
                                  Icons.history_rounded,
                                  size: 20,
                                ),
                                color: AppColors.ink2,
                                tooltip: '頻道紀錄',
                              ),
                              if (!widget.trash) ...[
                                if (selectedCategory != null)
                                  IconButton(
                                    onPressed: () async {
                                      final deleted = await deleteYtCategory(
                                        context,
                                        ref,
                                        selectedCategory!,
                                      );
                                      // 分類本身沒了，留在這頁沒意義，刪完
                                      // 直接退回分類格子那頁。
                                      if (deleted && context.mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                    ),
                                    color: AppColors.ink2,
                                    tooltip: '刪除分類',
                                  ),
                              ],
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
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 6),
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
                                value: _ViewMode.channel,
                                label: Text('依頻道顯示'),
                              ),
                              ButtonSegment(
                                value: _ViewMode.video,
                                label: Text('依影片顯示'),
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
                              side: const BorderSide(
                                color: AppColors.glassEdge,
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: _mode == _ViewMode.channel
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          _TypeChip(
                                            label: '預設排序',
                                            selected:
                                                _sort == _ChannelSort.normal,
                                            onTap: () => setState(
                                              () => _sort = _ChannelSort.normal,
                                            ),
                                          ),
                                          _TypeChip(
                                            label: '訂閱人數 多→少',
                                            selected:
                                                _sort == _ChannelSort.subsDesc,
                                            onTap: () => setState(
                                              () =>
                                                  _sort = _ChannelSort.subsDesc,
                                            ),
                                          ),
                                          _TypeChip(
                                            label: '訂閱人數 少→多',
                                            selected:
                                                _sort == _ChannelSort.subsAsc,
                                            onTap: () => setState(
                                              () =>
                                                  _sort = _ChannelSort.subsAsc,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: Gap.sm),
                                      Expanded(
                                        child: _ChannelGrid(
                                          channels: _sortedChannels(channels),
                                          // 只有單獨看「挖掘新頻道」分類時才秀來源標籤
                                          // （2026-09-29 使用者要求：僅在挖掘分類才顯示）。
                                          showDiscoveredBadge:
                                              _selected.length == 1 &&
                                              _selected.single ==
                                                  ytDiscoverCategoryId,
                                          onOpen: (c) => context
                                              .push(
                                                '/yt-tracker/channel/${c.id}',
                                              )
                                              .then((_) => _reload()),
                                          onMove: (c) =>
                                              _moveChannel(c, categories),
                                          onTogglePin: _togglePin,
                                          onToggleCold: _toggleCold,
                                          onSetNormal: _setNormal,
                                          onDelete: _deleteChannel,
                                          trash: widget.trash,
                                          onRestore: _restoreChannel,
                                          onPurge: _purgeChannel,
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

enum _ChannelMenuAction {
  edit,
  move,
  pin,
  normal,
  cold,
  delete,
  restore,
  purge,
}

/// 「挖掘新頻道」分類卡右上角的小標籤，顯示是靠哪個關鍵字／哪個頻道推薦
/// 挖到的（2026-09-29 使用者要求，見 [YtChannel.discoveredVia]）。
class _DiscoveredViaBadge extends StatelessWidget {
  const _DiscoveredViaBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 90),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 訂閱人數更新的實際邏輯，公開成頂層函式（2026-09-29 使用者要求：不只
/// 「依頻道顯示」那頁背景排程，YT 首頁一打開、設定頁按「儲存」也都要能
/// 觸發同一套檢查，不要各自重寫一份）。抓「全部」頻道（含垃圾桶、看過
/// 但不喜歡，見 [YtTrackerRepository.channelsForUpload]）挑出超過設定
/// 天數沒問過的，批次問 API，順便把每筆結果記一份訂閱數歷史快照
/// （[YtSubscriberHistoryStore]，不管頻道有沒有被刪除都記）。
///
/// [skipIds] 是呼叫端自己這個 session 已經試過（不管成功與否）的頻道
/// id，不再重試——避免解析不出來的頻道每次呼叫都重打 API。回傳
/// `attempted`：這次挑出來嘗試過的全部 id（不管有沒有成功，呼叫端要
/// 用它累積進自己的 skip 清單）；`updated`：真的問到新資料、已經存檔
/// 的頻道。
Future<({List<YtChannel> updated, Set<String> attempted})>
refreshYtSubscriberStats(
  WidgetRef ref, {
  Set<String> skipIds = const {},
}) async {
  final apiKey = ref.read(ytApiKeyProvider);
  if (apiKey == null || apiKey.isEmpty) {
    return (updated: const <YtChannel>[], attempted: const <String>{});
  }
  final now = DateTime.now();
  // 多久重新問一次，使用者在設定頁調（2026-09-29 使用者要求：原本寫死
  // 12 小時，改成可設定天數，預設一週一輪）。
  final refreshEvery = Duration(days: ref.read(ytStatsRefreshDaysProvider));
  final repo = ref.read(ytTrackerRepositoryProvider);
  final all = await repo.channelsForUpload();
  final stale = [
    for (final c in all)
      if (!skipIds.contains(c.id) &&
          (c.statsUpdatedAt == null ||
              now.difference(c.statsUpdatedAt!) > refreshEvery))
        c,
  ];
  final attempted = {for (final c in stale) c.id};
  if (stale.isEmpty) {
    return (updated: const <YtChannel>[], attempted: attempted);
  }
  final service = YoutubeApiService(apiKey);
  final history = YtSubscriberHistoryStore(ref.read(keyValueStoreProvider));
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
    if (info.subscriberCount != null) {
      await history.add(
        c.id,
        YtSubscriberSnapshot(at: now, count: info.subscriberCount!),
      );
    }
    updated.add(
      c.copyWith(
        avatarImageUrl: c.avatarImageUrl.isEmpty ? info.avatarUrl : null,
        youtubeChannelId: info.channelId,
        uploadsPlaylistId: info.uploadsPlaylistId,
        subscriberCount: info.subscriberCount,
        subscribersHidden: info.subscribersHidden,
        statsUpdatedAt: now,
        videoCount: info.videoCount,
      ),
    );
  }
  final stats = await service.fetchSubscriberStats([
    for (final c in withId) c.youtubeChannelId,
  ]);
  for (final c in withId) {
    final s = stats[c.youtubeChannelId];
    if (s == null) continue;
    if (s.count != null) {
      await history.add(c.id, YtSubscriberSnapshot(at: now, count: s.count!));
    }
    updated.add(
      c.copyWith(
        subscriberCount: s.count,
        subscribersHidden: s.hidden,
        videoCount: s.videoCount,
        statsUpdatedAt: now,
      ),
    );
  }
  if (updated.isNotEmpty) await repo.updateChannels(updated);
  return (updated: updated, attempted: attempted);
}

/// 新增頻道：貼網址就會自動用 YouTube API 抓頻道名稱跟大頭貼（2026-09-24
/// 使用者要求：只想貼網址、選分類）。抓到的資料一起存進頻道（頻道 ID、
/// 上傳清單 ID、訂閱人數），之後不用再解析一次。沒有 API 金鑰或抓不到
/// 時退回手動填名稱／頭像網址。公開成頂層函式（2026-09-29 使用者要求：
/// YT 首頁分類列表也要能直接新增頻道，不用先點進某個分類），回傳是否
/// 真的新增了（給呼叫端決定要不要重新整理列表）。
///
/// 打開就自動讀剪貼簿（2026-10-05 使用者要求）：iPhone Safari 每次讀剪貼簿
/// 都一定會跳系統的「貼上」小泡泡、網頁沒辦法跳過，原本要先按 App 的
/// 「貼上」再按 Safari 的「貼上」兩下，改成一打開就讀、只剩 Safari 那一下。
/// Safari 只在「使用者剛點完」那一刻准讀，所以讀取要在任何 await 之前就
/// 發出去——呼叫端自己得先 await 別的東西的話，先呼叫
/// [readYtChannelClipboard] 把結果用 [clipboard] 傳進來。剪貼簿內容不像
/// YouTube 頻道網址就不填，「貼上」按鈕照舊留著。
Future<bool> showAddYtChannelDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<YtCategory> categories,
  String? initialCategoryId,
  Future<String?>? clipboard,
}) async {
  final autoClipboard = clipboard ?? readYtChannelClipboard();
  final nameController = TextEditingController();
  final urlController = TextEditingController();
  final avatarController = TextEditingController();
  final descriptionController = TextEditingController();
  String? categoryId = initialCategoryId;

  YoutubeChannelInfo? info;
  String? status; // 給使用者看的一行狀態
  var statusIsError = false;
  var fetching = false;
  var nameTouched = false; // 使用者自己改過名稱就不要再蓋掉
  String? lastHandle;
  Timer? debounce;
  var autoPasteHooked = false;
  // 已經有的頻道（含垃圾桶裡的），貼網址、抓到頻道 ID 時都拿來比對，
  // 同一個頻道不能新增第二次（2026-10-05 使用者回報會重複新增）。
  final existing = await ref
      .read(ytTrackerRepositoryProvider)
      .channelsForUpload();
  String? duplicate; // 不是 null 就是重複的提示文字，「新增」鍵會停用

  // 永久刪除過的頻道（[YtChannel.purgedAt]）不算重複：使用者自己手動新增
  // 同一個頻道就是想要它回來，送出時直接把那筆救回來（2026-10-06）。
  final purged = [
    for (final c in existing)
      if (c.purgedAt != null) c,
  ];
  final active = [
    for (final c in existing)
      if (c.purgedAt == null) c,
  ];

  String? duplicateMessage({String youtubeChannelId = '', String url = ''}) {
    final d = findDuplicateYtChannel(
      active,
      youtubeChannelId: youtubeChannelId,
      url: url,
    );
    if (d == null) return null;
    if (d.deletedAt != null) {
      return '「${d.name}」已經在垃圾桶裡，到垃圾桶還原就好';
    }
    final category = d.categoryId == null
        ? '未分類'
        : categories.where((c) => c.id == d.categoryId).firstOrNull?.name ??
              '未分類';
    return '這個頻道已經新增過了：「${d.name}」（$category）';
  }

  if (!context.mounted) return false;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> fetchInfo(String handle) async {
          final apiKey = ref.read(ytApiKeyProvider);
          if (apiKey == null || apiKey.isEmpty) {
            setDialogState(() {
              status = '還沒設定 API 金鑰，無法自動抓取，請手動填名稱與頭像';
              statusIsError = true;
            });
            return;
          }
          setDialogState(() {
            fetching = true;
            status = '讀取頻道資料中…';
            statusIsError = false;
          });
          try {
            final result = await YoutubeApiService(
              apiKey,
            ).fetchChannelInfo(handle);
            if (lastHandle != handle) return; // 網址又改了，這筆過期
            final dup = duplicateMessage(youtubeChannelId: result.channelId);
            if (dup != null) {
              setDialogState(() {
                info = null;
                fetching = false;
                duplicate = dup;
                status = dup;
                statusIsError = true;
              });
              return;
            }
            setDialogState(() {
              info = result;
              fetching = false;
              if (!nameTouched) nameController.text = result.title;
              avatarController.text = result.avatarUrl.replaceFirst(
                RegExp(r'=s\d+.*$'),
                '=s160-c-k-c0x00ffffff-no-rj',
              );
              status = '已抓到：${result.title}';
              statusIsError = false;
            });
          } catch (e) {
            if (lastHandle != handle) return;
            setDialogState(() {
              info = null;
              fetching = false;
              status = '自動抓取失敗（$e），請手動填名稱與頭像';
              statusIsError = true;
            });
          }
        }

        void onUrlChanged(String value) {
          debounce?.cancel();
          final handle = YoutubeApiService.parseHandle(value);
          // 網址本身就認得出是已經有的頻道，不用再花 API 額度去抓。
          final dup = duplicateMessage(url: value);
          if (dup != null) {
            lastHandle = handle;
            setDialogState(() {
              info = null;
              duplicate = dup;
              status = dup;
              statusIsError = true;
            });
            return;
          }
          // 換成不重複的網址：馬上把收起來的欄位放回來。
          if (duplicate != null) {
            setDialogState(() {
              duplicate = null;
              status = null;
            });
          }
          if (handle == null) {
            lastHandle = null;
            setDialogState(() {
              info = null;
              status = null;
            });
            return;
          }
          if (handle == lastHandle) return;
          lastHandle = handle;
          debounce = Timer(const Duration(milliseconds: 500), () {
            fetchInfo(handle);
          });
        }

        if (!autoPasteHooked) {
          autoPasteHooked = true;
          autoClipboard.then((text) {
            if (text == null ||
                !context.mounted ||
                urlController.text.isNotEmpty ||
                !looksLikeYtChannelUrl(text)) {
              return;
            }
            urlController.text = text;
            setDialogState(() {});
            onUrlChanged(text);
          });
        }

        final hasAvatar = avatarController.text.trim().isNotEmpty;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('新增頻道', style: TextStyle(color: AppColors.ink)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 網址只能用貼的，不給打字（2026-09-29 使用者要求：一長串
                // 網址沒有人會手動慢慢輸入，跳鍵盤反而礙事）。用按鈕讀
                // 剪貼簿內容，不是輸入框。
                Text('頻道網址', style: AppText.note),
                const SizedBox(height: Gap.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassEdge),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          urlController.text.isEmpty
                              ? '按右邊「貼上」讀取剪貼簿網址'
                              : urlController.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: urlController.text.isEmpty
                                ? AppColors.ink3
                                : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      TextButton.icon(
                        onPressed: () async {
                          final text = await readYtChannelClipboard();
                          if (text == null) return;
                          urlController.text = text;
                          setDialogState(() {});
                          onUrlChanged(text);
                        },
                        icon: const Icon(
                          Icons.content_paste_go_rounded,
                          size: 16,
                        ),
                        label: const Text('貼上'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      if (fetching)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          status!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: statusIsError ? AppColors.mid : AppColors.ok,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 偵測到重複就只留網址跟提示，名稱、頭像、分類都用不到，收起來
                // （2026-10-05 使用者要求）。
                if (duplicate == null) ...[
                  const SizedBox(height: Gap.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasAvatar)
                        Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 6),
                          child: ClipOval(
                            child: Image.network(
                              avatarController.text.trim(),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  const SizedBox(width: 40, height: 40),
                            ),
                          ),
                        ),
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          onChanged: (_) => nameTouched = true,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: '頻道名稱（可改）',
                            counterText: '',
                          ),
                          style: const TextStyle(color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                  if (!hasAvatar || info == null) ...[
                    const SizedBox(height: Gap.xs),
                    TextField(
                      controller: avatarController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: '頭像圖片網址（沒自動抓到才需要）',
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
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
                          onTap: () =>
                              setDialogState(() => categoryId = cat.id),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: fetching || duplicate != null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('新增'),
            ),
          ],
        );
      },
    ),
  );
  debounce?.cancel();
  final name = nameController.text.trim();
  if (saved != true || name.isEmpty) return false;
  final fetched = info;
  // 送出前再比一次：沒有 API 金鑰時只能靠網址比，這裡把手動填的情況也
  // 擋下來。
  final lateDup = duplicateMessage(
    youtubeChannelId: fetched?.channelId ?? '',
    url: urlController.text,
  );
  if (lateDup != null) {
    if (context.mounted) showAppNotice(context, lateDup, isError: true);
    return false;
  }
  // 是永久刪除過的頻道：救回原本那筆（保留當初的紀錄），套上這次選的分類
  // 跟名稱，不另外新增一筆。
  final revive = findDuplicateYtChannel(
    purged,
    youtubeChannelId: fetched?.channelId ?? '',
    url: urlController.text,
  );
  if (revive != null) {
    await ref
        .read(ytTrackerRepositoryProvider)
        .updateChannel(
          revive.restored().copyWith(
            // 救回來的跟新加的一樣，先放待評鑑。
            reviewedAt: null,
            name: name,
            categoryId: categoryId,
            pinnedAt: null,
            coldAt: null,
          ),
        );
    return context.mounted;
  }
  await ref
      .read(ytTrackerRepositoryProvider)
      .addChannel(
        YtChannel(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          categoryId: categoryId,
          avatarImageUrl: avatarController.text.trim(),
          url: urlController.text.trim(),
          description: descriptionController.text.trim(),
          addedAt: DateTime.now(),
          youtubeChannelId: fetched?.channelId ?? '',
          uploadsPlaylistId: fetched?.uploadsPlaylistId ?? '',
          subscriberCount: fetched?.subscriberCount,
          subscribersHidden: fetched?.subscribersHidden ?? false,
          statsUpdatedAt: fetched == null ? null : DateTime.now(),
        ),
      );
  return context.mounted;
}

/// 讀剪貼簿的文字，讀不到（權限被擋、瀏覽器不支援、空的）回傳 null。
Future<String?> readYtChannelClipboard() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    return text == null || text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

/// 剪貼簿內容像不像 YouTube 頻道網址——自動貼上只填像的，不然隨便複製的
/// 一段文字也會被塞進網址欄。
bool looksLikeYtChannelUrl(String text) =>
    text.contains('youtube.com') ||
    text.contains('youtu.be') ||
    YoutubeApiService.parseHandle(text) != null;

class _ChannelGrid extends StatefulWidget {
  const _ChannelGrid({
    required this.channels,
    required this.onOpen,
    required this.onMove,
    required this.onTogglePin,
    required this.onToggleCold,
    required this.onSetNormal,
    required this.onDelete,
    this.showDiscoveredBadge = false,
    this.trash = false,
    this.onRestore,
    this.onPurge,
  });

  final List<YtChannel> channels;
  final void Function(YtChannel) onOpen;
  final void Function(YtChannel) onMove;
  final void Function(YtChannel) onTogglePin;
  final void Function(YtChannel) onToggleCold;
  final void Function(YtChannel) onSetNormal;
  final void Function(YtChannel) onDelete;

  /// 垃圾桶模式（見 [YtTrackerBrowsePage.trash]）：選單的「刪除」換成
  /// [onRestore]「還原」＋[onPurge]「永久刪除」，其餘選項照舊。
  final bool trash;
  final void Function(YtChannel)? onRestore;
  final void Function(YtChannel)? onPurge;

  /// 只有正在單獨看「挖掘新頻道」分類時才是 true，其他情況一律不顯示
  /// 挖掘來源標籤（2026-09-29 使用者要求：僅在挖掘分類才顯示）。
  final bool showDiscoveredBadge;

  @override
  State<_ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<_ChannelGrid> {
  /// 冷藏區預設收起來——放進去的本來就是「不常看」的頻道，攤開來擺在
  /// 下面只會佔空間，要看再點標題展開（2026-10-02 加冷藏區時決定）。
  /// 只記在這個畫面的狀態裡，離開再進來又是收起來的。
  bool _coldExpanded = false;

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    if (channels.isEmpty) {
      return SingleChildScrollView(
        child: widget.trash
            ? const InlineEmptyCard(title: '這個分類沒有被刪除的頻道', message: '換個分類看看')
            : const InlineEmptyCard(
                title: '這個分類還沒有頻道',
                message: '換個分類看看，或到首頁新增頻道',
              ),
      );
    }
    // 分四層畫：上面置頂、中間一般、下面冷藏、最下面待評鑑（2026-09-30
    // 加置頂區、2026-10-02 使用者要求加冷藏區：不常看但還不至於刪掉的
    // 頻道；2026-10-06 加待評鑑：新加進來、還沒分區的頻道）。
    // [_sortedChannels] 已經照這個順序排好，這裡只是切段分開畫。
    final pinned = [
      for (final c in channels)
        if (c.pinnedAt != null) c,
    ];
    final cold = [
      for (final c in channels)
        if (c.pinnedAt == null && c.coldAt != null) c,
    ];
    final rest = [
      for (final c in channels)
        if (c.pinnedAt == null && c.coldAt == null && !c.pendingReview) c,
    ];
    final pending = [
      for (final c in channels)
        if (c.pendingReview) c,
    ];
    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
    );
    SliverGrid grid(List<YtChannel> list) => SliverGrid(
      gridDelegate: gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, i) => _buildCard(context, list[i]),
        childCount: list.length,
      ),
    );
    const sectionGap = SliverToBoxAdapter(
      child: Column(
        children: [
          SizedBox(height: Gap.md),
          Divider(height: 1, color: AppColors.glassEdge),
          SizedBox(height: Gap.sm),
        ],
      ),
    );
    // 每區之間的分隔線只畫在「兩區都有」的時候，某一區空著就直接跳過
    // （2026-10-06 加待評鑑後，一般區可能整個是空的）。
    final sections = <List<Widget>>[
      if (pinned.isNotEmpty)
        [
          SliverToBoxAdapter(
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin_rounded,
                  size: 13,
                  color: AppColors.ytPinAccent,
                ),
                const SizedBox(width: 4),
                Text('已置頂 · ${pinned.length}', style: AppText.note),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xs)),
          grid(pinned),
        ],
      // 一般區（沒置頂也沒冷藏）也標數量，跟置頂、冷藏區一致
      // （2026-10-06 使用者要求）。
      if (rest.isNotEmpty)
        [
          SliverToBoxAdapter(
            child: Row(
              children: [
                const Icon(
                  Icons.subscriptions_outlined,
                  size: 13,
                  color: AppColors.ink3,
                ),
                const SizedBox(width: 4),
                Text('一般 · ${rest.length}', style: AppText.note),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xs)),
          grid(rest),
        ],
      if (cold.isNotEmpty)
        [
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () => setState(() => _coldExpanded = !_coldExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.ac_unit_rounded,
                      size: 13,
                      color: AppColors.ytColdAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$ytColdSectionLabel · ${cold.length}',
                      style: AppText.note,
                    ),
                    const Spacer(),
                    Text(_coldExpanded ? '收起' : '展開', style: AppText.note),
                    Icon(
                      _coldExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_coldExpanded) ...[
            const SliverToBoxAdapter(child: SizedBox(height: Gap.xs)),
            grid(cold),
          ],
        ],
      // 待評鑑：剛加進來、還沒分到置頂／一般／冷藏的頻道，排在最下面，
      // 等使用者自己長按分區（2026-10-06 使用者要求）。
      if (pending.isNotEmpty)
        [
          SliverToBoxAdapter(
            child: Row(
              children: [
                const Icon(
                  Icons.rate_review_outlined,
                  size: 13,
                  color: AppColors.ink3,
                ),
                const SizedBox(width: 4),
                Text('待評鑑 · ${pending.length}', style: AppText.note),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    '長按頻道分到置頂／一般／冷藏',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.note,
                  ),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xs)),
          grid(pending),
        ],
    ];
    // 所有區全部當成同一份可捲動內容的 sliver，整頁一起捲（2026-09-30
    // 使用者回報原本置頂區固定不動、下面各自捲動「頁面很擠」）；用 sliver
    // 不用 SingleChildScrollView+shrinkWrap，頻道一多才不會一次全部排版。
    return CustomScrollView(
      slivers: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) sectionGap,
          ...sections[i],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
      ],
    );
  }

  Widget _buildCard(BuildContext context, YtChannel c) {
    final isPinned = c.pinnedAt != null;
    final isCold = !isPinned && c.coldAt != null;
    final stripColor = isPinned
        ? AppColors.ytPinAccent
        : isCold
        ? AppColors.ytColdAccent
        : null;
    // 長按整張卡片、或點右邊 ⋮，都在這張卡片上方跳出同一條泡泡選單
    // （2026-09-24 加長按；2026-10-02 改成泡泡橫列，見 [_showChannelMenu]）。
    // 用 Builder 拿到卡片自己的 context，泡泡的尖角才對得準這張卡片。
    // 長按不放可以直接滑到選單按鈕上放開來選（2026-10-06 使用者要求）。
    return Builder(
      builder: (cardContext) => BubbleLongPress(
        onLongPress: (_, drag) => _showChannelMenu(cardContext, c, drag: drag),
        child: InkWell(
          onTap: () => widget.onOpen(c),
          borderRadius: BorderRadius.circular(Radii.card),
          // 裁成卡片圓角，左側色條才會順著圓角收邊，不會凸出去。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: Stack(
              children: [
                Container(
                  // 有色條（置頂／冷藏）的左邊多留一點，讓出色條的位置。
                  padding: EdgeInsets.fromLTRB(
                    stripColor != null ? 13 : 10,
                    10,
                    4,
                    10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.card),
                    color: AppColors.glassFill,
                    border: Border.all(color: AppColors.glassEdge),
                  ),
                  child: Row(
                    children: [
                      // 冷藏的頭像跟名稱淡一點，一眼看得出是「收起來的」。
                      Opacity(
                        opacity: isCold ? 0.6 : 1,
                        child: YtChannelAvatar(channel: c, radius: 17),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Opacity(
                          opacity: isCold ? 0.6 : 1,
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
                      ),
                      IconButton(
                        onPressed: () => _showChannelMenu(cardContext, c),
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                        color: AppColors.ink2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: '更多',
                      ),
                    ],
                  ),
                ),
                if (widget.showDiscoveredBadge && c.discoveredVia.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _DiscoveredViaBadge(text: c.discoveredVia),
                  ),
                // 左側色條：置頂金色（2026-09-30 使用者選的「左側色條」）、
                // 冷藏冰藍色（2026-10-02），一暖一冷，普通頻道沒有色條。
                if (stripColor != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 3,
                      child: ColoredBox(color: stripColor),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 頻道操作選單：泡泡橫列（LINE／微信長按訊息那種），浮在這張卡片
  /// 上方、尖角指向它，刪除在最右邊用分隔線隔開（2026-10-02 使用者從
  /// 長按選單設計稿挑的，全 App 共用 [showBubbleMenu]）。置頂／冷藏用
  /// 各自的區域色。
  Future<void> _showChannelMenu(
    BuildContext cardContext,
    YtChannel c, {
    BubbleMenuDrag? drag,
  }) async {
    final isPinned = c.pinnedAt != null;
    final isCold = c.coldAt != null;
    final action = await showBubbleMenu<_ChannelMenuAction>(
      cardContext,
      anchor: bubbleAnchorOf(cardContext),
      drag: drag,
      items: [
        const BubbleMenuItem(
          value: _ChannelMenuAction.edit,
          icon: Icons.edit_outlined,
          label: '編輯',
        ),
        const BubbleMenuItem(
          value: _ChannelMenuAction.move,
          icon: Icons.folder_open_rounded,
          label: '移動',
        ),
        BubbleMenuItem(
          value: _ChannelMenuAction.pin,
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: isPinned ? '取消置頂' : '置頂',
          iconColor: AppColors.ytPinAccent,
        ),
        // 不在一般區（置頂、冷藏、待評鑑）才給「一般」。
        if (c.pinnedAt != null || c.coldAt != null || c.pendingReview)
          const BubbleMenuItem(
            value: _ChannelMenuAction.normal,
            icon: Icons.subscriptions_outlined,
            label: '一般',
          ),
        BubbleMenuItem(
          value: _ChannelMenuAction.cold,
          icon: Icons.ac_unit_rounded,
          label: isCold ? '取消$ytColdSectionLabel' : ytColdSectionLabel,
          iconColor: AppColors.ytColdAccent,
        ),
        if (widget.trash) ...[
          const BubbleMenuItem(
            value: _ChannelMenuAction.restore,
            icon: Icons.restore_from_trash_outlined,
            label: '還原',
            iconColor: AppColors.ok,
          ),
          const BubbleMenuItem(
            value: _ChannelMenuAction.purge,
            icon: Icons.delete_forever_outlined,
            label: '永久刪除',
            destructive: true,
          ),
        ] else
          const BubbleMenuItem(
            value: _ChannelMenuAction.delete,
            icon: Icons.delete_outline_rounded,
            label: '刪除',
            destructive: true,
          ),
      ],
    );
    switch (action) {
      case _ChannelMenuAction.edit:
        widget.onOpen(c);
      case _ChannelMenuAction.move:
        widget.onMove(c);
      case _ChannelMenuAction.pin:
        widget.onTogglePin(c);
      case _ChannelMenuAction.normal:
        widget.onSetNormal(c);
      case _ChannelMenuAction.cold:
        widget.onToggleCold(c);
      case _ChannelMenuAction.delete:
        widget.onDelete(c);
      case _ChannelMenuAction.restore:
        widget.onRestore?.call(c);
      case _ChannelMenuAction.purge:
        widget.onPurge?.call(c);
      case null:
        break;
    }
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
