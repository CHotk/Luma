import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/diary_entry.dart';
import '../../domain/models/fitness.dart';
import '../repositories/diary_repository.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../domain/models/yt_tracker.dart';
import '../repositories/yt_tracker_repository.dart';
import '../repositories/yt_video_cache_store.dart';
import '../services/youtube_api_service.dart';
import '../../shared/debug/app_log.dart';
import '../repositories/error_log_repository.dart';
import '../../domain/models/kana_exam.dart';
import '../../domain/models/kana_practice.dart';
import '../../domain/models/history.dart';
import '../repositories/fitness_repository.dart';
import '../repositories/history_repository.dart';
import '../repositories/kana_exam_repository.dart';
import '../repositories/kana_practice_repository.dart';
import '../repositories/sync_log_repository.dart';
import 'r2_client.dart';

/// 「立即同步」跑到哪一步了，給畫面顯示用（見 `r2_sync_section.dart`
/// 的同步狀況卡）——不分功能共用同一組狀態，日記、健身都用得到。
enum SyncPhase { downloading, uploading }

/// 多裝置同步。第二階段（2026-09-23）：下載＋上傳都做了，刪除用墓碑
/// 標記（tombstone，見 [DiaryEntry.deletedAt] 的說明）不是物理刪除，
/// 避免刪掉的紀錄被下一次同步復活。日記做完之後健身也照這套模式加上
/// 去了（model 加 `deletedAt`／`updatedAt`、repository 加
/// `loadAllIncludingDeleted`、刪除改標記，見 `FitnessRepository` 的
/// 說明）——之後每加一個功能的同步，就在這個 class 上加一組對應的
/// `syncXxx`，不要另外開新檔案，同步邏輯要集中在一個地方找得到。
class R2SyncService {
  R2SyncService(this._client);

  final R2Client _client;

  /// 「測試連線」按下去實際做的事：R2 沒有專門的測試 API（見
  /// `r2_client.dart` 的 [R2Client] 說明），組合兩個真實請求：
  /// 1. `headBucket`：確認金鑰能讀、bucket 存在。
  /// 2. 寫一個小測試檔再馬上刪掉：確認寫入權限也沒問題——只驗證讀
  ///    的話，等真的同步時才會發現寫入權限設定錯了，不如現在先抓出來。
  Future<void> testConnection() async {
    await _client.headBucket();
    const testKey = '_lume_sync_test.json';
    final marker = utf8.encode(
      jsonEncode({'testedAt': DateTime.now().toIso8601String()}),
    );
    await _client.putObject(testKey, Uint8List.fromList(marker));
    await _client.deleteObject(testKey);
  }

  /// 把 R2 上的 `diary.json` 抓下來解析成 entry 清單，還沒併回本機
  /// ——[syncDiary] 要在上傳前也拿這份「雲端原本長怎樣」來跟上傳內容
  /// 比對，算出上傳異動了幾筆，所以抓資料跟合併分成兩步。雲端還沒有
  /// 這個檔案（第一次用）就回傳空清單，不算錯誤。
  Future<List<DiaryEntry>> _fetchCloudDiary() async {
    final bytes = await _client.getObject('diary.json');
    if (bytes == null) return const [];
    final decoded = jsonDecode(utf8.decode(bytes)) as List;
    return decoded.cast<Map<String, dynamic>>().map(DiaryEntry.fromJson).toList();
  }

  /// 「立即同步」按下去做的事：先下載合併，再上傳——順序很重要，
  /// 上傳前一定要先把雲端可能有的新資料併進本機，不然直接上傳會把
  /// 雲端才有、本機還沒同步到的東西覆蓋掉。
  ///
  /// 回傳下載、上傳兩邊「各自」的異動筆數（新增／被刪除／內容有變，
  /// 各算一筆），不是同一個數字——原本只回傳下載那邊的異動數，上傳
  /// 明明可能把好幾筆本地新增／編輯／刪除送上雲端，畫面卻顯示
  /// 「異動 0 筆」，不精確（2026-09-23 使用者要求分開算）。上傳異動數
  /// 是拿上傳前抓下來的雲端快照，跟即將上傳的本機內容比（[diaryDiffCount]
  /// ，跟下載那邊用同一套比對邏輯）——這樣才只算「本地這邊造成的
  /// 差異」，不會把剛從雲端合併進來、本來就沒變的部分也算進去。
  ///
  /// [onPhase] 選填，跑到下載／上傳那一步就會呼叫一次，給畫面顯示
  /// 「目前在下載還是上傳」用（見 `r2_sync_section.dart` 的同步狀況卡）。
  Future<({int downloaded, int uploaded})> syncDiary(
    DiaryRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) async {
    onPhase?.call(SyncPhase.downloading);
    final cloudBefore = await _fetchCloudDiary();
    final downloaded = cloudBefore.isEmpty
        ? 0
        : await repo.mergeFromCloud(cloudBefore);

    onPhase?.call(SyncPhase.uploading);
    final all = await repo.allForUpload();
    final uploaded = diaryDiffCount(cloudBefore, all);
    final bytes = utf8.encode(jsonEncode([for (final e in all) e.toJson()]));
    await _client.putObject('diary.json', Uint8List.fromList(bytes));

    return (downloaded: downloaded, uploaded: uploaded);
  }

  /// 跟 [_fetchCloudDiary] 同一個用途，換成健身的 `fitness.json`。
  Future<List<FitnessEntry>> _fetchCloudFitness() async {
    final bytes = await _client.getObject('fitness.json');
    if (bytes == null) return const [];
    final decoded = jsonDecode(utf8.decode(bytes)) as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(FitnessEntry.fromJson)
        .toList();
  }

  /// 健身版的 [syncDiary]，邏輯完全對應（下載合併→上傳覆蓋、上傳／
  /// 下載異動筆數分開算、同一組 [SyncPhase] 回報進度），只是換成健身
  /// 的 model／repository／R2 物件 key（`fitness.json`，跟日記的
  /// `diary.json` 分開存，一個功能一個檔案，不要塞在同一份 JSON 裡）。
  Future<({int downloaded, int uploaded})> syncFitness(
    FitnessRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) async {
    onPhase?.call(SyncPhase.downloading);
    final cloudBefore = await _fetchCloudFitness();
    final downloaded = cloudBefore.isEmpty
        ? 0
        : await repo.mergeFromCloud(cloudBefore);

    onPhase?.call(SyncPhase.uploading);
    final all = await repo.allForUpload();
    final uploaded = fitnessDiffCount(cloudBefore, all);
    final bytes = utf8.encode(jsonEncode([for (final e in all) e.toJson()]));
    await _client.putObject('fitness.json', Uint8List.fromList(bytes));

    return (downloaded: downloaded, uploaded: uploaded);
  }

  Future<List<YtCategory>> _fetchCloudYtCategories() async {
    final bytes = await _client.getObject('yt_categories.json');
    if (bytes == null) return const [];
    return (jsonDecode(utf8.decode(bytes)) as List)
        .cast<Map<String, dynamic>>()
        .map(YtCategory.fromJson)
        .toList();
  }

  Future<List<YtChannel>> _fetchCloudYtChannels() async {
    final bytes = await _client.getObject('yt_channels.json');
    if (bytes == null) return const [];
    return (jsonDecode(utf8.decode(bytes)) as List)
        .cast<Map<String, dynamic>>()
        .map(YtChannel.fromJson)
        .toList();
  }

  /// YT 頻道追蹤版的 [syncDiary]：分類跟頻道各一個 R2 檔
  /// （`yt_categories.json`／`yt_channels.json`），下載合併→上傳覆蓋，
  /// 回傳的筆數是分類＋頻道加總。
  Future<({int downloaded, int uploaded})> syncYtTracker(
    YtTrackerRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) async {
    onPhase?.call(SyncPhase.downloading);
    final cloudCategories = await _fetchCloudYtCategories();
    final cloudChannels = await _fetchCloudYtChannels();
    final downloaded =
        await repo.mergeCategoriesFromCloud(cloudCategories) +
        await repo.mergeChannelsFromCloud(cloudChannels);

    onPhase?.call(SyncPhase.uploading);
    final categories = await repo.categoriesForUpload();
    final channels = await repo.channelsForUpload();
    final uploaded =
        ytDiffCount(
          [for (final c in cloudCategories) c.toJson()],
          [for (final c in categories) c.toJson()],
        ) +
        ytDiffCount(
          [for (final c in cloudChannels) c.toJson()],
          [for (final c in channels) c.toJson()],
        );
    await _client.putObject(
      'yt_categories.json',
      Uint8List.fromList(
        utf8.encode(jsonEncode([for (final c in categories) c.toJson()])),
      ),
    );
    await _client.putObject(
      'yt_channels.json',
      Uint8List.fromList(
        utf8.encode(jsonEncode([for (final c in channels) c.toJson()])),
      ),
    );
    return (downloaded: downloaded, uploaded: uploaded);
  }

  /// YT 上傳頻率圖用的歷史影片快取也同步（2026-09-24 使用者要求：資料
  /// 都該可同步）。一個頻道一個 R2 檔（`yt_video_cache/<頻道id>.json`，
  /// 內容 `{fetchedAt, videos}`），不塞成一份大檔，每次只動有變的頻道。
  /// 下載聯集合併→本機比雲端多東西才上傳。回傳影片部數（不是頻道數）。
  Future<({int downloaded, int uploaded})> syncYtVideoCache(
    YtVideoCacheStore cache,
    List<YtChannel> channels,
  ) async {
    var downloaded = 0;
    var uploaded = 0;
    for (final channel in channels) {
      final key = 'yt_video_cache/${channel.id}.json';
      final bytes = await _client.getObject(key);
      var cloudVideos = <YoutubeVideo>[];
      DateTime? cloudAt;
      if (bytes != null) {
        final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        cloudAt = DateTime.tryParse(decoded['fetchedAt'] as String? ?? '');
        cloudVideos = (decoded['videos'] as List)
            .cast<Map<String, dynamic>>()
            .map(YoutubeVideo.fromJson)
            .toList();
        downloaded += await cache.mergeFromCloud(channel.id, cloudVideos, cloudAt);
      }

      final local = await cache.load(channel.id);
      if (local.isEmpty) continue;
      final localAt = await cache.lastFetchedAt(channel.id);
      final cloudById = {for (final v in cloudVideos) v.videoId: v};
      final diff = [
        for (final v in local)
          if (cloudById[v.videoId] == null ||
              (cloudById[v.videoId]!.duration == null && v.duration != null))
            v,
      ];
      final needsUpload = bytes == null || diff.isNotEmpty || localAt != cloudAt;
      if (!needsUpload) continue;
      uploaded += diff.length;
      final body = utf8.encode(
        jsonEncode({
          'fetchedAt': localAt?.toIso8601String(),
          'videos': [for (final v in local) v.toJson()],
        }),
      );
      await _client.putObject(key, Uint8List.fromList(body));
    }
    return (downloaded: downloaded, uploaded: uploaded);
  }

  /// 「下載合併→上傳覆蓋」的通用做法，給五十音練習／考試共用（日記、
  /// 健身、YT 是先寫的，各有自己一份幾乎一樣的邏輯，沒動它們）。
  Future<({int downloaded, int uploaded})> _syncRecords<T>({
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required Future<int> Function(List<T>) mergeFromCloud,
    required Future<List<T>> Function() allForUpload,
    void Function(SyncPhase phase)? onPhase,
  }) async {
    onPhase?.call(SyncPhase.downloading);
    final bytes = await _client.getObject(key);
    final cloudBefore = bytes == null
        ? <T>[]
        : (jsonDecode(utf8.decode(bytes)) as List)
              .cast<Map<String, dynamic>>()
              .map(fromJson)
              .toList();
    final downloaded = cloudBefore.isEmpty
        ? 0
        : await mergeFromCloud(cloudBefore);

    onPhase?.call(SyncPhase.uploading);
    final all = await allForUpload();
    final uploaded = ytDiffCount(
      [for (final e in cloudBefore) toJson(e)],
      [for (final e in all) toJson(e)],
    );
    final body = utf8.encode(jsonEncode([for (final e in all) toJson(e)]));
    await _client.putObject(key, Uint8List.fromList(body));
    return (downloaded: downloaded, uploaded: uploaded);
  }

  /// 英文單字作答紀錄（2026-09-24）。作答紀錄只增不改，所以不需要墓碑，
  /// 合併是聯集（見 [HistoryRepository.mergeFromCloud]）；每輪摘要一起放
  /// 在同一個檔案 `english_history.json`（`{entries, rounds}`）。單字本身
  /// 的資料是打包進 App 的，沒有使用者編輯，不用同步；對錯次數從紀錄現算。
  Future<({int downloaded, int uploaded})> syncEnglishHistory(
    HistoryRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) async {
    onPhase?.call(SyncPhase.downloading);
    final bytes = await _client.getObject('english_history.json');
    var cloudEntries = <HistoryEntry>[];
    var cloudRounds = <RoundLog>[];
    if (bytes != null) {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      cloudEntries = (decoded['entries'] as List)
          .cast<Map<String, dynamic>>()
          .map(HistoryEntry.fromJson)
          .toList();
      cloudRounds = (decoded['rounds'] as List)
          .cast<Map<String, dynamic>>()
          .map(RoundLog.fromJson)
          .toList();
    }
    final downloaded = bytes == null
        ? 0
        : await repo.mergeFromCloud(cloudEntries, cloudRounds);

    onPhase?.call(SyncPhase.uploading);
    final all = await repo.allForUpload();
    final cloudPrints = {
      for (final e in cloudEntries) HistoryRepository.fingerprint(e),
    };
    final cloudRoundsByAt = {for (final r in cloudRounds) r.at: r};
    final uploaded =
        all.entries
            .where((e) => !cloudPrints.contains(HistoryRepository.fingerprint(e)))
            .length +
        all.rounds.where((r) {
          final c = cloudRoundsByAt[r.at];
          return c == null || c.seconds != r.seconds || c.total != r.total;
        }).length;
    final body = utf8.encode(
      jsonEncode({
        'entries': [for (final e in all.entries) e.toJson()],
        'rounds': [for (final r in all.rounds) r.toJson()],
      }),
    );
    await _client.putObject('english_history.json', Uint8List.fromList(body));
    return (downloaded: downloaded, uploaded: uploaded);
  }

  /// 五十音手寫練習紀錄（`kana_practice.json`）。
  Future<({int downloaded, int uploaded})> syncKanaPractice(
    KanaPracticeRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) => _syncRecords<KanaPracticeEntry>(
    key: 'kana_practice.json',
    fromJson: KanaPracticeEntry.fromJson,
    toJson: (e) => e.toJson(),
    mergeFromCloud: repo.mergeFromCloud,
    allForUpload: repo.allForUpload,
    onPhase: onPhase,
  );

  /// 五十音／詞彙考試紀錄（`kana_exam.json`）。
  Future<({int downloaded, int uploaded})> syncKanaExam(
    KanaExamRepository repo, {
    void Function(SyncPhase phase)? onPhase,
  }) => _syncRecords<KanaExamEntry>(
    key: 'kana_exam.json',
    fromJson: KanaExamEntry.fromJson,
    toJson: (e) => e.toJson(),
    mergeFromCloud: repo.mergeFromCloud,
    allForUpload: repo.allForUpload,
    onPhase: onPhase,
  );

  Future<List<Object?>> _fetchCloudRaw(String key) async {
    final bytes = await _client.getObject(key);
    if (bytes == null) return const [];
    return (jsonDecode(utf8.decode(bytes)) as List).cast<Object?>();
  }

  Future<List<SyncLogEntry>> _fetchCloudLog() async {
    final bytes = await _client.getObject('sync_log.json');
    if (bytes == null) return const [];
    final decoded = jsonDecode(utf8.decode(bytes)) as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(SyncLogEntry.fromJson)
        .toList();
  }

  /// 同步紀錄本身也要同步（2026-09-24 使用者要求）：下載聯集合併→
  /// 把合併後的完整紀錄上傳覆蓋。log 只增不刪，所以不會有覆蓋掉別台
  /// 資料的問題。呼叫端要在寫完「這次同步」那筆紀錄之後才呼叫，這樣
  /// 這筆也會一起上傳。回傳從雲端新併進來幾筆。
  Future<int> syncLog(SyncLogRepository repo) async {
    final cloud = await _fetchCloudLog();
    final downloaded = cloud.isEmpty ? 0 : await repo.mergeFromCloud(cloud);
    final all = await repo.loadAll();
    final bytes = utf8.encode(jsonEncode([for (final e in all) e.toJson()]));
    await _client.putObject('sync_log.json', Uint8List.fromList(bytes));
    return downloaded;
  }

  Future<List<AppLogEntry>> _fetchCloudErrorLog() async {
    final bytes = await _client.getObject('error_log.json');
    if (bytes == null) return const [];
    final decoded = jsonDecode(utf8.decode(bytes)) as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(AppLogEntry.fromJson)
        .toList();
  }

  /// 除錯頁的錯誤日誌也同步（2026-09-24 使用者要求），做法跟 [syncLog]
  /// 一樣：只增不刪，下載聯集合併→上傳完整內容。回傳從雲端新併進來
  /// 幾筆；呼叫端要接著用 [AppLog.restore] 把合併結果放回畫面。
  Future<int> syncErrorLog(ErrorLogRepository repo) async {
    final cloud = await _fetchCloudErrorLog();
    final downloaded = cloud.isEmpty ? 0 : await repo.mergeFromCloud(cloud);
    final all = await repo.loadAll();
    final bytes = utf8.encode(jsonEncode([for (final e in all) e.toJson()]));
    await _client.putObject('error_log.json', Uint8List.fromList(bytes));
    return downloaded;
  }

  /// 「備份雲端資料」按鈕用：把 R2 上目前每個功能的資料整包抓下來，
  /// 包成一份 JSON 給使用者下載存到本機——跟 [syncDiary]／[syncFitness]
  /// 不一樣，這裡純讀，不合併也不寫回任何 repository／localStorage
  /// （2026-09-24 使用者要求：想要一顆按鈕直接把雲端資料整包抓下來
  /// 方便自己另外備份）。之後同步的功能增加，這裡也要跟著多一個欄位。
  /// 順便回傳各功能筆數，給呼叫端寫進同步紀錄 log 用
  /// （見 `sync_page.dart` 的 `_downloadBackup`）。
  Future<({String json, int diaryCount, int fitnessCount, int ytCount})>
  fetchBackupJson() async {
    final diary = await _fetchCloudDiary();
    final fitness = await _fetchCloudFitness();
    final ytCategories = await _fetchCloudYtCategories();
    final ytChannels = await _fetchCloudYtChannels();
    final kanaPractice = await _fetchCloudRaw('kana_practice.json');
    final kanaExam = await _fetchCloudRaw('kana_exam.json');
    final englishHistoryBytes = await _client.getObject('english_history.json');
    final englishHistory = englishHistoryBytes == null
        ? null
        : jsonDecode(utf8.decode(englishHistoryBytes));
    final log = await _fetchCloudLog();
    final errorLog = await _fetchCloudErrorLog();
    // 影片快取一個頻道一個檔，跟頻道清單對著逐一抓。
    final ytVideoCache = <String, Object?>{};
    for (final c in ytChannels.where((c) => c.deletedAt == null)) {
      final bytes = await _client.getObject('yt_video_cache/${c.id}.json');
      if (bytes != null) ytVideoCache[c.id] = jsonDecode(utf8.decode(bytes));
    }
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert({
      'exportedAt': DateTime.now().toIso8601String(),
      'diary': [for (final e in diary) e.toJson()],
      'fitness': [for (final e in fitness) e.toJson()],
      'ytCategories': [for (final e in ytCategories) e.toJson()],
      'ytChannels': [for (final e in ytChannels) e.toJson()],
      'ytVideoCache': ytVideoCache,
      'kanaPractice': kanaPractice,
      'kanaExam': kanaExam,
      'englishHistory': englishHistory,
      'syncLog': [for (final e in log) e.toJson()],
      'errorLog': [for (final e in errorLog) e.toJson()],
    });
    return (
      json: json,
      diaryCount: diary.length,
      fitnessCount: fitness.length,
      ytCount: ytChannels.where((c) => c.deletedAt == null).length,
    );
  }
}
