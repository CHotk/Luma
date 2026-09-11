import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/quiz/quiz_page.dart';
import '../features/result/result_page.dart';
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
  ],
);
