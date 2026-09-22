import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/diary_entry.dart';

/// 讀 `assets/data/diary.json`：日記快照，跟 `kana_practice_seed_loader.dart`
/// 同一個用途——讓在別的裝置／瀏覽器匯出的日記，重新部署後能合併回
/// 每個裝置自己的 localStorage。
///
/// 使用者還沒把匯出的檔案放進去、或者内容還是空陣列，都算正常——讀
/// 不到、格式壞掉就當沒有快照資料，不讓例外往上炸把整個日記頁弄壞。
Future<List<DiaryEntry>> loadDiarySeed() async {
  try {
    final raw = await rootBundle.loadString('assets/data/diary.json');
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(DiaryEntry.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}
