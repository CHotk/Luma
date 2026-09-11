import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/history_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/word_repository.dart';
import '../data/seed/word_seed_loader.dart';
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
  (ref) => WordRepository(
    store: ref.watch(keyValueStoreProvider),
    // 對錯次數是從紀錄加總出來的，所以單字庫依賴紀錄，不是反過來。
    history: ref.watch(historyRepositoryProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(keyValueStoreProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(
    ref.watch(keyValueStoreProvider),
    // 給了來源，第一次讀取時會把 En 資料夾那邊的舊紀錄搬進來。
    seed: WordSeedLoader(),
  ),
);

/// 時間來源。測試時換掉這個就能固定「現在」。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 偽裝模式。開著的時候這一輪不出打字題，
/// 因為偽裝畫面要假裝成終端機，跳出中文輸入法就穿幫了。
final stealthModeProvider = StateProvider<bool>((ref) => false);

/// 剛結束那一輪的成績，給結果頁讀。
/// 不用 autoDispose，因為從測驗頁跳到結果頁的過程中測驗頁會被銷毀。
final lastRoundProvider = StateProvider<RoundResult?>((ref) => null);
