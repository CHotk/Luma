import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
import '../features/history/round_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/notes/note_detail_page.dart';
import '../features/notes/notes_page.dart';
import '../features/word_detail/word_detail_page.dart';
import '../features/quiz/quiz_page.dart';
import '../features/result/result_page.dart';
import '../features/settings/settings_page.dart';
import '../features/splash/splash_page.dart';
import '../features/stealth/stealth_page.dart';

/// 全 App 的路徑只在這裡定義，畫面裡不准自己組路徑字串。
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/quiz', builder: (_, _) => const QuizPage()),
    GoRoute(path: '/result', builder: (_, _) => const ResultPage()),
    GoRoute(path: '/stealth', builder: (_, _) => const StealthPage()),
    GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
    GoRoute(
      path: '/round/:round',
      builder: (_, state) => RoundDetailPage(
        round: int.tryParse(state.pathParameters['round'] ?? '') ?? 0,
      ),
    ),
    GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
    GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(
      path: '/notes/:no',
      builder: (_, state) =>
          NoteDetailPage(no: state.pathParameters['no'] ?? ''),
    ),
    GoRoute(
      path: '/word/:word',
      builder: (_, state) =>
          WordDetailPage(word: state.pathParameters['word'] ?? ''),
    ),
  ],
);
