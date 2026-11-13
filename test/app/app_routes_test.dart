import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/router.dart';

import '../support/app_host.dart';
import '../support/poke.dart';
import '../support/yt_fake.dart';

/// 路由（2026-11-13 第 19 項）：整個 App 開起來，每條路徑都進去一次，不會壞；
/// 網址參數格式不對（月份、日期、一輪的時間、考試沒帶東西）退回預設；舊的 /tally
/// 轉走後回到首頁；不存在的路徑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  Future<void> openApp(WidgetTester tester) => openWholeApp(tester);

  Future<void> go(WidgetTester tester, String path, {Object? extra}) =>
      goPath(tester, path, extra: extra);

  const paths = [
    '/start',
    '/crypto-watch',
    '/crypto-watch/journal',
    '/crypto-watch/report?m=2026-9',
    '/crypto-watch/report?m=壞掉',
    '/crypto-watch/report',
    '/crypto-watch/day/2026-9-5',
    '/crypto-watch/day/2026-9',
    '/debt',
    '/debt/calendar',
    '/ledger',
    '/ledger/list',
    '/ledger/stats',
    '/ledger/accounts',
    '/ledger/log',
    '/ledger/subs',
    '/i88',
    '/i88/log',
    '/smoking-log',
    '/smoking-log/stats',
    '/drinking-log',
    '/drinking-log/stats',
    '/music',
    '/music/search',
    '/music/log',
    '/music/library?tab=artists&g=f',
    '/music/artist/沒有',
    '/music/work/沒有',
    '/music/list/沒有',
    '/home',
    '/jp-home',
    '/jp-stats',
    '/jp-log',
    '/jp-light',
    '/quiz',
    '/result',
    '/history',
    '/round/2026-10-01T08%3A00%3A00.000',
    '/round/壞掉',
    '/library',
    '/kana-practice',
    '/kana-practice/history',
    '/kana-exam',
    '/kana-exam/rows',
    '/kana-exam/light',
    '/kana-exam/history',
    '/kana-exam/start',
    '/diary',
    '/yt-tracker',
    '/yt-tracker/browse',
    '/yt-tracker/channel/a',
    '/yt-tracker/channel/a/log',
    '/yt-tracker/trash',
    '/yt-tracker/log',
    '/yt-tracker/purged',
    '/yt-tracker/category-order',
    '/yt-playlists',
    '/yt-playlists/沒有',
    '/fitness',
    '/fitness/stats',
    '/mastered',
    '/notes',
    '/settings',
    '/settings/other',
    '/home-card-order/app',
    '/home-card-order/jp',
    '/home-card-order/en',
    '/debug-log',
    '/local-storage',
    '/sync',
    '/sync/log',
    '/notes/traps/1',
    '/word/apple',
  ];

  testWidgets('每條路徑都進去一次，不會壞', (tester) async {
    await http.runWithClient(() async {
      await openApp(tester);
      for (final p in paths) {
        await go(tester, p);
        expect(tester.takeException(), isNull, reason: p);
        expect(currentAppPath(), Uri.parse(p).path, reason: p);
      }
      await tester.pump(const Duration(seconds: 5));
    }, () => FakeYoutube().client());
  });

  testWidgets('帶 extra 的頁面：考試三種進法、垃圾桶分類、日文紀錄只看點亮、櫻花慶祝', (tester) async {
    await http.runWithClient(() async {
      await openApp(tester);
      await go(tester, '/jp-log', extra: 'light');
      await go(tester, '/kana-exam/start', extra: 'あ');
      await go(tester, '/kana-exam/start', extra: <String>{'あ'});
      await go(tester, '/yt-tracker/trash/browse', extra: <String>{'c1'});
      await go(tester, '/yt-tracker/browse', extra: <String>{'c1'});
      await go(tester, '/yt-tracker/log', extra: <String>{'c1'});
      await go(tester, '/settings', extra: '/yt-tracker');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    }, () => FakeYoutube().client());
  });

  testWidgets('舊的記帳網址轉走後回首頁；開機畫面自己跳走', (tester) async {
    await http.runWithClient(() async {
      await openApp(tester);
      for (final p in ['/tally', '/tally/log', '/tally-solo']) {
        await go(tester, p);
        expect(currentAppPath(), '/start', reason: p);
      }
      // 不存在的路徑：go_router 自己的錯誤頁，不會丟例外。
      await go(tester, '/沒有這頁');
      expect(tester.takeException(), isNull);
      await go(tester, '/');
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, 4);
      expect(currentAppPath(), isNot('/'));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    }, () => FakeYoutube().client());
  });
}
