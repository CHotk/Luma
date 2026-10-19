import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/music_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/music.dart';

/// 音樂兩台裝置同步（2026-10-19 使用者回報：電腦新增歌手，手機同步後沒看到）。
void main() {
  late _FakeR2Http cloud;
  late _MemoryStore pc;
  late _MemoryStore phone;

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
    pc = _MemoryStore();
    phone = _MemoryStore();
  });

  MusicArtist artist(String id, String name, DateTime at) =>
      MusicArtist(id: id, name: name, updatedAt: at);

  test('電腦新增歌手（還沒有任何歌）→ 電腦同步 → 手機同步，手機看得到', () async {
    final pcStore = MusicStore(pc);
    final phoneStore = MusicStore(phone);
    await pcStore.save(
      MusicData.empty.putArtist(artist('a1', '周杰倫', DateTime(2026, 10, 19, 9))),
    );
    expect(await serviceFor(pc).syncMusic(pcStore), (
      downloaded: 0,
      uploaded: 1,
    ));
    expect(await serviceFor(phone).syncMusic(phoneStore), (
      downloaded: 1,
      uploaded: 0,
    ));
    expect((await phoneStore.load()).artists.map((a) => a.name), ['周杰倫']);
  });

  test('手機本來就有別的資料：電腦後來新增歌手，手機再同步也拿得到', () async {
    final pcStore = MusicStore(pc);
    final phoneStore = MusicStore(phone);
    final t0 = DateTime(2026, 10, 18);
    await pcStore.save(MusicData.empty.putArtist(artist('a0', '五月天', t0)));
    await serviceFor(pc).syncMusic(pcStore);
    await serviceFor(phone).syncMusic(phoneStore);

    // 電腦新增第二個歌手；手機這段時間沒動。
    await pcStore.save(
      (await pcStore.load()).putArtist(
        artist('a1', '周杰倫', DateTime(2026, 10, 19, 9)),
      ),
    );
    await serviceFor(pc).syncMusic(pcStore);
    final r = await serviceFor(phone).syncMusic(phoneStore);
    expect(r.downloaded, 1);
    expect((await phoneStore.load()).artists.map((a) => a.name).toSet(), {
      '五月天',
      '周杰倫',
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
