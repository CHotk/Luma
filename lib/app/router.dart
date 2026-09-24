import 'package:go_router/go_router.dart';

import '../features/diary/diary_page.dart';
import '../features/fitness/fitness_home_page.dart';
import '../features/fitness/fitness_stats_page.dart';
import '../features/history/history_page.dart';
import '../features/history/round_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/jp_home/jp_home_page.dart';
import '../features/jp_home/jp_stats_page.dart';
import '../features/kana_exam/kana_exam_history_page.dart';
import '../features/kana_exam/kana_exam_mode_select_page.dart';
import '../features/kana_exam/kana_exam_page.dart';
import '../features/kana_exam/kana_exam_row_select_page.dart';
import '../features/kana_practice/kana_practice_history_page.dart';
import '../features/kana_practice/kana_practice_page.dart';
import '../features/library/library_page.dart';
import '../features/mastered/mastered_page.dart';
import '../domain/models/note_collection.dart';
import '../features/notes/note_detail_page.dart';
import '../features/notes/notes_page.dart';
import '../features/word_detail/word_detail_page.dart';
import '../features/quiz/quiz_page.dart';
import '../features/result/result_page.dart';
import '../features/settings/debug_log_page.dart';
import '../features/settings/other_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../features/splash/splash_page.dart';
import '../features/stealth/stealth_page.dart';
import '../features/sync/sync_page.dart';
import '../features/yt_tracker/yt_tracker_browse_page.dart';
import '../features/yt_tracker/yt_tracker_channel_page.dart';
import '../features/yt_tracker/yt_tracker_home_page.dart';

/// 全 App 的路徑只在這裡定義，畫面裡不准自己組路徑字串。
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/jp-home', builder: (_, _) => const JpHomePage()),
    GoRoute(path: '/jp-stats', builder: (_, _) => const JpStatsPage()),
    GoRoute(path: '/quiz', builder: (_, _) => const QuizPage()),
    GoRoute(path: '/result', builder: (_, _) => const ResultPage()),
    GoRoute(path: '/stealth', builder: (_, _) => const StealthPage()),
    GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
    GoRoute(
      path: '/round/:at',
      // 一輪已經沒有編號了，路由參數是那一輪共用的 at 時戳（ISO8601，
      // 用 Uri.encodeComponent 編碼過，因為冒號跟點在路徑片段裡不安全）
      // ——見 history_repository.dart／history_page.dart 的說明。
      builder: (_, state) => RoundDetailPage(
        at:
            DateTime.tryParse(
              Uri.decodeComponent(state.pathParameters['at'] ?? ''),
            ) ??
            DateTime(0),
      ),
    ),
    GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
    GoRoute(
      path: '/kana-practice',
      // extra 是日文首頁預覽卡片點空白處帶進來的起始選擇（見
      // jp_home_page.dart 的說明），沒有就是一般從按鈕進來，從第一行
      // 開始選。
      builder: (_, state) =>
          KanaPracticePage(initial: state.extra as KanaPracticeInitial?),
    ),
    GoRoute(
      path: '/kana-practice/history',
      builder: (_, _) => const KanaPracticeHistoryPage(),
    ),
    GoRoute(
      path: '/kana-exam',
      builder: (_, _) => const KanaExamModeSelectPage(),
      routes: [
        GoRoute(path: 'rows', builder: (_, _) => const KanaExamRowSelectPage()),
        GoRoute(
          path: 'history',
          builder: (_, _) => const KanaExamHistoryPage(),
        ),
        GoRoute(
          path: 'start',
          // extra 是進來的方式決定的型別：詞彙模式從模式選擇頁直接帶
          // `ExamMode.vocab` 進來（不用選範圍）；50 音模式從選題範圍頁
          // 帶 `(ExamMode.kana, Set<String>)` 進來（選中的行）。兩種都
          // 沒對到就沒得考，直接退回選擇頁（正常操作不會發生，防的是
          // 有人直接打網址）。
          builder: (_, state) {
            final extra = state.extra;
            if (extra is ExamMode) {
              return KanaExamPage(mode: extra);
            }
            if (extra is (ExamMode, Set<String>)) {
              return KanaExamPage(mode: extra.$1, selectedRows: extra.$2);
            }
            return const KanaExamModeSelectPage();
          },
        ),
      ],
    ),
    GoRoute(path: '/diary', builder: (_, _) => const DiaryPage()),
    GoRoute(path: '/yt-tracker', builder: (_, _) => const YtTrackerHomePage()),
    GoRoute(
      path: '/yt-tracker/browse',
      // extra 是從首頁點哪個分類資料夾進來的（見 yt_tracker_home_page.dart），
      // 沒帶（例如有人直接打網址）就當作沒篩選，顯示全部。
      builder: (_, state) => YtTrackerBrowsePage(
        initialCategoryIds: state.extra as Set<String>? ?? const {},
      ),
    ),
    GoRoute(
      path: '/yt-tracker/channel/:id',
      builder: (_, state) => YtTrackerChannelPage(
        channelId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(path: '/fitness', builder: (_, _) => const FitnessHomePage()),
    GoRoute(
      path: '/fitness/stats',
      builder: (_, _) => const FitnessStatsPage(),
    ),
    GoRoute(path: '/mastered', builder: (_, _) => const MasteredPage()),
    GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(
      path: '/settings/other',
      builder: (_, _) => const OtherSettingsPage(),
    ),
    GoRoute(path: '/debug-log', builder: (_, _) => const DebugLogPage()),
    GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
    GoRoute(
      path: '/notes/:collection/:no',
      builder: (_, state) => NoteDetailPage(
        collection: NoteCollection.parse(state.pathParameters['collection']),
        no: state.pathParameters['no'] ?? '',
      ),
    ),
    GoRoute(
      path: '/word/:word',
      builder: (_, state) =>
          WordDetailPage(word: state.pathParameters['word'] ?? ''),
    ),
  ],
);
