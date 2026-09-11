import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/settings_repository.dart';
import '../data/repositories/word_repository.dart';
import '../data/storage/key_value_store.dart';
import '../domain/models/quiz.dart';

/// 全 App 共用的東西只有這幾個：儲存、兩個 repository、時間來源。
/// 其餘狀態一律放各自 feature 的資料夾，不要往這裡塞。

/// 儲存後端。在 main() 用 overrideWithValue 注入，
/// 因為 SharedPreferences 要非同步開啟，不適合在 provider 裡等。
final keyValueStoreProvider = Provider<KeyValueStore>((ref) {
  throw UnimplementedError('請在 main() 用 overrideWithValue 注入');
});

final wordRepositoryProvider = Provider<WordRepository>(
  (ref) => WordRepository(store: ref.watch(keyValueStoreProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(keyValueStoreProvider)),
);

/// 時間來源。測試時換掉這個就能固定「現在」。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 剛結束那一輪的成績，給結果頁讀。
/// 不用 autoDispose，因為從測驗頁跳到結果頁的過程中測驗頁會被銷毀。
final lastRoundProvider = StateProvider<RoundResult?>((ref) => null);
