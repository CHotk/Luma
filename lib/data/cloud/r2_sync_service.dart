import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/diary_entry.dart';
import '../../domain/models/fitness.dart';
import '../repositories/diary_repository.dart';
import '../repositories/fitness_repository.dart';
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

  /// 「備份雲端資料」按鈕用：把 R2 上目前每個功能的資料整包抓下來，
  /// 包成一份 JSON 給使用者下載存到本機——跟 [syncDiary]／[syncFitness]
  /// 不一樣，這裡純讀，不合併也不寫回任何 repository／localStorage
  /// （2026-09-24 使用者要求：想要一顆按鈕直接把雲端資料整包抓下來
  /// 方便自己另外備份）。之後同步的功能增加，這裡也要跟著多一個欄位。
  /// 順便回傳各功能筆數，給呼叫端寫進同步紀錄 log 用
  /// （見 `sync_page.dart` 的 `_downloadBackup`）。
  Future<({String json, int diaryCount, int fitnessCount})>
  fetchBackupJson() async {
    final diary = await _fetchCloudDiary();
    final fitness = await _fetchCloudFitness();
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert({
      'exportedAt': DateTime.now().toIso8601String(),
      'diary': [for (final e in diary) e.toJson()],
      'fitness': [for (final e in fitness) e.toJson()],
    });
    return (json: json, diaryCount: diary.length, fitnessCount: fitness.length);
  }
}
