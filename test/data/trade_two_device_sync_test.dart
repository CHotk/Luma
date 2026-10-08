import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/crypto_watch_repository.dart';
import 'package:lume/data/repositories/trade_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-08 使用者要求「交易&自律要確保多裝置都能同步」：兩台裝置（各自
/// 的本機儲存）透過同一個假的雲端 bucket 同步，看盤次數、每一單（開倉、
/// 平倉、刪除）、月初資金都要兩邊對得上。
void main() {
  test('兩台裝置互相同步：開倉、平倉、刪除、看盤、月初資金都帶得過去', () async {
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
    R2SyncService service(KeyValueStore meta) => R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          accessKeyId: 'k',
          secretAccessKey: 's',
        ),
        bucket: 'lume',
        httpClient: cloud(),
      ),
      meta,
    );

    final phone = _MemoryStore(), pc = _MemoryStore();
    Future<void> sync(_MemoryStore s) async {
      final svc = service(s);
      await svc.syncTrades(TradeRepository(s));
      await svc.syncCryptoWatch(CryptoWatchRepository(s));
    }

    // 手機：開一單、看兩次盤、設月初資金。
    final t = await TradeRepository(phone).add(
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 400,
      openedAt: DateTime(2026, 10, 1, 22, 10),
    );
    final other = await TradeRepository(phone).add(
      symbol: 'ETH',
      isLong: false,
      leverage: 5,
      margin: 100,
      openedAt: DateTime(2026, 10, 2, 9),
      closedAt: DateTime(2026, 10, 2, 12),
      pnl: -20,
    );
    await CryptoWatchRepository(phone).add(at: DateTime(2026, 10, 8, 9));
    await CryptoWatchRepository(phone).add(at: DateTime(2026, 10, 8, 10));
    await TradeRepository(phone).setCapital(DateTime(2026, 10), 2000);
    await sync(phone);

    // 電腦：同步後全部都有。
    await sync(pc);
    var trades = await TradeRepository(pc).loadAll();
    expect(trades.map((e) => e.id), containsAll([t.id, other.id]));
    expect(trades.firstWhere((e) => e.id == t.id).isOpen, isTrue);
    expect((await CryptoWatchRepository(pc).loadAll()).length, 2);
    expect((await TradeRepository(pc).loadCapitals())['2026-10'], 2000);

    // 電腦：平倉、刪掉另一單、再看一次盤、改月初資金。
    await TradeRepository(
      pc,
    ).close(t.id, pnl: 132, at: DateTime(2026, 10, 8, 22));
    await TradeRepository(pc).delete(other.id);
    await CryptoWatchRepository(pc).add(at: DateTime(2026, 10, 8, 11));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await TradeRepository(pc).setCapital(DateTime(2026, 10), 2500);
    await sync(pc);

    // 手機：同步後看到平倉結果、刪除、第三次看盤、新的月初資金。
    await sync(phone);
    trades = await TradeRepository(phone).loadAll();
    expect(trades.map((e) => e.id), [t.id]);
    expect(trades.single.pnl, 132);
    expect(trades.single.closedAt, DateTime(2026, 10, 8, 22));
    expect((await CryptoWatchRepository(phone).loadAll()).length, 3);
    expect((await TradeRepository(phone).loadCapitals())['2026-10'], 2500);
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
