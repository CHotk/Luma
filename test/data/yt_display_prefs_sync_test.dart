import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/yt_display_prefs_store.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-12 使用者要求：設定也要多裝置同步。YT 顯示設定在一台改，
/// 另一台同步後跟著變；後改的贏。
void main() {
  test('YT 顯示設定兩台裝置互相同步，後改的贏', () async {
    final bucket = <String, List<int>>{};
    http.Client cloud() => MockClient((req) async {
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
    Future<void> sync(_MemoryStore s) => R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: cloud(),
      ),
      s,
    ).syncYtDisplayPrefs(YtDisplayPrefsStore(s));

    final phone = _MemoryStore(), pc = _MemoryStore();
    // 都沒設定過：不上傳。
    await sync(phone);
    expect(bucket, isEmpty);

    // 手機關掉捲動條。
    final p = YtDisplayPrefsStore(phone);
    await p.save((await p.load()).copyWith(showScrollbar: false));
    await sync(phone);
    await sync(pc);
    final onPc = await YtDisplayPrefsStore(pc).load();
    expect(onPc.showScrollbar, isFalse);
    expect(onPc.showBackToTop, isTrue);

    // 電腦後來關掉回到最上面、打開抓冷藏：手機同步後跟著變。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final c = YtDisplayPrefsStore(pc);
    await c.save(
      onPc.copyWith(
        showBackToTop: false,
        videoIncludeCold: true,
        removedCheckDays: 30,
      ),
    );
    await sync(pc);
    await sync(phone);
    final onPhone = await YtDisplayPrefsStore(phone).load();
    expect(onPhone.showScrollbar, isFalse);
    expect(onPhone.showBackToTop, isFalse);
    expect(onPhone.videoIncludeCold, isTrue);
    // 下架檢查多久一次（2026-10-12）也一起同步。
    expect(onPhone.removedCheckDays, 30);
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
