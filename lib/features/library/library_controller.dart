import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/word.dart';
import '../../domain/scoring.dart';

/// 搜尋字串。英文和中文都能搜。
final libraryQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// 狀態篩選。null 代表不篩。
final libraryFilterProvider = StateProvider.autoDispose<WordStatus?>(
  (ref) => null,
);

/// 單字庫畫面要的資料。
class LibraryData {
  const LibraryData({
    required this.words,
    required this.counts,
    required this.confirmRight,
  });

  /// 篩選與搜尋之後的結果。
  final List<Word> words;

  /// 三種狀態各有幾個字。這是全庫的數量，不受搜尋影響，
  /// 不然篩選鈕上的數字會跟著搜尋跳動，很難用。
  final Map<WordStatus, int> counts;

  final int confirmRight;
}

final libraryProvider = FutureProvider.autoDispose<LibraryData>((ref) async {
  final all = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await ref.watch(settingsRepositoryProvider).loadRules();
  final query = ref.watch(libraryQueryProvider).trim();
  final filter = ref.watch(libraryFilterProvider);

  final summary = Scoring.summarize(all, rules.confirmRight);
  final counts = {
    WordStatus.confirmed: summary.confirmed,
    WordStatus.learning: summary.learning,
    WordStatus.pending: summary.pending,
  };

  final lower = query.toLowerCase();
  final filtered = all.where((w) {
    if (filter != null && w.statusWith(rules.confirmRight) != filter) {
      return false;
    }
    if (query.isEmpty) return true;
    return w.word.toLowerCase().contains(lower) || w.zh.contains(query);
  }).toList();

  // 待複習的排前面，那是最需要看的。其餘照原本的編號。
  filtered.sort((a, b) {
    final sa = a.statusWith(rules.confirmRight).index;
    final sb = b.statusWith(rules.confirmRight).index;
    if (sa != sb) return sb.compareTo(sa);
    return a.id.compareTo(b.id);
  });

  return LibraryData(
    words: filtered,
    counts: counts,
    confirmRight: rules.confirmRight,
  );
});
