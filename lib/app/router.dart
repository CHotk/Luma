import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../features/crypto_watch/crypto_watch_page.dart';
import '../features/crypto_watch/crypto_watch_stats_page.dart';
import '../features/crypto_watch/trade_day_page.dart';
import '../features/crypto_watch/trade_journal_page.dart';
import '../features/crypto_watch/trade_report_page.dart';
import '../features/smoking_log/smoking_page.dart';
import '../features/smoking_log/smoking_stats_page.dart';
import '../features/drinking_log/drinking_page.dart';
import '../features/drinking_log/drinking_stats_page.dart';
import '../features/app_home/app_home_page.dart';

import '../features/debt/debt_calendar_page.dart';
import '../features/debt/debt_page.dart';
import '../features/diary/diary_page.dart';
import '../features/fitness/fitness_home_page.dart';
import '../features/fitness/fitness_stats_page.dart';
import '../features/history/history_page.dart';
import '../features/history/round_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/jp_home/jp_home_page.dart';
import '../features/jp_home/jp_stats_page.dart';
import '../features/kana_exam/kana_exam_history_page.dart';
import '../features/local_storage/local_storage_page.dart';
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
import '../features/settings/home_card_order_page.dart';
import '../features/settings/other_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../features/splash/splash_page.dart';
import '../features/sync/sync_log_page.dart';
import '../features/sync/sync_page.dart';
import '../features/yt_tracker/yt_category_order_page.dart';
import '../features/yt_tracker/yt_tracker_browse_page.dart';
import '../features/yt_tracker/yt_tracker_channel_page.dart';
import '../features/yt_tracker/yt_tracker_home_page.dart';
import '../features/yt_tracker/yt_channel_log_page.dart';
import '../features/yt_tracker/yt_purged_channels_page.dart';
import '../features/yt_tracker/yt_trash_page.dart';

/// 最外層 Navigator 的 key。給「發起的頁面已經被關掉，事情做完還是要
/// 跳提示」的情況拿 context 用（例如同步途中離開設定頁，見
/// `r2_sync_section.dart`）。
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 全 App 的路徑只在這裡定義，畫面裡不准自己組路徑字串。
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    // 看盤／抽菸／喝酒各自獨立的頁面（不共用）。
    GoRoute(path: '/crypto-watch', builder: (_, _) => const CryptoWatchPage()),
    GoRoute(
      path: '/crypto-watch/stats',
      builder: (_, _) => const CryptoWatchStatsPage(),
    ),
    GoRoute(
      path: '/crypto-watch/journal',
      builder: (_, _) => const TradeJournalPage(),
    ),
    GoRoute(
      path: '/crypto-watch/report',
      builder: (_, state) => TradeReportPage(
        initialMonth: _parseMonth(state.uri.queryParameters['m']),
      ),
    ),
    GoRoute(
      path: '/crypto-watch/day/:d',
      builder: (_, state) => TradeDayPage(
        day: _parseDay(state.pathParameters['d']) ?? DateTime.now(),
      ),
    ),
    // 負債每月還款表（2026-10-08）：主畫面是設計稿版本 1，月曆是版本 2。
    GoRoute(path: '/debt', builder: (_, _) => const DebtPage()),
    GoRoute(
      path: '/debt/calendar',
      builder: (_, _) => const DebtCalendarPage(),
    ),
    GoRoute(path: '/smoking-log', builder: (_, _) => const SmokingPage()),
    GoRoute(
      path: '/smoking-log/stats',
      builder: (_, _) => const SmokingStatsPage(),
    ),
    GoRoute(path: '/drinking-log', builder: (_, _) => const DrinkingPage()),
    GoRoute(
      path: '/drinking-log/stats',
      builder: (_, _) => const DrinkingStatsPage(),
    ),
    GoRoute(path: '/start', builder: (_, _) => const AppHomePage()),
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/jp-home', builder: (_, _) => const JpHomePage()),
    GoRoute(path: '/jp-stats', builder: (_, _) => const JpStatsPage()),
    GoRoute(path: '/quiz', builder: (_, _) => const QuizPage()),
    GoRoute(path: '/result', builder: (_, _) => const ResultPage()),
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
      builder: (_, state) =>
          YtTrackerChannelPage(channelId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(path: '/yt-tracker/trash', builder: (_, _) => const YtTrashPage()),
    GoRoute(
      path: '/yt-tracker/channel/:id/log',
      builder: (_, state) =>
          YtChannelLogPage(channelId: state.pathParameters['id']!),
    ),
    // 全部頻道的紀錄（2026-10-06）。從分類頁進來帶那幾個分類的 id。
    GoRoute(
      path: '/yt-tracker/log',
      builder: (_, state) => YtChannelLogPage(
        categoryIds: (state.extra as Set<String>?) ?? const {},
      ),
    ),
    GoRoute(
      path: '/yt-tracker/purged',
      builder: (_, _) => const YtPurgedChannelsPage(),
    ),
    GoRoute(
      path: '/yt-tracker/trash/browse',
      // 垃圾桶點進分類：跟一般分類頁同一頁，開垃圾桶模式（2026-10-06）。
      builder: (_, state) => YtTrackerBrowsePage(
        initialCategoryIds: state.extra as Set<String>,
        trash: true,
      ),
    ),
    GoRoute(
      path: '/yt-tracker/category-order',
      builder: (_, _) => const YtCategoryOrderPage(),
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
      builder: (_, state) =>
          OtherSettingsPage(fromLocation: state.extra as String?),
    ),
    // 英文／日文首頁卡片順序（2026-10-05 使用者要求）。
    GoRoute(
      path: '/home-card-order/:track',
      builder: (_, state) {
        // App 首頁圖示格的功能順序也走同一頁（2026-10-06）。
        return switch (state.pathParameters['track']) {
          'app' => const HomeCardOrderPage(
            track: 'app',
            title: '首頁功能順序',
            cards: appHomeCards,
          ),
          'jp' => const HomeCardOrderPage(
            track: 'jp',
            title: '日文首頁卡片順序',
            cards: jpHomeCards,
          ),
          _ => const HomeCardOrderPage(
            track: 'en',
            title: '英文首頁卡片順序',
            cards: enHomeCards,
          ),
        };
      },
    ),
    GoRoute(path: '/debug-log', builder: (_, _) => const DebugLogPage()),
    GoRoute(
      path: '/local-storage',
      builder: (_, _) => const LocalStoragePage(),
    ),
    GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
    GoRoute(path: '/sync/log', builder: (_, _) => const SyncLogPage()),
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

/// 交易&自律的網址參數：月份 `2026-9`、日期 `2026-9-5`，格式不對回傳 null。
DateTime? _parseMonth(String? s) {
  final p = s?.split('-').map(int.tryParse).toList();
  if (p == null || p.length != 2 || p.contains(null)) return null;
  return DateTime(p[0]!, p[1]!);
}

DateTime? _parseDay(String? s) {
  final p = s?.split('-').map(int.tryParse).toList();
  if (p == null || p.length != 3 || p.contains(null)) return null;
  return DateTime(p[0]!, p[1]!, p[2]!);
}
