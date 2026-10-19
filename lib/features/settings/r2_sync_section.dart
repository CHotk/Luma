import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../sync/sync_progress_banner.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/usdt_twd_rate_store.dart';
import '../../data/repositories/nav_bar_prefs_store.dart';
import '../../data/repositories/app_home_style_store.dart';
import '../../data/repositories/jp_home_ring_store.dart';
import '../../data/repositories/jp_light_style_store.dart';
import '../../data/repositories/yt_video_song_store.dart';
import '../../data/repositories/music_store.dart';
import '../../data/repositories/yt_embed_player_style_store.dart';
import '../../data/repositories/yt_search_recents_store.dart';
import '../../data/repositories/yt_stats_refresh_setting_store.dart';
import '../../data/repositories/yt_video_open_mode_store.dart';
import '../../data/repositories/yt_display_prefs_store.dart';
import '../../data/repositories/yt_playlist_store.dart';
import '../../data/cloud/r2_client.dart';
import '../../data/cloud/r2_credentials_store.dart';
import '../../data/cloud/r2_sync_service.dart';
import '../../data/export/device_label.dart';
import '../../data/repositories/diary_password_store.dart';
import '../../data/repositories/home_card_order_store.dart';
import '../../data/repositories/yt_category_order_store.dart';
import '../../data/repositories/yt_channel_log_store.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../shared/debug/app_log.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/glass_card.dart';

const _lastSyncedKey = 'r2_sync.last_synced_at.v1';

enum _Phase { idle, testing, success, error }

/// 「各功能同步狀況」卡片裡，單一功能目前跑到哪一步（2026-09-23
/// 使用者要求：同步頁要看得出目前是哪個功能在下載還是上傳，不是只有
/// 一顆「立即同步」按鈕看不出進度）。日記、健身都用同一組狀態，之後
/// 每加一個功能的同步，這個卡片就多加一行。
enum _FeaturePhase { idle, downloading, uploading, done, error }

/// 同步是不是正在跑，全 App 一個（2026-10-08 使用者回報：按了同步跳去別的
/// 功能，回來看起來像被取消了）。同步本身離開頁面也會跑完（見 [_syncNow]），
/// 但「同步中」原本只記在這個區塊自己的 State，換頁回來是新的 State，
/// 按鈕又能按、看起來沒在跑，再按還會同時跑兩次。放這裡，回來還是看得到
/// 「同步中」，也擋住重複同步。
final r2SyncRunningProvider = StateProvider<bool>((ref) => false);

/// 設定頁「多裝置同步」區塊，照設計稿
/// `design-history/已選擇完成/雲端同步設計/01_簡潔卡片式.html` 做：沒設定過就是
/// 輸入卡片（Account ID／Access Key ID／Secret Access Key 三欄＋
/// 「儲存並測試連線」），設定完成後換成「已連接雲端」狀態卡＋「立即
/// 同步」——第一階段（打地基）「立即同步」只做下載，還沒有上傳
/// （2026-09-23 使用者決定分階段開發，先驗證連線/簽章/資料格式）。
class R2SyncSection extends ConsumerStatefulWidget {
  const R2SyncSection({super.key, this.onLogged});

  /// 每次同步結束（不管成功失敗）寫完 [SyncLogEntry] 之後呼叫一次，讓
  /// 外層（`sync_page.dart`）知道要重讀同步紀錄卡的列表——同步紀錄的
  /// 儲存跟顯示分屬不同 widget，用這個回呼串起來，不用共用 provider
  /// 硬湊（2026-09-24）。
  final VoidCallback? onLogged;

  @override
  ConsumerState<R2SyncSection> createState() => _R2SyncSectionState();
}

/// 同步中每一項的狀態（2026-10-12 使用者回報：同步中離開同步頁再回來，
/// 頁面上每一項的進度都不見了）。原本記在頁面的 State 裡，頁面一關就丟，
/// 背景同步照跑、但新開的頁面什麼都看不到。改成放在頁面外面這一份，
/// 同步一路寫進來；頁面開著就聽它的變化重畫，關掉再開也接得上。
class _SyncUiState extends ChangeNotifier {
  bool syncing = false;
  _FeaturePhase diary = _FeaturePhase.idle;
  _FeaturePhase fitness = _FeaturePhase.idle;
  _FeaturePhase yt = _FeaturePhase.idle;
  _FeaturePhase kanaPractice = _FeaturePhase.idle;
  _FeaturePhase kanaExam = _FeaturePhase.idle;
  _FeaturePhase english = _FeaturePhase.idle;
  _FeaturePhase appHome = _FeaturePhase.idle;
  _FeaturePhase syncLog = _FeaturePhase.idle;
  _FeaturePhase errorLog = _FeaturePhase.idle;
  final habits = <String, _FeaturePhase>{};
  final results = <String, String>{};

  void changed() => notifyListeners();
}

final _ui = _SyncUiState();

class _R2SyncSectionState extends ConsumerState<R2SyncSection> {
  final _endpointController = TextEditingController();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();

  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  DateTime? _lastSyncedAt;
  // 下面這些都是 [_ui] 的別名，見 [_SyncUiState]。
  bool get _syncing => _ui.syncing;
  set _syncing(bool v) => _ui.syncing = v;
  _FeaturePhase get _diaryPhase => _ui.diary;
  set _diaryPhase(_FeaturePhase v) => _ui.diary = v;
  _FeaturePhase get _fitnessPhase => _ui.fitness;
  set _fitnessPhase(_FeaturePhase v) => _ui.fitness = v;
  _FeaturePhase get _ytPhase => _ui.yt;
  set _ytPhase(_FeaturePhase v) => _ui.yt = v;
  _FeaturePhase get _kanaPracticePhase => _ui.kanaPractice;
  set _kanaPracticePhase(_FeaturePhase v) => _ui.kanaPractice = v;
  _FeaturePhase get _kanaExamPhase => _ui.kanaExam;
  set _kanaExamPhase(_FeaturePhase v) => _ui.kanaExam = v;
  _FeaturePhase get _englishPhase => _ui.english;
  set _englishPhase(_FeaturePhase v) => _ui.english = v;
  _FeaturePhase get _appHomePhase => _ui.appHome;
  set _appHomePhase(_FeaturePhase v) => _ui.appHome = v;
  Map<String, _FeaturePhase> get _habitPhases => _ui.habits;

  /// 交易／抽菸／喝酒／負債記錄的同步狀況列（id 對應 [_habitPhases]）。
  static const _habitRows = [
    ('trade', '交易紀錄'),
    ('smoking', '抽菸記錄'),
    ('drinking', '喝酒記錄'),
    ('debt', '負債管理'),
  ];
  _FeaturePhase get _syncLogPhase => _ui.syncLog;
  set _syncLogPhase(_FeaturePhase v) => _ui.syncLog = v;
  _FeaturePhase get _errorLogPhase => _ui.errorLog;
  set _errorLogPhase(_FeaturePhase v) => _ui.errorLog = v;

  /// 各功能這次同步的上傳／下載筆數，顯示在「各功能同步狀況」每一列
  /// 右邊（2026-09-24 使用者要求：各功能同步狀況也要看得到結果）。
  Map<String, String> get _results => _ui.results;

  /// 頁面關掉也照寫（同步在背景跑），開著的頁面靠 [_onUiChanged] 重畫。
  void _record(String label, ({int downloaded, int uploaded}) r) {
    _results[label] = '↑${r.uploaded} ↓${r.downloaded}';
    _ui.changed();
  }

  void _onUiChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ui.addListener(_onUiChanged);
    _loadLastSyncedAt();
  }

  @override
  void dispose() {
    _ui.removeListener(_onUiChanged);
    _endpointController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSyncedAt() async {
    final raw = await ref.read(keyValueStoreProvider).read(_lastSyncedKey);
    if (raw != null && mounted) {
      setState(() => _lastSyncedAt = DateTime.tryParse(raw));
    }
  }

  Future<void> _saveAndTestConnection() async {
    final endpoint = _endpointController.text.trim();
    final accessKey = _accessKeyController.text.trim();
    final secretKey = _secretKeyController.text.trim();
    if (endpoint.isEmpty || accessKey.isEmpty || secretKey.isEmpty) return;

    setState(() {
      _phase = _Phase.testing;
      _errorMessage = null;
    });

    final credentials = R2Credentials(
      endpoint: endpoint,
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
    );
    try {
      final client = R2Client(
        credentials: credentials,
        bucket: ref.read(r2BucketNameProvider),
      );
      await R2SyncService(client).testConnection();
      final store = ref.read(keyValueStoreProvider);
      await R2CredentialsStore(store).save(credentials);
      ref.read(r2CredentialsProvider.notifier).state = credentials;
      if (!mounted) return;
      setState(() => _phase = _Phase.success);
      // 成功打勾停留一下再自動切到「已連接」畫面，跟設計稿一致，不要
      // 一測完馬上跳走，使用者才看得到「有成功」這個回饋。
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = '$e';
      });
    }
  }

  Future<void> _clearCredentials() async {
    final store = ref.read(keyValueStoreProvider);
    await R2CredentialsStore(store).clear();
    ref.read(r2CredentialsProvider.notifier).state = null;
    _endpointController.clear();
    _accessKeyController.clear();
    _secretKeyController.clear();
  }

  /// 給單一功能用的 [SyncPhase] → [_FeaturePhase] 轉接，[onUpdate] 是
  /// 對應功能自己的 setState 賦值——日記、健身各自呼叫一次
  /// [R2SyncService] 的 `syncXxx`，用這個共用轉接省得兩邊各寫一份幾乎
  /// 一樣的 callback。
  void Function(SyncPhase) _phaseCallback(
    void Function(_FeaturePhase) onUpdate,
  ) {
    return (phase) {
      onUpdate(switch (phase) {
        SyncPhase.downloading => _FeaturePhase.downloading,
        SyncPhase.uploading => _FeaturePhase.uploading,
      });
      _ui.changed();
    };
  }

  Future<void> _syncNow() async {
    // 同步途中使用者可能已經離開設定頁（2026-10-08 使用者回報：點同步後
    // 跳去別的功能，上方通知沒出來）。頁面一卸載 `ref.read` 就會丟
    // StateError，後半段的同步紀錄、上次同步時間、通知全部跟著斷掉，
    // 所以一開始就抓住 ProviderContainer，整段同步都用它讀。
    final container = ProviderScope.containerOf(context, listen: false);
    final credentials = container.read(r2CredentialsProvider);
    if (credentials == null ||
        _syncing ||
        container.read(r2SyncRunningProvider)) {
      return;
    }
    container.read(r2SyncRunningProvider.notifier).state = true;
    // 即時進度（2026-10-12 使用者要求：同步中跳去別的地方，上方要顯示
    // 跑到哪了），見 [SyncProgressBanner]。
    final progress = container.read(syncProgressProvider.notifier);
    progress.state = const SyncProgress(total: 0, done: 0, running: []);
    setState(() {
      _syncing = true;
      _diaryPhase = _FeaturePhase.downloading;
      _fitnessPhase = _FeaturePhase.downloading;
      _ytPhase = _FeaturePhase.downloading;
      _kanaPracticePhase = _FeaturePhase.downloading;
      _kanaExamPhase = _FeaturePhase.downloading;
      _englishPhase = _FeaturePhase.downloading;
      _appHomePhase = _FeaturePhase.downloading;
      _habitPhases
        ..clear()
        ..addEntries(
          _habitRows.map((r) => MapEntry(r.$1, _FeaturePhase.downloading)),
        );
      _syncLogPhase = _FeaturePhase.idle;
      _errorLogPhase = _FeaturePhase.idle;
      _results.clear();
    });
    // 這次同步整體有沒有出過錯，寫進同步紀錄用；單一功能失敗不會擋住
    // 其他功能（2026-09-29 使用者要求：互不相關的功能要能同時做，不能
    // 因為其中一個掛了就整批放棄，明明其他已經做完的）。
    final details = <String>[];
    final failures = <String>[];
    // 給上方通知用的（2026-10-08 使用者挑「多裝置同步上方通知」第 2 版：
    // 毛玻璃提示改寫成「日記 +2、YT 頻道追蹤 +3」這種摘要）。
    final downloads = <String, int>{};
    final failedLabels = <String>[];

    try {
      final client = R2Client(
        credentials: credentials,
        bucket: container.read(r2BucketNameProvider),
      );
      // 帶本機儲存進去，同步才能記住「上次同步完的內容指紋／雲端 ETag」，
      // 下次兩邊都沒變就整段跳過（2026-09-29 使用者要求加速，見
      // `R2SyncService` 建構子跟 `_canSkip` 的說明）。
      final service = R2SyncService(
        client,
        container.read(keyValueStoreProvider),
      );

      // 單一功能同步的共用包裝：跑完記結果、標記完成；失敗記下來、標記
      // 失敗，不往外丟例外——這樣外層才能用 `Future.wait` 讓每個功能
      // 同時跑，一個失敗不會讓 `Future.wait` 直接中斷、拖累還在跑的
      // 其他功能（2026-09-29 使用者問「怎現在還是線性的」，這裡改成
      // 真的平行：日記、健身、YT、五十音練習/考試、英文紀錄、看盤/
      // 抽菸/喝酒，全部同時打，不用排隊）。
      Future<void> run(
        String label,
        void Function(_FeaturePhase) setPhase,
        Future<({int downloaded, int uploaded})> Function(
          void Function(SyncPhase)?,
        )
        task,
      ) async {
        // 這段在第一個 await 之前，Future.wait 一排開時就全部算進總數。
        final p0 = progress.state;
        if (p0 != null) {
          progress.state = SyncProgress(
            total: p0.total + 1,
            done: p0.done,
            running: [...p0.running, label],
          );
        }
        try {
          final r = await task(_phaseCallback(setPhase));
          _record(label, r);
          details.add('$label 上傳${r.uploaded}／下載${r.downloaded}');
          if (r.downloaded > 0) downloads[label] = r.downloaded;
          setPhase(_FeaturePhase.done);
          _ui.changed();
        } catch (e, stack) {
          AppLog.add('[同步] $label 失敗：$e\n$stack', isError: true);
          failures.add('$label：$e');
          failedLabels.add(label);
          setPhase(_FeaturePhase.error);
          _ui.changed();
        } finally {
          final p = progress.state;
          if (p != null) {
            progress.state = SyncProgress(
              total: p.total,
              done: p.done + 1,
              running: [...p.running]..remove(label),
            );
          }
        }
      }

      await Future.wait([
        run('日記', (p) => _diaryPhase = p, (onPhase) async {
          // 日記密碼（2026-09-29 使用者要求）跟日記內容本來就是同一個
          // 功能範疇內的資料，包進同一個「日記」任務一起跑，不另外開
          // 一個平行任務跟一顆狀態列。
          final entryResult = await service.syncDiary(
            container.read(diaryRepositoryProvider),
            onPhase: onPhase,
          );
          final pwResult = await service.syncDiaryPassword(
            DiaryPasswordStore(container.read(keyValueStoreProvider)),
          );
          return (
            downloaded: entryResult.downloaded + pwResult.downloaded,
            uploaded: entryResult.uploaded + pwResult.uploaded,
          );
        }),
        run(
          '健身',
          (p) => _fitnessPhase = p,
          (onPhase) => service.syncFitness(
            container.read(fitnessRepositoryProvider),
            onPhase: onPhase,
          ),
        ),
        run('YT 頻道追蹤', (p) => _ytPhase = p, (onPhase) async {
          // YT 分類／頻道要先同步完，影片快取才能拿到最新的頻道清單，
          // 這兩步本來就有先後依賴，包成同一個「功能」一起跑，跟其他
          // 互不相關的功能平行，不是說「YT 也要平行」就硬拆開兩步。
          final ytResult = await service.syncYtTracker(
            container.read(ytTrackerRepositoryProvider),
            onPhase: onPhase,
          );
          // 分類／頻道同步完之後，下面這些彼此不相關，同時跑（2026-10-15
          // 使用者要求 YT 同步加速；原本一項等一項）。各自是什麼：
          // - 影片快取：要用剛同步完的頻道清單。
          // - 影片「看過了」記錄（2026-09-29）、分類顯示順序（2026-09-30：
          //   原本只存本機）、頻道紀錄（2026-10-06）、YT 顯示設定（2026-10-12，
          //   別台改過就套用到畫面）、播放清單（2026-10-14）。
          // - 原本只存本機的 YT 設定跟最近搜尋（2026-10-15）：點影片時、
          //   播放器樣式、訂閱人數更新頻率、最近搜尋。
          final kv = container.read(keyValueStoreProvider);
          final channels = await container
              .read(ytTrackerRepositoryProvider)
              .loadChannels();
          final prefsStore = YtDisplayPrefsStore(kv);
          final playlistStore = YtPlaylistStore(kv);
          final openMode = YtVideoOpenModeStore(kv);
          final playerStyle = YtEmbedPlayerStyleStore(kv);
          final statsDays = YtStatsRefreshSettingStore(kv);
          final results = await Future.wait([
            service.syncYtVideoCache(YtVideoCacheStore(kv), channels),
            service.syncYtVideoWatch(YtVideoWatchStore(kv)),
            service.syncYtCategoryOrder(YtCategoryOrderStore(kv)),
            service.syncYtChannelLog(YtChannelLogStore(kv)),
            service.syncYtDisplayPrefs(prefsStore).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytDisplayPrefsProvider.notifier).state =
                    await prefsStore.load();
              }
              return r;
            }),
            // 音樂功能（2026-10-19）跟 YT 一起同步。
            service.syncMusic(MusicStore(kv)).then((r) async {
              if (r.downloaded > 0) {
                container.read(musicDataProvider.notifier).state =
                    await MusicStore(kv).load();
              }
              return r;
            }),
            service.syncYtVideoSongs(YtVideoSongStore(kv)).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytVideoSongsProvider.notifier).state =
                    await YtVideoSongStore(kv).loadIds();
              }
              return r;
            }),
            service.syncYtPlaylists(playlistStore).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytPlaylistsProvider.notifier).state =
                    await playlistStore.loadAll();
              }
              return r;
            }),
            service.syncStampedSetting(openMode.record).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytVideoOpenModeProvider.notifier).state =
                    await openMode.load();
              }
              return r;
            }),
            service.syncStampedSetting(playerStyle.record).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytEmbedPlayerStyleProvider.notifier).state =
                    await playerStyle.load();
              }
              return r;
            }),
            service.syncStampedSetting(statsDays.record).then((r) async {
              if (r.downloaded > 0) {
                container.read(ytStatsRefreshDaysProvider.notifier).state =
                    await statsDays.load();
              }
              return r;
            }),
            service.syncStampedSetting(YtSearchRecentsStore(kv).record),
          ]);
          return (
            downloaded: results.fold<int>(
              ytResult.downloaded,
              (n, r) => n + r.downloaded,
            ),
            uploaded: results.fold<int>(
              ytResult.uploaded,
              (n, r) => n + r.uploaded,
            ),
          );
        }),
        run('五十音練習', (p) => _kanaPracticePhase = p, (onPhase) async {
          final r = await service.syncKanaPractice(
            container.read(kanaPracticeRepositoryProvider),
            onPhase: onPhase,
          );
          // 日文首頁卡片順序（2026-10-05）跟日文練習一起同步，不另開
          // 一個任務跟一顆狀態列。
          final order = await service.syncHomeCardOrder(
            HomeCardOrderStore(container.read(keyValueStoreProvider), 'jp'),
          );
          // 日文首頁進度圈開關（2026-10-15 使用者要求同步）。
          final ringStore = JpHomeRingStore(
            container.read(keyValueStoreProvider),
          );
          final ring = await service.syncStampedSetting(ringStore.record);
          if (ring.downloaded > 0) {
            container.read(jpShowProgressRingProvider.notifier).state =
                await ringStore.load();
          }
          // 櫻花樹畫法（2026-10-16）。
          final lightStore = JpLightStyleStore(
            container.read(keyValueStoreProvider),
          );
          final light = await service.syncStampedSetting(lightStore.record);
          if (light.downloaded > 0) {
            container.read(jpLightStyleProvider.notifier).state =
                await lightStore.load();
          }
          return (
            downloaded:
                r.downloaded +
                order.downloaded +
                ring.downloaded +
                light.downloaded,
            uploaded:
                r.uploaded + order.uploaded + ring.uploaded + light.uploaded,
          );
        }),
        run(
          '五十音考試',
          (p) => _kanaExamPhase = p,
          (onPhase) => service.syncKanaExam(
            container.read(kanaExamRepositoryProvider),
            onPhase: onPhase,
          ),
        ),
        run('英文單字紀錄', (p) => _englishPhase = p, (onPhase) async {
          final r = await service.syncEnglishHistory(
            container.read(historyRepositoryProvider),
            onPhase: onPhase,
          );
          // 單字庫有記憶體快取（對錯次數是從紀錄現算的），紀錄變了要
          // 丟掉重算。
          container.read(wordRepositoryProvider).invalidate();
          // 英文首頁卡片順序（2026-10-05）跟英文紀錄一起同步。
          final order = await service.syncHomeCardOrder(
            HomeCardOrderStore(container.read(keyValueStoreProvider), 'en'),
          );
          return (
            downloaded: r.downloaded + order.downloaded,
            uploaded: r.uploaded + order.uploaded,
          );
        }),
        // App 首頁功能順序（2026-10-06），跟英文／日文卡片順序同一套。
        run('首頁', (p) => _appHomePhase = p, (_) async {
          final order = await service.syncHomeCardOrder(
            HomeCardOrderStore(container.read(keyValueStoreProvider), 'app'),
          );
          // 底部分頁列設定（2026-10-14）是整個 App 的，跟首頁一起同步。
          final navStore = NavBarPrefsStore(
            container.read(keyValueStoreProvider),
          );
          final nav = await service.syncNavBarPrefs(navStore);
          if (nav.downloaded > 0) {
            container.read(navBarPrefsProvider.notifier).state = await navStore
                .load();
          }
          // 首頁樣式（2026-10-15 使用者要求同步）。
          final homeStyle = AppHomeStyleStore(
            container.read(keyValueStoreProvider),
          );
          final style = await service.syncStampedSetting(homeStyle.record);
          if (style.downloaded > 0) {
            container.read(appHomeStyleProvider.notifier).state =
                await homeStyle.load();
          }
          return (
            downloaded: order.downloaded + nav.downloaded + style.downloaded,
            uploaded: order.uploaded + nav.uploaded + style.uploaded,
          );
        }),
        run('交易紀錄', (p) => _habitPhases['trade'] = p, (onPhase) async {
          // 順便刪掉已移除的看盤次數留在雲端的 crypto_watch.json。
          await service.deleteRetiredCloudFiles();
          final trades = await service.syncTrades(
            container.read(tradeRepositoryProvider),
            onPhase: onPhase,
          );
          // USDT 換台幣匯率也算交易的設定，一起同步；別台改過就套用到畫面。
          final rateStore = UsdtTwdRateStore(
            container.read(keyValueStoreProvider),
          );
          final rate = await service.syncUsdtTwdRate(rateStore);
          if (rate.downloaded > 0) {
            container.read(usdtTwdRateProvider.notifier).state = await rateStore
                .load();
          }
          return (
            downloaded: trades.downloaded + rate.downloaded,
            uploaded: trades.uploaded + rate.uploaded,
          );
        }),
        run(
          '抽菸記錄',
          (p) => _habitPhases['smoking'] = p,
          (onPhase) => service.syncSmoking(
            container.read(smokingRepositoryProvider),
            onPhase: onPhase,
          ),
        ),
        run(
          '喝酒記錄',
          (p) => _habitPhases['drinking'] = p,
          (onPhase) => service.syncDrinking(
            container.read(drinkingRepositoryProvider),
            onPhase: onPhase,
          ),
        ),
        run(
          '負債管理',
          (p) => _habitPhases['debt'] = p,
          (onPhase) => service.syncDebts(
            container.read(debtRepositoryProvider),
            onPhase: onPhase,
          ),
        ),
      ]);

      // 同步紀錄本身這筆內容就是「這次同步的結果」，一定要等上面全部
      // 功能都做完（不管成功失敗）才能寫，所以留在 Future.wait 之後、
      // 序列做，不是漏掉平行化。
      final now = DateTime.now();
      await container
          .read(keyValueStoreProvider)
          .write(_lastSyncedKey, now.toIso8601String());
      await container
          .read(syncLogRepositoryProvider)
          .add(
            SyncLogEntry(
              at: now,
              action: SyncLogAction.sync,
              success: failures.isEmpty,
              device: currentDeviceLabel(),
              detail: [
                ...details,
                if (failures.isNotEmpty) '失敗：${failures.join('；')}',
              ].join('；'),
            ),
          );
      try {
        // 除錯日誌先同步、同步紀錄最後才做（2026-09-29 使用者指出：同步
        // 紀錄是這整次同步的「收據」，理論上該排在最後，不該夾在除錯
        // 日誌前面）。除錯日誌本身也可能收到這次同步過程中任何功能失敗
        // 寫進 AppLog 的錯誤（見上面 `run` 的 catch），所以放前面同步剛好
        // 也比較新；同步紀錄墊底才是真的「這次同步全部做完」的最終記錄。
        _errorLogPhase = _FeaturePhase.downloading;
        _ui.changed();
        final errorRepo = container.read(errorLogRepositoryProvider);
        final errorResult = await service.syncErrorLog(errorRepo);
        _record('除錯錯誤日誌', errorResult);
        AppLog.restore(await errorRepo.loadAll());
        _errorLogPhase = _FeaturePhase.done;
        _syncLogPhase = _FeaturePhase.downloading;
        _ui.changed();
        final logResult = await service.syncLog(
          container.read(syncLogRepositoryProvider),
        );
        _record('同步紀錄', logResult);
        _syncLogPhase = _FeaturePhase.done;
        _ui.changed();
      } catch (_) {
        // 紀錄上傳失敗不擋主流程：其他功能已經同步成功。
      }
      if (mounted) widget.onLogged?.call();
      // 同步抓回來的資料要讓日記頁／健身頁（可能還留在導覽堆疊底下沒被
      // 重建）知道要重讀，不然使用者按返回時畫面還是同步前的舊資料
      // （2026-09-23 使用者回報）——跟練習紀錄頁那套「存檔完 bump 這個
      // provider」共用同一個機制，見 `dataRevisionProvider` 的其他用法。
      container.read(dataRevisionProvider.notifier).state++;
      container.read(r2SyncRunningProvider.notifier).state = false;
      progress.state = null;
      _syncing = false;
      _ui.changed();
      if (mounted) setState(() => _lastSyncedAt = now);
      // 不寫是哪台裝置傳的（2026-10-08 使用者：不用分 iPhone／Android，
      // 只要「本裝置從雲端更新了什麼」）。
      // 已經離開同步頁：用整個 App 的 Navigator 底下那層 Overlay 顯示
      // （見 [showAppNotice] 的 overlay 參數說明）。
      final noticeContext = mounted ? context : rootNavigatorKey.currentContext;
      final noticeOverlay = mounted
          ? null
          : rootNavigatorKey.currentState?.overlay;
      if (noticeContext == null ||
          !noticeContext.mounted ||
          (!mounted && noticeOverlay == null)) {
        return;
      }
      if (failedLabels.isEmpty) {
        showAppNotice(
          noticeContext,
          overlay: noticeOverlay,
          downloads.isEmpty
              ? '同步完成，沒有新資料'
              : '本裝置從雲端更新：${_downloadSummary(downloads)}',
        );
      } else {
        showAppNotice(
          noticeContext,
          overlay: noticeOverlay,
          '同步完成，但 ${failedLabels.length} 項失敗：${failedLabels.join('、')}',
          detail: '其他功能已經更新',
          isError: true,
        );
      }
    } catch (e, stack) {
      // 這裡接住的是「不屬於任何單一功能」的意外錯誤（例如建立 R2Client
      // 本身出問題）——各功能自己的失敗已經在 `run` 裡接住了，不會
      // 跑到這裡。
      AppLog.add('[同步] 意外錯誤：$e\n$stack', isError: true);
      await container
          .read(syncLogRepositoryProvider)
          .add(
            SyncLogEntry(
              at: DateTime.now(),
              action: SyncLogAction.sync,
              success: false,
              device: currentDeviceLabel(),
              detail: '意外錯誤：$e',
            ),
          );
      container.read(r2SyncRunningProvider.notifier).state = false;
      progress.state = null;
      _syncing = false;
      _ui.changed();
      if (mounted) widget.onLogged?.call();
      // 已經離開同步頁：用整個 App 的 Navigator 底下那層 Overlay 顯示
      // （見 [showAppNotice] 的 overlay 參數說明）。
      final noticeContext = mounted ? context : rootNavigatorKey.currentContext;
      final noticeOverlay = mounted
          ? null
          : rootNavigatorKey.currentState?.overlay;
      if (noticeContext == null ||
          !noticeContext.mounted ||
          (!mounted && noticeOverlay == null)) {
        return;
      }
      showAppNotice(
        noticeContext,
        '同步失敗：$e',
        isError: true,
        overlay: noticeOverlay,
      );
    }
  }

  /// 「日記 +2、YT 頻道追蹤 +3」：只列這次真的有下載到東西的功能。
  static String _downloadSummary(Map<String, int> downloads) =>
      downloads.entries.map((e) => '${e.key} +${e.value}').join('、');

  @override
  Widget build(BuildContext context) {
    final credentials = ref.watch(r2CredentialsProvider);
    // 在別的頁面發起、還在背景跑的同步跑完了：重讀上次同步時間跟紀錄。
    ref.listen(r2SyncRunningProvider, (was, now) {
      if (was == true && !now) {
        _loadLastSyncedAt();
        widget.onLogged?.call();
      }
    });
    if (credentials == null) {
      return GlassCard(child: _buildInputCard());
    }
    // 「各功能同步狀況」卡片只有連上雲端之後才有意義顯示，跟輸入卡片
    // 分開放（2026-09-23 使用者要求：頁面底下再加一張卡片顯示同步
    // 進度）。
    return Column(
      children: [
        GlassCard(child: _buildConnectedCard(credentials)),
        const SizedBox(height: Gap.sm),
        GlassCard(child: _buildStatusCard()),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '各功能同步狀況',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Gap.sm),
        _FeatureStatusRow(
          label: '日記',
          phase: _diaryPhase,
          result: _results['日記'],
        ),
        _FeatureStatusRow(
          label: '健身',
          phase: _fitnessPhase,
          result: _results['健身'],
        ),
        _FeatureStatusRow(
          label: 'YT 頻道追蹤',
          phase: _ytPhase,
          result: _results['YT 頻道追蹤'],
        ),
        _FeatureStatusRow(
          label: '五十音練習',
          phase: _kanaPracticePhase,
          result: _results['五十音練習'],
        ),
        _FeatureStatusRow(
          label: '五十音考試',
          phase: _kanaExamPhase,
          result: _results['五十音考試'],
        ),
        _FeatureStatusRow(
          label: '英文單字紀錄',
          phase: _englishPhase,
          result: _results['英文單字紀錄'],
        ),
        _FeatureStatusRow(
          label: '首頁',
          phase: _appHomePhase,
          result: _results['首頁'],
        ),
        for (final (id, title) in _habitRows)
          _FeatureStatusRow(
            label: title,
            phase: _habitPhases[id] ?? _FeaturePhase.idle,
            result: _results[title],
          ),
        // 同步紀錄、錯誤日誌本身也是要同步的資料，一樣列出來
        // （2026-09-24 使用者要求）。除錯日誌在前、同步紀錄墊底——同步
        // 紀錄是這次同步的「收據」，順序上該是最後一項（2026-09-29
        // 使用者要求，跟實際同步順序一致，見 `_syncNow` 的說明）。
        _FeatureStatusRow(
          label: '除錯錯誤日誌',
          phase: _errorLogPhase,
          result: _results['除錯錯誤日誌'],
        ),
        _FeatureStatusRow(
          label: '同步紀錄',
          phase: _syncLogPhase,
          result: _results['同步紀錄'],
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(
          label: 'Account ID / S3 API 網址',
          controller: _endpointController,
          hint: 'https://xxxxxxxx.r2.cloudflarestorage.com',
        ),
        _Field(
          label: 'Access Key ID',
          controller: _accessKeyController,
          hint: '貼上 Access Key ID',
        ),
        _Field(
          label: 'Secret Access Key',
          controller: _secretKeyController,
          hint: '貼上 Secret Access Key',
          obscure: true,
          hintNote: '只存在這台裝置的瀏覽器裡，不會進 Git、也不會顯示在畫面上。',
        ),
        const SizedBox(height: Gap.xs),
        _buildActionButton(),
        if (_phase == _Phase.error && _errorMessage != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 10.5, color: AppColors.bad),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton() {
    switch (_phase) {
      case _Phase.testing:
        return _StaticButton(
          color: AppColors.glassFill,
          textColor: AppColors.ink2,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('連線測試中…'),
            ],
          ),
        );
      case _Phase.success:
        return _StaticButton(
          color: AppColors.ok,
          textColor: const Color(0xFF062B16),
          child: const Text('✓ 連線成功'),
        );
      case _Phase.error:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _saveAndTestConnection,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bad,
              side: const BorderSide(color: AppColors.bad),
            ),
            child: const Text('連線失敗，再試一次'),
          ),
        );
      case _Phase.idle:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saveAndTestConnection,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bgDeep,
            ),
            child: const Text('儲存並測試連線'),
          ),
        );
    }
  }

  Widget _buildConnectedCard(R2Credentials credentials) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 8, color: AppColors.ok),
            const SizedBox(width: Gap.xs),
            const Text(
              '已連接雲端',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _clearCredentials,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.bad,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
              ),
              child: const Text('取消連接', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        Text(
          _lastSyncedAt == null
              ? '還沒同步過'
              : '上次同步：${_relativeTime(_lastSyncedAt!)}',
          style: AppText.note,
        ),
        if (!_syncing && ref.watch(r2SyncRunningProvider))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '同步還在背景跑，跑完上方會通知你',
              style: AppText.note.copyWith(color: AppColors.mid),
            ),
          ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _syncing || ref.watch(r2SyncRunningProvider)
                ? null
                : _syncNow,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bgDeep,
            ),
            child: _syncing || ref.watch(r2SyncRunningProvider)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('立即同步'),
          ),
        ),
      ],
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.hintNote,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final String? hintNote;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: AppText.note),
          const SizedBox(height: 4),
          TextField(
            controller: widget.controller,
            obscureText: _obscured,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: widget.obscure
                  ? IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      color: AppColors.ink3,
                    )
                  : null,
            ),
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
          if (widget.hintNote != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.hintNote!,
              style: const TextStyle(
                fontSize: 9.5,
                color: AppColors.ink3,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 同步狀況卡片裡的一行：功能名稱＋目前狀態（閒置／下載中／上傳中／
/// 完成打勾／失敗）。
class _FeatureStatusRow extends StatelessWidget {
  const _FeatureStatusRow({
    required this.label,
    required this.phase,
    this.result,
  });

  final String label;
  final _FeaturePhase phase;

  /// 這次同步的結果（↑上傳 ↓下載筆數），沒有就不顯示。
  final String? result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (result != null && phase == _FeaturePhase.done) ...[
            Text(
              result!,
              style: const TextStyle(fontSize: 11, color: AppColors.ink2),
            ),
            const SizedBox(width: 8),
          ],
          _buildStatus(),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    switch (phase) {
      case _FeaturePhase.idle:
        return const Text(
          '待同步',
          style: TextStyle(fontSize: 11, color: AppColors.ink3),
        );
      case _FeaturePhase.downloading:
        return const _StatusSpinnerLabel(label: '下載中…');
      case _FeaturePhase.uploading:
        return const _StatusSpinnerLabel(label: '上傳中…');
      case _FeaturePhase.done:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: AppColors.ok),
            SizedBox(width: 4),
            Text('完成', style: TextStyle(fontSize: 11, color: AppColors.ok)),
          ],
        );
      case _FeaturePhase.error:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: AppColors.bad),
            SizedBox(width: 4),
            Text('失敗', style: TextStyle(fontSize: 11, color: AppColors.bad)),
          ],
        );
    }
  }
}

class _StatusSpinnerLabel extends StatelessWidget {
  const _StatusSpinnerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.ink2),
        ),
      ],
    );
  }
}

class _StaticButton extends StatelessWidget {
  const _StaticButton({
    required this.color,
    required this.textColor,
    required this.child,
  });

  final Color color;
  final Color textColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
        child: Center(child: child),
      ),
    );
  }
}
