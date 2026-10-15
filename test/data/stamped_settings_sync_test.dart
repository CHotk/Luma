import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/app_home_style_store.dart';
import 'package:lume/data/repositories/jp_home_ring_store.dart';
import 'package:lume/data/repositories/stamped_setting_store.dart';
import 'package:lume/data/repositories/yt_embed_player_style_store.dart';
import 'package:lume/data/repositories/yt_search_recents_store.dart';
import 'package:lume/data/repositories/yt_stats_refresh_setting_store.dart';
import 'package:lume/data/repositories/yt_video_open_mode_store.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-15 使用者要求：原本只存本機的設定（點影片時、播放器樣式、
/// 訂閱人數更新頻率、日文進度圈、首頁樣式）跟最近搜尋也要多裝置同步。
void main() {
  R2SyncService service(Map<String, List<int>> bucket, _MemoryStore s) {
    final cloud = MockClient((req) async {
      final key = req.url.pathSegments.skip(1).join('/');
      String etag(List<int> b) => md5.convert(b).toString();
      switch (req.method) {
        case 'GET':
          final b = bucket[key];
          return b == null
              ? http.Response('', 404)
              : http.Response.bytes(b, 200, headers: {'etag': '"${etag(b)}"'});
        case 'HEAD':
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
      }
      return http.Response('', 400);
    });
    return R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: cloud,
      ),
      s,
    );
  }

  Future<void> twoDevices(
    StampedSettingStore Function(_MemoryStore) store,
  ) async {
    final bucket = <String, List<int>>{};
    Future<void> sync(_MemoryStore s) =>
        service(bucket, s).syncStampedSetting(store(s));

    final phone = _MemoryStore(), pc = _MemoryStore();
    // 都沒設定過：不上傳。
    await sync(phone);
    expect(bucket, isEmpty);

    await YtVideoOpenModeStore(phone).save(YtVideoOpenMode.embedded);
    await sync(phone);
    await sync(pc);
    expect(await YtVideoOpenModeStore(pc).load(), YtVideoOpenMode.embedded);

    // 電腦後來改回開新分頁：手機同步後跟著變。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await YtVideoOpenModeStore(pc).save(YtVideoOpenMode.external);
    await sync(pc);
    await sync(phone);
    expect(await YtVideoOpenModeStore(phone).load(), YtVideoOpenMode.external);
  }

  test('點影片時兩台互相同步，後改的贏', () async {
    await twoDevices((s) => YtVideoOpenModeStore(s).record);
  });

  test('其他舊設定也都接同步', () async {
    final phone = _MemoryStore(), pc = _MemoryStore();
    final bucket = <String, List<int>>{};
    Future<void> syncAll(_MemoryStore s) async {
      final svc = service(bucket, s);
      for (final r in [
        YtEmbedPlayerStyleStore(s).record,
        YtStatsRefreshSettingStore(s).record,
        JpHomeRingStore(s).record,
        AppHomeStyleStore(s).record,
        YtSearchRecentsStore(s).record,
      ]) {
        await svc.syncStampedSetting(r);
      }
    }

    await YtEmbedPlayerStyleStore(phone).save(YtEmbedPlayerStyle.bottomSheet);
    await YtStatsRefreshSettingStore(phone).save(30);
    await JpHomeRingStore(phone).save(true);
    await AppHomeStyleStore(phone).save(AppHomeStyle.dashboard);
    await YtSearchRecentsStore(phone).add('周杰倫');
    await syncAll(phone);
    await syncAll(pc);
    expect(
      await YtEmbedPlayerStyleStore(pc).load(),
      YtEmbedPlayerStyle.bottomSheet,
    );
    expect(await YtStatsRefreshSettingStore(pc).load(), 30);
    expect(await JpHomeRingStore(pc).load(), isTrue);
    expect(await AppHomeStyleStore(pc).load(), AppHomeStyle.dashboard);
    expect(await YtSearchRecentsStore(pc).load(), ['周杰倫']);

    // 刪掉最近搜尋也跟著同步。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await YtSearchRecentsStore(pc).remove('周杰倫');
    await syncAll(pc);
    await syncAll(phone);
    expect(await YtSearchRecentsStore(phone).load(), isEmpty);
  });

  test('舊版直接存值的讀得進來，雲端沒有就上傳', () async {
    final phone = _MemoryStore()
      ..data['yt_tracker.stats_refresh_days.v1'] = '3';
    expect(await YtStatsRefreshSettingStore(phone).load(), 3);
    final bucket = <String, List<int>>{};
    final r = await service(
      bucket,
      phone,
    ).syncStampedSetting(YtStatsRefreshSettingStore(phone).record);
    expect(r.uploaded, 1);
    final pc = _MemoryStore();
    await service(
      bucket,
      pc,
    ).syncStampedSetting(YtStatsRefreshSettingStore(pc).record);
    expect(await YtStatsRefreshSettingStore(pc).load(), 3);
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
