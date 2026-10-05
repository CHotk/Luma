import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/home_card_order_store.dart';
import 'package:lume/data/storage/key_value_store.dart';

void main() {
  group('套用存起來的順序', () {
    const defaults = ['calendar', 'ring', 'kana', 'exam', 'next'];

    test('沒排過就是預設順序', () {
      expect(applyHomeCardOrder(defaults, null), defaults);
    });

    test('照存的排；之後新加的卡片接在後面，拿掉的卡片跳過', () {
      expect(applyHomeCardOrder(defaults, ['next', 'gone', 'calendar']), [
        'next',
        'calendar',
        'ring',
        'kana',
        'exam',
      ]);
    });
  });

  group('兩台裝置同步', () {
    late _FakeR2Http cloud;
    late _MemoryStore phone;
    late _MemoryStore laptop;

    R2SyncService serviceFor(_MemoryStore store) => R2SyncService(
      R2Client(
        credentials: const R2Credentials(
          endpoint: 'https://example.r2.cloudflarestorage.com',
          accessKeyId: 'id',
          secretAccessKey: 'secret',
        ),
        bucket: 'test-bucket',
        httpClient: cloud,
      ),
      store,
    );

    setUp(() {
      cloud = _FakeR2Http();
      phone = _MemoryStore();
      laptop = _MemoryStore();
    });

    test('手機排好、同步，電腦同步後拿到同一個順序；之後電腦再改，手機也跟上', () async {
      final phoneJp = HomeCardOrderStore(phone, 'jp');
      final laptopJp = HomeCardOrderStore(laptop, 'jp');

      await phoneJp.saveRecord(
        HomeCardOrderRecord(
          order: ['next', 'calendar'],
          updatedAt: DateTime(2026, 10, 5, 9),
        ),
      );
      expect(await serviceFor(phone).syncHomeCardOrder(phoneJp), (
        downloaded: 0,
        uploaded: 1,
      ));
      expect(await serviceFor(laptop).syncHomeCardOrder(laptopJp), (
        downloaded: 1,
        uploaded: 0,
      ));
      expect(await laptopJp.load(), ['next', 'calendar']);

      // 電腦之後又改了一次（時間比較新）。
      await laptopJp.saveRecord(
        HomeCardOrderRecord(
          order: ['exam', 'next'],
          updatedAt: DateTime(2026, 10, 5, 10),
        ),
      );
      await serviceFor(laptop).syncHomeCardOrder(laptopJp);
      await serviceFor(phone).syncHomeCardOrder(phoneJp);
      expect(await phoneJp.load(), ['exam', 'next']);

      // 兩邊都沒再動，再同步一次不該有任何上傳下載。
      expect(await serviceFor(phone).syncHomeCardOrder(phoneJp), (
        downloaded: 0,
        uploaded: 0,
      ));
    });

    test('兩台都改了還沒同步：比較晚改的那台贏，不會被舊的蓋回去', () async {
      final phoneEn = HomeCardOrderStore(phone, 'en');
      final laptopEn = HomeCardOrderStore(laptop, 'en');
      await phoneEn.saveRecord(
        HomeCardOrderRecord(
          order: ['ring', 'calendar', 'next'],
          updatedAt: DateTime(2026, 10, 5, 8),
        ),
      );
      await laptopEn.saveRecord(
        HomeCardOrderRecord(
          order: ['next', 'ring', 'calendar'],
          updatedAt: DateTime(2026, 10, 5, 11),
        ),
      );

      // 舊的那台先同步上去，新的那台後同步。
      await serviceFor(phone).syncHomeCardOrder(phoneEn);
      await serviceFor(laptop).syncHomeCardOrder(laptopEn);
      await serviceFor(phone).syncHomeCardOrder(phoneEn);

      expect(await phoneEn.load(), ['next', 'ring', 'calendar']);
      expect(await laptopEn.load(), ['next', 'ring', 'calendar']);
    });

    test('英文跟日文各存各的，不會互相蓋掉', () async {
      final en = HomeCardOrderStore(phone, 'en');
      final jp = HomeCardOrderStore(phone, 'jp');
      await en.save(['next', 'calendar', 'ring']);
      await jp.save(['kana', 'calendar']);
      await serviceFor(phone).syncHomeCardOrder(en);
      await serviceFor(phone).syncHomeCardOrder(jp);

      await serviceFor(
        laptop,
      ).syncHomeCardOrder(HomeCardOrderStore(laptop, 'en'));
      await serviceFor(
        laptop,
      ).syncHomeCardOrder(HomeCardOrderStore(laptop, 'jp'));
      expect(await HomeCardOrderStore(laptop, 'en').load(), [
        'next',
        'calendar',
        'ring',
      ]);
      expect(await HomeCardOrderStore(laptop, 'jp').load(), [
        'kana',
        'calendar',
      ]);
    });
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

/// 假的 R2：每個 key 的內容跟一個遞增的 ETag 存在記憶體裡（跟
/// `yt_category_delete_sync_repro_test.dart` 同一套）。
class _FakeR2Http extends http.BaseClient {
  final Map<String, Uint8List> _objects = {};
  final Map<String, String> _etags = {};
  int _etagSeq = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    switch (request.method) {
      case 'HEAD':
        if (!_objects.containsKey(path)) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'etag': _etags[path]!},
        );
      case 'GET':
        final body = _objects[path];
        if (body == null) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          Stream.value(body),
          200,
          headers: {'etag': _etags[path]!},
        );
      case 'PUT':
        final bytes = await request.finalize().toBytes();
        _objects[path] = Uint8List.fromList(bytes);
        _etagSeq++;
        final etag = 'v$_etagSeq';
        _etags[path] = etag;
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'etag': etag},
        );
      default:
        throw UnsupportedError('unexpected method ${request.method}');
    }
  }
}
