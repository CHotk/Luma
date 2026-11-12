import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/app_home_style_store.dart';
import 'package:lume/data/repositories/jp_home_ring_store.dart';
import 'package:lume/data/repositories/jp_light_style_store.dart';
import 'package:lume/data/repositories/ledger_confirm_store.dart';
import 'package:lume/data/repositories/ledger_row_title_store.dart';
import 'package:lume/data/repositories/ledger_show_note_store.dart';
import 'package:lume/data/repositories/ledger_sin_ask_store.dart';
import 'package:lume/data/repositories/ledger_usdt_rate_store.dart';
import 'package:lume/data/repositories/music_play_mode_store.dart';
import 'package:lume/data/repositories/nav_bar_prefs_store.dart';
import 'package:lume/data/repositories/usdt_twd_rate_store.dart';
import 'package:lume/data/repositories/yt_display_prefs_store.dart';
import 'package:lume/data/repositories/yt_embed_player_style_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_stats_refresh_setting_store.dart';
import 'package:lume/data/repositories/yt_video_open_mode_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/repositories/yt_video_song_store.dart';
import 'package:lume/features/settings/r2_sync_section.dart';

/// 多裝置同步：別台先改了設定、傳上雲端，這台按「立即同步」→ 每個設定都換成別台的、
/// 畫面上的狀態也跟著更新（2026-11-12 使用者：每個功能都補到 95%、更多邊界）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, List<int>> bucket;
  late int failStatus;

  http.Client cloud() => MockClient((req) async {
    if (failStatus != 0) return http.Response('broken', failStatus);
    final segs = req.url.pathSegments;
    final key = segs.skip(1).join('/');
    String etag(List<int> b) => md5.convert(b).toString();
    switch (req.method) {
      case 'GET':
        if (key.isEmpty) {
          // 列出檔案（影片快取、備份用）。
          final prefix = req.url.queryParameters['prefix'] ?? '';
          final items = [
            for (final e in bucket.entries)
              if (e.key.startsWith(prefix))
                '<Contents><Key>${e.key}</Key><ETag>"${etag(e.value)}"</ETag></Contents>',
          ].join();
          return http.Response(
            '<ListBucketResult>$items<IsTruncated>false</IsTruncated></ListBucketResult>',
            200,
          );
        }
        final b = bucket[key];
        return b == null
            ? http.Response('', 404)
            : http.Response.bytes(b, 200, headers: {'etag': '"${etag(b)}"'});
      case 'HEAD':
        if (key.isEmpty) return http.Response('', 200);
        final b = bucket[key];
        return b == null
            ? http.Response('', 404)
            : http.Response('', 200, headers: {'etag': '"${etag(b)}"'});
      case 'PUT':
        bucket[key] = req.bodyBytes;
        return http.Response(
          '',
          200,
          headers: {'etag': '"${etag(req.bodyBytes)}"'},
        );
      case 'DELETE':
        bucket.remove(key);
        return http.Response('', 204);
    }
    return http.Response('', 400);
  });

  setUp(() {
    bucket = {};
    failStatus = 0;
  });

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await http.runWithClient(
        () => tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        ),
        cloud,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 等到同步跑完（按鈕又出現「立即同步」）。
  Future<void> waitIdle(WidgetTester tester) async {
    for (var i = 0; i < 400; i++) {
      await settle(tester, rounds: 1);
      if (find.text('立即同步').evaluate().isNotEmpty) return;
    }
    fail('同步一直沒跑完');
  }

  Future<_MemoryStore> pump(WidgetTester tester, {R2Credentials? creds}) async {
    final store = _MemoryStore();
    tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          r2BucketNameProvider.overrideWithValue('lume'),
          r2CredentialsProvider.overrideWith((_) => creds),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: R2SyncSection())),
        ),
      ),
    );
    await tester.pump();
    return store;
  }

  /// 按下去的那一刻起都在假的雲端裡跑。
  Future<void> tapInCloud(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await http.runWithClient(() => tester.tap(f), cloud);
  }

  const creds = R2Credentials(
    endpoint: 'https://acc.r2.cloudflarestorage.com',
    accessKeyId: 'k',
    secretAccessKey: 's',
  );

  testWidgets('別台改過的設定：同步下來，每個都套用、寫「本裝置從雲端更新」', (tester) async {
    // 別台（A）：每個設定都改過、傳上雲端。
    final a = _MemoryStore();
    final sa = R2SyncService(
      R2Client(credentials: creds, bucket: 'lume', httpClient: cloud()),
      a,
    );
    await tester.runAsync(() async {
      await YtDisplayPrefsStore(
        a,
      ).save(YtDisplayPrefs.defaults.copyWith(videoIncludeCold: true));
      await YtVideoSongStore(a).set('v1', true);
      await YtVideoRatingStore(a).set(
        'v1',
        YtVideoRating(at: DateTime(2026, 11, 1), verdict: YtVerdict.ok),
      );
      await YtPlaylistStore(a).saveAll([
        ...await YtPlaylistStore(a).loadAll(),
        YtPlaylist(
          id: 'p',
          name: '清單',
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
      ]);
      await YtVideoOpenModeStore(a).save(YtVideoOpenMode.values.last);
      await YtEmbedPlayerStyleStore(a).save(YtEmbedPlayerStyle.values.last);
      await YtStatsRefreshSettingStore(a).save(3);
      await MusicPlayModeStore(a).save(MusicPlayMode.embedded);
      await JpHomeRingStore(a).save(false);
      await JpLightStyleStore(a).save(JpLightStyle.classic);
      await NavBarPrefsStore(a).save(
        NavBarPrefs(mode: NavBarMode.values.last, updatedAt: DateTime.now()),
      );
      await AppHomeStyleStore(a).save(AppHomeStyle.values.last);
      await UsdtTwdRateStore(a).save(30.1);
      await LedgerShowNoteStore(a).save(false);
      await LedgerSinAskStore(a).save(false);
      await LedgerConfirmStore(a).save(false);
      await LedgerUsdtRateStore(a).save(31.2);
      await LedgerRowTitleStore(a).save(LedgerRowTitleStore.merchant);
      await sa.syncYtDisplayPrefs(YtDisplayPrefsStore(a));
      await sa.syncYtVideoSongs(YtVideoSongStore(a));
      await sa.syncYtVideoRatings(YtVideoRatingStore(a));
      await sa.syncYtPlaylists(YtPlaylistStore(a));
      for (final r in [
        YtVideoOpenModeStore(a).record,
        YtEmbedPlayerStyleStore(a).record,
        YtStatsRefreshSettingStore(a).record,
        MusicPlayModeStore(a).record,
        JpHomeRingStore(a).record,
        JpLightStyleStore(a).record,
        AppHomeStyleStore(a).record,
        LedgerShowNoteStore(a).record,
        LedgerSinAskStore(a).record,
        LedgerConfirmStore(a).record,
        LedgerUsdtRateStore(a).record,
        LedgerRowTitleStore(a).record,
      ]) {
        await sa.syncStampedSetting(r);
      }
      await sa.syncNavBarPrefs(NavBarPrefsStore(a));
      await sa.syncUsdtTwdRate(UsdtTwdRateStore(a));
    });
    // 這台（B）：同步。
    final b = await pump(tester, creds: creds);
    await tapInCloud(tester, find.text('立即同步'));
    await waitIdle(tester);
    expect(find.textContaining('本裝置從雲端更新'), findsWidgets);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(R2SyncSection)),
    );
    expect(container.read(ytDisplayPrefsProvider).videoIncludeCold, isTrue);
    expect(container.read(ytVideoSongsProvider), contains('v1'));
    expect(container.read(musicPlayModeProvider), MusicPlayMode.embedded);
    expect(container.read(jpLightStyleProvider), JpLightStyle.classic);
    expect(
      container.read(ledgerRowTitleProvider),
      LedgerRowTitleStore.merchant,
    );
    expect(container.read(ledgerUsdtRateProvider), 31.2);
    expect(await tester.runAsync(() => LedgerConfirmStore(b).load()), isFalse);
    await tester.pump(const Duration(seconds: 6));
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

// ignore: unused_element
String _j(Object o) => jsonEncode(o);
