import 'dart:convert';

import '../storage/key_value_store.dart';

/// 日記密碼設定值（2026-09-29 使用者要求：日記要加密碼鎖，預設寫死
/// `15975311`——使用者原話「反正寫死的我也不怕忘記密碼」——日記內的
/// 設定頁能自己改，改掉的密碼也要能跨裝置同步，見
/// `R2SyncService.syncDiaryPassword`）。
///
/// 只存一筆 `{password, updatedAt}`，不是清單型紀錄，多裝置同步靠比較
/// `updatedAt` 決定哪邊蓋過哪邊（跟其他紀錄類資料的「聯集合併」是不同
/// 套路——密碼只有一份，沒有「兩邊都保留」這回事）。
class DiaryPasswordRecord {
  const DiaryPasswordRecord({required this.password, required this.updatedAt});

  final String password;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'password': password,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DiaryPasswordRecord.fromJson(Map<String, dynamic> json) =>
      DiaryPasswordRecord(
        password: json['password'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class DiaryPasswordStore {
  DiaryPasswordStore(this._store);

  final KeyValueStore _store;

  static const _key = 'diary.password.v1';

  /// 沒改過密碼時的預設值。
  static const defaultPassword = '15975311';

  Future<String> loadPassword() async => (await loadRecord()).password;

  /// 沒存過（從沒改過密碼）就回傳一筆時間戳定在最早的預設記錄——這樣
  /// 任何一台裝置只要真的改過密碼（`updatedAt` 一定比它新），同步時都會
  /// 蓋過這個從沒改過的預設值，不用另外判斷「有沒有設定過」。
  Future<DiaryPasswordRecord> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw == null) {
      return DiaryPasswordRecord(
        password: defaultPassword,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return DiaryPasswordRecord.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> savePassword(String password) => saveRecord(
    DiaryPasswordRecord(password: password, updatedAt: DateTime.now()),
  );

  Future<void> saveRecord(DiaryPasswordRecord record) =>
      _store.write(_key, jsonEncode(record.toJson()));
}
