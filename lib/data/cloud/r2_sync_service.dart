import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/diary_entry.dart';
import '../repositories/diary_repository.dart';
import 'r2_client.dart';

/// 多裝置同步。第二階段（2026-09-23）：下載＋上傳都做了，刪除用墓碑
/// 標記（tombstone，見 [DiaryEntry.deletedAt] 的說明）不是物理刪除，
/// 避免刪掉的紀錄被下一次同步復活。之後每加一個功能的同步，就在這個
/// class 上加一組對應的 `pullXxx`／`pushXxx`／`syncXxx`，不要另外開
/// 新檔案，同步邏輯要集中在一個地方找得到，其他功能要照日記這套模式
/// （model 加 `deletedAt`、repository 加 `loadAllIncludingDeleted`、
/// 刪除改標記）照樣做一次，見 `DiaryRepository` 的說明。
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

  /// 把 R2 上的 `diary.json` 抓下來，跟本機合併（本機資料贏，墓碑
  /// 標記優先，見 [DiaryRepository.mergeFromCloud] 的說明）。回傳這次
  /// 合併「異動」了幾筆（新增／被刪除／內容有變，各算一筆），不是
  /// 合併後的總筆數——使用者要看到的是這次同步做了什麼
  /// （2026-09-23 使用者要求）。
  Future<int> pullDiary(DiaryRepository repo) async {
    final bytes = await _client.getObject('diary.json');
    // 雲端還沒有這個檔案（第一次用）就當沒有資料可以合併，不算錯誤。
    if (bytes == null) return 0;
    final decoded = jsonDecode(utf8.decode(bytes)) as List;
    final incoming = decoded
        .cast<Map<String, dynamic>>()
        .map(DiaryEntry.fromJson)
        .toList();
    return repo.mergeFromCloud(incoming);
  }

  /// 把本機現況（含刪除標記）整包覆蓋寫回 R2——不是合併，單純用本機
  /// 蓋掉雲端那份。之所以能這樣做而不怕弄丟資料：[syncDiary] 一定會
  /// 先 [pullDiary] 把雲端有、本機沒有的合併進本機，再上傳，所以上傳
  /// 當下的本機狀態已經包含了雲端原本的東西，直接覆蓋不會丟資料
  /// ——除非兩台裝置在下載完、上傳前這段空檔各自又新增了東西，那種
  /// 罕見的競速情況目前沒有處理，個人一兩台裝置手動按同步的使用情境
  /// 機率很低，先不處理。
  Future<void> pushDiary(DiaryRepository repo) async {
    final all = await repo.allForUpload();
    final bytes = utf8.encode(jsonEncode([for (final e in all) e.toJson()]));
    await _client.putObject('diary.json', Uint8List.fromList(bytes));
  }

  /// 「立即同步」按下去做的事：先下載合併，再上傳——順序很重要，
  /// 上傳前一定要先把雲端可能有的新資料併進本機，不然直接上傳會把
  /// 雲端才有、本機還沒同步到的東西覆蓋掉。回傳下載那步的異動筆數
  /// 給畫面顯示。
  Future<int> syncDiary(DiaryRepository repo) async {
    final changed = await pullDiary(repo);
    await pushDiary(repo);
    return changed;
  }
}
