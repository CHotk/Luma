import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/diary_entry.dart';
import '../repositories/diary_repository.dart';
import 'r2_client.dart';

/// 多裝置同步的第一階段（打地基）：只做「測試連線」跟「日記下載」，
/// 還沒有上傳——先把連線／簽章／資料格式這些地基在風險較低的讀取
/// 路徑上驗證過，再加上傳（2026-09-23 使用者決定）。之後每加一個
/// 功能的同步，就在這個 class 上加一個對應的 `pullXxx` 方法，不要
/// 另外開新檔案，同步邏輯要集中在一個地方找得到。
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

  /// 把 R2 上的 `diary.json` 抓下來，跟本機合併（本機資料贏，見
  /// [DiaryRepository.mergeFromCloud] 的說明）。回傳合併後本機共有
  /// 幾篇日記，給畫面顯示用。
  Future<int> pullDiary(DiaryRepository repo) async {
    final bytes = await _client.getObject('diary.json');
    if (bytes != null) {
      final decoded = jsonDecode(utf8.decode(bytes)) as List;
      final incoming = decoded
          .cast<Map<String, dynamic>>()
          .map(DiaryEntry.fromJson)
          .toList();
      await repo.mergeFromCloud(incoming);
    }
    // 雲端還沒有這個檔案（第一次用、或還沒手動上傳過）就當沒有資料
    // 可以合併，不算錯誤，直接回報目前本機有幾篇。
    return (await repo.loadAll()).length;
  }
}
