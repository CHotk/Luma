import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// 日文首頁要顯示的東西。目前這個軌道只有五十音手寫練習，統計也只
/// 算得出跟這個功能有關的數字——不要在這裡塞進英文軌道那種輪數／
/// 分鐘目標，那套規則（[RulesConfig]）是英文軌道自己的，日文還沒有
/// 對應的東西，硬套會是假資料。
class JpHomeState {
  const JpHomeState({required this.totalEntries, required this.todayEntries});

  final int totalEntries;
  final int todayEntries;
}

/// autoDispose：離開這頁就丟掉，回來時重新算。額外 watch
/// `dataRevisionProvider`——這頁可能一直活在 `/kana-practice` 底下
/// 沒被銷毀（push 疊上去、還沒 pop），autoDispose 救不到這個情境，
/// 靠這個號碼在存檔之後手動觸發重算（見
/// `kana_practice_page.dart` 的 `_autoSave`）。
final jpHomeStateProvider = FutureProvider.autoDispose<JpHomeState>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final entries = await ref.watch(kanaPracticeRepositoryProvider).loadAll();
  final now = DateTime.now();
  final today = entries
      .where(
        (e) =>
            e.savedAt.year == now.year &&
            e.savedAt.month == now.month &&
            e.savedAt.day == now.day,
      )
      .length;
  return JpHomeState(totalEntries: entries.length, todayEntries: today);
});
