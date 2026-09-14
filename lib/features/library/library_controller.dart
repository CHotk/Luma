import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../../domain/scoring.dart';
import '../notes/notes_controller.dart';

/// 搜尋字串。英文和中文都能搜。
final libraryQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// 狀態篩選。null 代表不篩。
final libraryFilterProvider = StateProvider.autoDispose<WordStatus?>(
  (ref) => null,
);

/// 類別篩選。null 代表不篩。跟狀態是「且」的關係，兩個可以同時生效。
final libraryTopicProvider = StateProvider.autoDispose<WordTopic?>(
  (ref) => null,
);

/// 單字庫畫面要的資料。
class LibraryData {
  const LibraryData({
    required this.words,
    required this.counts,
    required this.topicCounts,
    required this.traps,
    required this.rules,
  });

  /// 篩選與搜尋之後的結果。
  final List<Word> words;

  /// 三種狀態各有幾個字。這是全庫的數量，不受搜尋影響，
  /// 不然篩選鈕上的數字會跟著搜尋跳動，很難用。
  final Map<WordStatus, int> counts;

  /// 每個類別各有幾個字，給下拉選單顯示。
  final Map<WordTopic, int> topicCounts;

  /// 地雷字對應到第幾則筆記。鍵是小寫的單字。
  final Map<String, String> traps;

  final RulesConfig rules;
}

final libraryProvider = FutureProvider.autoDispose<LibraryData>((ref) async {
  ref.watch(dataRevisionProvider);
  final all = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await ref.watch(settingsRepositoryProvider).loadRules();
  final query = ref.watch(libraryQueryProvider).trim();
  final filter = ref.watch(libraryFilterProvider);
  final topic = ref.watch(libraryTopicProvider);
  final traps = await ref.watch(trapWordsProvider.future);

  final counts = Scoring.countByStatus(all, rules);

  // 有幾個字被分過類，決定要不要顯示類別下拉。
  final topicCounts = <WordTopic, int>{};
  for (final w in all) {
    topicCounts[w.topic] = (topicCounts[w.topic] ?? 0) + 1;
  }

  final lower = query.toLowerCase();
  final filtered = all.where((w) {
    if (filter != null && w.statusWith(rules) != filter) {
      return false;
    }
    // 狀態和類別是「且」的關係：兩個都選就要同時符合。
    if (topic != null && w.topic != topic) return false;
    if (query.isEmpty) return true;
    return w.word.toLowerCase().contains(lower) || w.zh.contains(query);
  }).toList();

  // 待複習的排前面，那是最需要看的。同一種狀態就照原本的編號。
  filtered.sort((a, b) {
    final sa = a.statusWith(rules).priority;
    final sb = b.statusWith(rules).priority;
    if (sa != sb) return sa.compareTo(sb);
    return a.id.compareTo(b.id);
  });

  return LibraryData(
    words: filtered,
    counts: counts,
    topicCounts: topicCounts,
    traps: traps,
    rules: rules,
  );
});
