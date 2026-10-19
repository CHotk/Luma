import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/music_event_log_store.dart';
import 'package:lume/data/repositories/music_play_log_store.dart';
import 'package:lume/data/repositories/music_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/music.dart';

/// 音樂兩台裝置同步（2026-10-19 使用者回報：電腦新增歌手，手機同步後沒看到）。
void main() {
  urlTests();
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

  test('兩台各自新增同名歌手：同步後合成一個，歌跟原唱改指到留下的那個，兩台結果一樣', () async {
    final pcStore = MusicStore(pc);
    final phoneStore = MusicStore(phone);
    MusicVersion ver(String id, String artist) => MusicVersion(
      id: id,
      workId: 'w',
      type: MusicVersionType.sing,
      artistIds: [artist],
      videoTitle: 't',
      thumbnailUrl: '',
      uploaderName: 'u',
      publishedAt: DateTime(2026, 10, 1),
      addedAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 19, 9, 5),
    );
    final work = MusicWork(
      id: 'w',
      title: '晴天',
      originalArtistIds: const ['a2'],
      updatedAt: DateTime(2026, 10, 19, 9, 5),
    );
    await pcStore.save(
      MusicData.empty
          .putArtist(artist('a1', '周杰倫', DateTime(2026, 10, 19, 9)))
          .putWork(work.copyWith(originalArtistIds: const ['a1']))
          .putVersion(ver('v1', 'a1')),
    );
    await phoneStore.save(
      MusicData.empty
          .putArtist(artist('a2', '周杰倫', DateTime(2026, 10, 19, 9, 1)))
          .putWork(work)
          .putVersion(ver('v2', 'a2')),
    );
    await serviceFor(pc).syncMusic(pcStore);
    await serviceFor(phone).syncMusic(phoneStore);
    await serviceFor(pc).syncMusic(pcStore);
    for (final st in [pcStore, phoneStore]) {
      final d = await st.load();
      expect(d.artists.map((a) => a.id), ['a1']);
      expect(d.versions.map((v) => v.artistIds.single).toSet(), {'a1'});
      expect(d.work('w')!.originalArtistIds, ['a1']);
    }
    // 兩邊都合好了，再同步一次不該有任何異動。
    expect(await serviceFor(pc).syncMusic(pcStore), (
      downloaded: 0,
      uploaded: 0,
    ));
    expect(await serviceFor(phone).syncMusic(phoneStore), (
      downloaded: 0,
      uploaded: 0,
    ));
  });

  test('播放紀錄、異動紀錄：兩台各記各的，同步後兩邊都是聯集、一筆不少', () async {
    final pcPlay = MusicPlayLogStore(pc), phonePlay = MusicPlayLogStore(phone);
    final pcEv = MusicEventLogStore(pc), phoneEv = MusicEventLogStore(phone);
    await pcPlay.save({
      'v1': [MusicPlay(at: DateTime(2026, 10, 19, 9), from: '首頁', mode: 'app')],
    });
    await phonePlay.save({
      'v1': [
        MusicPlay(at: DateTime(2026, 10, 19, 10), from: '搜尋', mode: 'youtube'),
      ],
      'v2': [MusicPlay(at: DateTime(2026, 10, 19, 11))],
    });
    await pcEv.save([
      MusicEvent(id: 'e1', at: DateTime(2026, 10, 19, 9), text: '電腦做的'),
    ]);
    await phoneEv.save([
      MusicEvent(id: 'e2', at: DateTime(2026, 10, 19, 10), text: '手機做的'),
    ]);
    await serviceFor(pc).syncMusicPlayLog(pcPlay);
    await serviceFor(pc).syncMusicEventLog(pcEv);
    await serviceFor(phone).syncMusicPlayLog(phonePlay);
    await serviceFor(phone).syncMusicEventLog(phoneEv);
    await serviceFor(pc).syncMusicPlayLog(pcPlay);
    await serviceFor(pc).syncMusicEventLog(pcEv);
    for (final p in [pcPlay, phonePlay]) {
      expect(MusicPlayLogStore.count(await p.load()), 3);
    }
    for (final e in [pcEv, phoneEv]) {
      expect((await e.load()).map((x) => x.id).toSet(), {'e1', 'e2'});
    }
  });

  test('時間存成 UTC、讀回來是本地時間，來回不變', () {
    final t = DateTime(2026, 10, 19, 23, 30);
    final a = MusicArtist(id: 'x', name: 'n', updatedAt: t);
    final json = a.toJson();
    expect((json['updatedAt'] as String).endsWith('Z'), isTrue);
    expect(MusicArtist.fromJson(json).updatedAt, t);
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

void urlTests() {
  test('從貼上的文字抓 YouTube 影片 ID', () {
    const id = 'DYptgVvkVLQ';
    for (final t in [
      'https://www.youtube.com/watch?v=$id',
      'https://www.youtube.com/watch?v=$id&list=PLx&t=30s',
      'https://youtu.be/$id?si=abc',
      'https://m.youtube.com/shorts/$id',
      'https://music.youtube.com/watch?v=$id&feature=share',
      'https://www.youtube.com/embed/$id',
      '看這首 https://youtu.be/$id 很好聽',
      id,
    ]) {
      expect(YoutubeApiService.parseVideoId(t), id, reason: t);
    }
    expect(YoutubeApiService.parseVideoId('https://example.com/abc'), isNull);
    expect(YoutubeApiService.parseVideoId(''), isNull);
  });
}
