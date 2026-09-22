import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/diary_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/kana_exam_repository.dart';
import '../data/repositories/kana_practice_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/word_repository.dart';
import '../data/seed/app_defaults_loader.dart';
import '../data/seed/word_seed_loader.dart';
import '../data/storage/key_value_store.dart';
import '../domain/models/quiz.dart';
import '../domain/services/tts_service.dart';

/// 全 App 共用的東西只有這幾個：儲存、兩個 repository、時間來源。
/// 其餘狀態一律放各自 feature 的資料夾，不要往這裡塞。

/// 儲存後端。在 main() 用 overrideWithValue 注入，
/// 因為 SharedPreferences 要非同步開啟，不適合在 provider 裡等。
final keyValueStoreProvider = Provider<KeyValueStore>((ref) {
  throw UnimplementedError('請在 main() 用 overrideWithValue 注入');
});

/// 單字庫標籤下拉選單的排序偏好。跟 [keyValueStoreProvider] 同理，
/// 讀 `app_defaults.yaml` 需要非同步，不適合在 provider 裡等，
/// 在 main() 先讀好再用 overrideWithValue 注入。
final libraryTagOrderProvider = Provider<LibraryTagOrder>((ref) {
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

final kanaPracticeRepositoryProvider = Provider<KanaPracticeRepository>(
  (ref) => KanaPracticeRepository(ref.watch(keyValueStoreProvider)),
);

final kanaExamRepositoryProvider = Provider<KanaExamRepository>(
  (ref) => KanaExamRepository(ref.watch(keyValueStoreProvider)),
);

final diaryRepositoryProvider = Provider<DiaryRepository>(
  (ref) => DiaryRepository(ref.watch(keyValueStoreProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(
    ref.watch(keyValueStoreProvider),
    // 給了來源，第一次讀取時會把 En 資料夾那邊的舊紀錄搬進來。
    seed: WordSeedLoader(),
  ),
);

/// 資料版本號。任何寫入之後就加一。
///
/// 為什麼需要它：測驗頁是用 push 疊在首頁上面的，首頁並沒有被銷毀，
/// 所以 autoDispose 不會觸發，回到首頁時看到的還是舊數字。
/// 讓每個讀資料的 provider 都 watch 這個號碼，寫入後畫面就會自己重算。
final dataRevisionProvider = StateProvider<int>((ref) => 0);

/// 時間來源。測試時換掉這個就能固定「現在」。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 發音。測驗頁跟單字詳情頁共用同一顆，不要每個畫面各自建一個
/// `FlutterTts` 實例——同時有兩個實例在背景初始化，Web 上偶爾會搶著
/// 註冊同一個瀏覽器 SpeechSynthesis 事件，聲音會怪怪的。
///
/// 語言／音調要先從 `app_defaults.yaml` 讀出來才能建立實例，所以是
/// `FutureProvider`，讀取端用 `ref.read(ttsServiceProvider.future)`。
final ttsServiceProvider = FutureProvider<TtsService>((ref) async {
  final defaults = await loadTtsDefaults();
  return TtsService(language: defaults.language, pitch: defaults.pitch);
});

/// 偽裝模式。開著的時候這一輪不出打字題，
/// 因為偽裝畫面要假裝成終端機，跳出中文輸入法就穿幫了。
final stealthModeProvider = StateProvider<bool>((ref) => false);

/// 剛結束那一輪的成績，給結果頁讀。
/// 不用 autoDispose，因為從測驗頁跳到結果頁的過程中測驗頁會被銷毀。
final lastRoundProvider = StateProvider<RoundResult?>((ref) => null);
