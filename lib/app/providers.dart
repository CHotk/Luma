import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud/r2_client.dart';
import '../data/repositories/habit_log_repository.dart';
import '../domain/habit_config.dart';
import '../data/repositories/diary_repository.dart';
import '../data/repositories/error_log_repository.dart';
import '../data/repositories/fitness_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/kana_exam_repository.dart';
import '../data/repositories/kana_practice_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/sync_log_repository.dart';
import '../data/repositories/word_repository.dart';
import '../data/repositories/yt_tracker_repository.dart';
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

final ytTrackerRepositoryProvider = Provider<YtTrackerRepository>(
  (ref) => YtTrackerRepository(ref.watch(keyValueStoreProvider)),
);

/// 看盤／抽菸／喝酒紀錄，依 [HabitConfig] 各一個（同一個 const 設定同一個實例）。
final habitLogRepositoryProvider =
    Provider.family<HabitLogRepository, HabitConfig>(
      (ref, config) => HabitLogRepository(
        ref.watch(keyValueStoreProvider),
        config.storageKey,
      ),
    );

final fitnessRepositoryProvider = Provider<FitnessRepository>(
  (ref) => FitnessRepository(ref.watch(keyValueStoreProvider)),
);

final errorLogRepositoryProvider = Provider<ErrorLogRepository>(
  (ref) => ErrorLogRepository(ref.watch(keyValueStoreProvider)),
);

final syncLogRepositoryProvider = Provider<SyncLogRepository>(
  (ref) => SyncLogRepository(ref.watch(keyValueStoreProvider)),
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
  return TtsService(
    language: defaults.language,
    languageJa: defaults.languageJa,
    pitch: defaults.pitch,
  );
});

/// 偽裝模式。開著的時候這一輪不出打字題，
/// 因為偽裝畫面要假裝成終端機，跳出中文輸入法就穿幫了。
final stealthModeProvider = StateProvider<bool>((ref) => false);

/// YouTube API 金鑰。原本堅持只放記憶體、不寫進 localStorage
/// （2026-09-22），後來使用者覺得每次重新整理都要重貼太麻煩，改成存
/// `KeyValueStore`／localStorage，但帶效期（現在是一週）會自動過期
/// （2026-09-23 使用者決定，見 `data/repositories/yt_api_key_store.dart`）
/// ——不是永久留著，兩邊各退一步。這裡的初始值預設是 null，真正「有
/// 存過、還沒過期」的值是在 `main.dart` 用 `overrideWith` 蓋進來的；
/// 存新金鑰／清除金鑰時，畫面層要自己再呼叫一次 [YtApiKeyStore] 同步
/// 寫回本機，這個 provider 本身不會自動幫你寫（它只是純記憶體狀態，
/// 跟開機時讀一次是兩件事）。
final ytApiKeyProvider = StateProvider<String?>((ref) => null);

/// 剛結束那一輪的成績，給結果頁讀。
/// 不用 autoDispose，因為從測驗頁跳到結果頁的過程中測驗頁會被銷毀。
final lastRoundProvider = StateProvider<RoundResult?>((ref) => null);

/// R2 bucket 名稱，跟 [libraryTagOrderProvider] 同理，讀
/// `app_defaults.yaml` 要非同步，main() 先讀好用 overrideWithValue 注入。
final r2BucketNameProvider = Provider<String>((ref) {
  throw UnimplementedError('請在 main() 用 overrideWithValue 注入');
});

/// R2 同步憑證，跟 [ytApiKeyProvider] 同一套模式（記憶體 provider 讓
/// 畫面即時反應，`main()` 開機時讀一次本機存的值灌進來），但**沒有
/// 過期時間**——見 `data/cloud/r2_credentials_store.dart` 的說明，這把
/// 是要長期用來同步的，不能跟 YT 金鑰一樣常常過期。存新憑證／清除，
/// 畫面層要自己同時呼叫 `R2CredentialsStore` 寫回本機，這個 provider
/// 不會自動幫你同步寫入。
final r2CredentialsProvider = StateProvider<R2Credentials?>((ref) => null);
