import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/daily_limit.dart';
import '../../domain/rules_config.dart';
import '../../domain/scoring.dart';

/// 首頁要顯示的東西，一次算好，畫面只負責排版。
class HomeState {
  const HomeState({
    required this.rules,
    required this.usage,
    required this.total,
    required this.confirmed,
    required this.pending,
  });

  final RulesConfig rules;
  final DailyUsage usage;
  final int total;
  final int confirmed;
  final int pending;

  bool get limitReached => DailyLimit.reached(usage, rules);
  int get roundsLeft => DailyLimit.roundsLeft(usage, rules);
}

/// autoDispose：離開首頁就丟掉，回來時重新算，
/// 這樣做完一輪回來數字一定是新的，不用手動通知。
final homeStateProvider = FutureProvider.autoDispose<HomeState>((ref) async {
  // 有寫入就重算，不然回到首頁看到的還是上一輪之前的數字。
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final settings = ref.watch(settingsRepositoryProvider);
  final words = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await settings.loadRules();
  final usage = await settings.loadUsage(now);
  final summary = Scoring.summarize(words, rules.confirmRight);

  return HomeState(
    rules: rules,
    usage: usage,
    total: summary.total,
    confirmed: summary.confirmed,
    pending: summary.pending,
  );
});
