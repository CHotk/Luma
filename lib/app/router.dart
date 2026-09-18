import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
import '../features/history/round_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/jp_home/jp_home_page.dart';
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
import '../features/settings/settings_page.dart';
import '../features/splash/splash_page.dart';
import '../features/stealth/stealth_page.dart';

/// 全 App 的路徑只在這裡定義，畫面裡不准自己組路徑字串。
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/jp-home', builder: (_, _) => const JpHomePage()),
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
    GoRoute(path: '/mastered', builder: (_, _) => const MasteredPage()),
    GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(path: '/debug-log', builder: (_, _) => const DebugLogPage()),
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
