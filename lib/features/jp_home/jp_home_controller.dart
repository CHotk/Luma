import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../domain/jp_review_config.dart';
import 'jp_review_state.dart';

/// 日文首頁要顯示的東西，一次算好，畫面只負責排版
/// （跟英文軌道的 [HomeState] 同一個做法）。
class JpHomeState {
  const JpHomeState({
    required this.config,
    required this.todayCount,
    required this.todayMinutes,
    required this.review,
  });

  final JpReviewConfig config;

  /// 今天存了幾筆練習紀錄，首頁進度環的「done」看這個。
  final int todayCount;

  /// 今天練習花的分鐘數，從每筆紀錄的筆畫時間戳加總算出來，不是編的。
  final int todayMinutes;

  final KanaReviewSummary review;
}

/// autoDispose：離開日文首頁就丟掉，回來時重新算，practice 頁自動存檔
/// 之後靠 [dataRevisionProvider] 通知這裡要重算。
final jpHomeStateProvider = FutureProvider.autoDispose<JpHomeState>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final config = await loadJpReviewConfig();
  final entries = await ref.watch(kanaPracticeRepositoryProvider).loadAll();
  final now = DateTime.now();

  final today = entries.where(
    (e) =>
        e.savedAt.year == now.year &&
        e.savedAt.month == now.month &&
        e.savedAt.day == now.day,
  );

  // 每筆紀錄自己的練習時間＝那筆筆畫時間軸最後一個時間戳（見
  // KanaPracticeEntry.strokes 的說明：時間軸從那一筆的第一次落筆算起，
  // 換字／存檔就會歸零重算），今天花的總分鐘數是今天所有紀錄加總，
  // 不是找最大值。匯入的舊圖片沒有筆畫資料，貢獻 0，不會假裝有練習
  // 時間。
  var todayMs = 0.0;
  for (final e in today) {
    var entryMs = 0.0;
    for (final stroke in e.strokes) {
      if (stroke.isEmpty) continue;
      final last = stroke.last.$3;
      if (last > entryMs) entryMs = last;
    }
    todayMs += entryMs;
  }

  final progress = buildKanaProgress(entries);
  final review = summarizeKanaReview(progress, config, now: now);

  return JpHomeState(
    config: config,
    todayCount: today.length,
    todayMinutes: todayMs ~/ 60000,
    review: review,
  );
});
