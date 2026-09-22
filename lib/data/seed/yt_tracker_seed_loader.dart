import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/yt_tracker.dart';

/// 讀 `assets/data/yt_tracker_categories.json` 跟
/// `assets/data/yt_tracker_channels.json`：YT 頻道追蹤的分類／頻道快照，
/// 跟 `diary_seed_loader.dart` 同一個用途——讓在別的裝置／瀏覽器匯出
/// 的分類跟頻道，重新部署後能合併回每個裝置自己的 localStorage。
///
/// 讀不到、格式壞掉都當沒有快照資料，不讓例外往上炸把整個頁面弄壞。
Future<List<YtCategory>> loadYtCategoriesSeed() async {
  try {
    final raw = await rootBundle.loadString(
      'assets/data/yt_tracker_categories.json',
    );
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtCategory.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<List<YtChannel>> loadYtChannelsSeed() async {
  try {
    final raw = await rootBundle.loadString(
      'assets/data/yt_tracker_channels.json',
    );
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtChannel.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}
