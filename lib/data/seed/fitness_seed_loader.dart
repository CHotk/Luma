import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/fitness.dart';

/// 讀 `assets/data/fitness_entries.json`：健身打卡的快照，跟
/// `diary_seed_loader.dart`／`yt_tracker_seed_loader.dart` 同一個用途
/// ——讓在別的裝置／瀏覽器打的卡，重新部署後能合併回每個裝置自己的
/// localStorage。讀不到、格式壞掉都當沒有快照資料，不讓例外往上炸把
/// 整個頁面弄壞。
Future<List<FitnessEntry>> loadFitnessSeed() async {
  try {
    final raw = await rootBundle.loadString('assets/data/fitness_entries.json');
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(FitnessEntry.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}
