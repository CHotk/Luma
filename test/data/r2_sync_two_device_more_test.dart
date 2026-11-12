import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/cloud/r2_client.dart';
import 'package:lume/data/cloud/r2_credentials_store.dart';
import 'package:lume/data/cloud/r2_sync_service.dart';
import 'package:lume/data/repositories/debt_repository.dart';
import 'package:lume/data/repositories/diary_password_store.dart';
import 'package:lume/data/repositories/diary_repository.dart';
import 'package:lume/data/repositories/drinking_repository.dart';
import 'package:lume/data/repositories/error_log_repository.dart';
import 'package:lume/data/repositories/fitness_repository.dart';
import 'package:lume/data/repositories/history_repository.dart';
import 'package:lume/data/repositories/kana_exam_repository.dart';
import 'package:lume/data/repositories/kana_practice_repository.dart';
import 'package:lume/data/repositories/nav_bar_prefs_store.dart';
import 'package:lume/data/repositories/smoking_repository.dart';
import 'package:lume/data/repositories/sync_log_repository.dart';
import 'package:lume/data/repositories/yt_category_order_store.dart';
import 'package:lume/data/repositories/yt_channel_log_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/repositories/yt_video_song_store.dart';
import 'package:lume/data/repositories/yt_video_watch_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/diary_entry.dart';
import 'package:lume/domain/models/fitness.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/domain/models/kana_practice.dart';
import 'package:lume/domain/models/sync_log_entry.dart';
import 'package:lume/shared/debug/app_log.dart';

/// 每種資料的雲端同步，兩台裝置共用一個假的 R2（2026-11-12 使用者：每個功能都補到 95%）：
/// A 新增 → 同步上去 → B 同步下來看得到；沒變的第二次同步不用傳（跳過）；
/// 雲端還沒有檔案（第一次）、兩邊時間一樣、雲端比較新、本機比較新（邊界）。
void main() {
  late Map<String, List<int>> bucket;
  late List<String> calls;

  R2SyncService service(_MemoryStore s) {
    final cloud = MockClient((req) async {
      final key = req.url.pathSegments.skip(1).join('/');
      calls.add('${req.method} $key');
      String etag(List<int> b) => md5.convert(b).toString();
      switch (req.method) {
        case 'GET':
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

  setUp(() {
    bucket = {};
    calls = [];
  });

  final t0 = DateTime(2026, 11, 1, 10);

  test('測試連線：寫一個測試檔再刪掉，雲端不留東西', () async {
    await service(_MemoryStore()).testConnection();
    expect(calls, contains('PUT _lume_sync_test.json'));
    expect(calls, contains('DELETE _lume_sync_test.json'));
    expect(bucket.containsKey('_lume_sync_test.json'), isFalse);
  });

  test('日記：A 寫一篇 → B 看得到；回報下載／上傳階段；再同步一次沒變就跳過', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await DiaryRepository(
      a,
    ).add(DiaryEntry(id: 'd1', mood: '😀', text: '今天很好', savedAt: t0));
    final phases = <SyncPhase>[];
    final up = await service(
      a,
    ).syncDiary(DiaryRepository(a), onPhase: phases.add);
    expect(up.uploaded, 1);
    expect(phases, [SyncPhase.downloading, SyncPhase.uploading]);
    final down = await service(b).syncDiary(DiaryRepository(b));
    expect(down.downloaded, 1);
    expect((await DiaryRepository(b).loadAll()).single.text, '今天很好');
    calls.clear();
    final again = await service(b).syncDiary(DiaryRepository(b));
    expect(again, (downloaded: 0, uploaded: 0));
    expect(calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  test('日記密碼：雲端沒有＝上傳；別台改得比較新＝拉下來；時間一樣＝都不算', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await DiaryPasswordStore(
      a,
    ).saveRecord(DiaryPasswordRecord(password: '1111', updatedAt: t0));
    expect(
      (await service(a).syncDiaryPassword(DiaryPasswordStore(a))).uploaded,
      1,
    );
    await DiaryPasswordStore(b).saveRecord(
      DiaryPasswordRecord(
        password: '0000',
        updatedAt: t0.subtract(const Duration(days: 1)),
      ),
    );
    expect(
      (await service(b).syncDiaryPassword(DiaryPasswordStore(b))).downloaded,
      1,
    );
    expect(await DiaryPasswordStore(b).loadPassword(), '1111');
    // B 再改得比較新 → 上傳；A 同步拿到。
    await DiaryPasswordStore(b).saveRecord(
      DiaryPasswordRecord(
        password: '2222',
        updatedAt: t0.add(const Duration(days: 1)),
      ),
    );
    expect(
      (await service(b).syncDiaryPassword(DiaryPasswordStore(b))).uploaded,
      1,
    );
    await service(a).syncDiaryPassword(DiaryPasswordStore(a));
    expect(await DiaryPasswordStore(a).loadPassword(), '2222');
    // 跳過的 meta 拿掉，強迫比一次：時間一樣＝0、0。
    final fresh = _MemoryStore();
    await DiaryPasswordStore(fresh).saveRecord(
      DiaryPasswordRecord(
        password: '2222',
        updatedAt: t0.add(const Duration(days: 1)),
      ),
    );
    expect(await service(fresh).syncDiaryPassword(DiaryPasswordStore(fresh)), (
      downloaded: 0,
      uploaded: 0,
    ));
  });

  test('健身：A 記一筆 → B 看得到', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await FitnessRepository(a).addEntry(
      FitnessEntry(
        id: 'f1',
        date: t0,
        type: FitnessType.cardio,
        durationMinutes: 30,
        loggedAt: t0,
      ),
    );
    final phases = <SyncPhase>[];
    await service(a).syncFitness(FitnessRepository(a), onPhase: phases.add);
    expect(phases.length, 2);
    final down = await service(b).syncFitness(FitnessRepository(b));
    expect(down.downloaded, 1);
    expect(
      (await FitnessRepository(b).loadEntries()).single.durationMinutes,
      30,
    );
  });

  test('抽菸、喝酒：各自一個檔案，A 記的 B 看得到，刪掉的也同步', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    final s = await SmokingRepository(a).add(reason: '壓力', at: t0);
    await DrinkingRepository(a).add(reason: '聚餐', at: t0);
    await service(a).syncSmoking(SmokingRepository(a));
    await service(a).syncDrinking(DrinkingRepository(a));
    expect(bucket.keys, containsAll(['smoking.json', 'drinking.json']));
    await service(b).syncSmoking(SmokingRepository(b));
    await service(b).syncDrinking(DrinkingRepository(b));
    expect((await SmokingRepository(b).loadAll()).single.reason, '壓力');
    expect((await DrinkingRepository(b).loadAll()).single.reason, '聚餐');
    await SmokingRepository(a).delete(s.id);
    await service(a).syncSmoking(SmokingRepository(a));
    await service(b).syncSmoking(SmokingRepository(b));
    expect(await SmokingRepository(b).loadAll(), isEmpty);
  });

  test('債務：還款紀錄跟設定一起同步', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await DebtRepository(a).addPayment(debtId: 'x', date: t0, amount: 1234);
    final up = await service(a).syncDebts(DebtRepository(a));
    expect(up.uploaded, greaterThanOrEqualTo(1));
    await service(b).syncDebts(DebtRepository(b));
    expect((await DebtRepository(b).loadPayments()).single.amount, 1234);
  });

  test('50 音練習、考試：A 寫的 B 看得到', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await KanaPracticeRepository(a).add(
      KanaPracticeEntry(
        id: 'p1',
        kana: 'あ',
        romaji: 'a',
        assisted: false,
        savedAt: t0,
        strokes: const [],
      ),
    );
    await KanaExamRepository(a).add(
      KanaExamEntry(
        id: 'e1',
        roundId: 'r1',
        kana: 'い',
        romaji: 'i',
        isCorrect: true,
        examType: 'hiragana',
        savedAt: t0,
        strokes: const [],
      ),
    );
    await service(a).syncKanaPractice(KanaPracticeRepository(a));
    await service(a).syncKanaExam(KanaExamRepository(a));
    await service(b).syncKanaPractice(KanaPracticeRepository(b));
    await service(b).syncKanaExam(KanaExamRepository(b));
    expect((await KanaPracticeRepository(b).loadAll()).single.kana, 'あ');
    expect((await KanaExamRepository(b).loadAll()).single.kana, 'い');
  });

  test('英文作答紀錄：作答＋每輪摘要一起同步；同一筆不會重複', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await HistoryRepository(
      a,
    ).appendAnswer(HistoryEntry(word: 'apple', correct: true, at: t0));
    await HistoryRepository(a).finishRound(t0, const Duration(seconds: 30));
    final phases = <SyncPhase>[];
    final up = await service(
      a,
    ).syncEnglishHistory(HistoryRepository(a), onPhase: phases.add);
    expect(up.uploaded, greaterThanOrEqualTo(1));
    expect(phases.length, 2);
    await service(b).syncEnglishHistory(HistoryRepository(b));
    expect((await HistoryRepository(b).entries()).single.word, 'apple');
    expect(await HistoryRepository(b).rounds(), hasLength(1));
    // B 再同步一次：雲端已經有，不會變兩筆。
    await HistoryRepository(b).appendAnswer(
      HistoryEntry(
        word: 'book',
        correct: false,
        at: t0.add(const Duration(minutes: 1)),
      ),
    );
    final b2 = await service(b).syncEnglishHistory(HistoryRepository(b));
    // 新的一題＋它那一輪的摘要＝2 筆（已經在雲端的 apple 不算）。
    expect(b2.uploaded, 2);
    await service(a).syncEnglishHistory(HistoryRepository(a));
    expect(await HistoryRepository(a).entries(), hasLength(2));
  });

  test('YT 分類順序：沒設定過又沒雲端＝不做事；有設定＝上傳；比較新的贏；時間一樣不算', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    expect(await service(a).syncYtCategoryOrder(YtCategoryOrderStore(a)), (
      downloaded: 0,
      uploaded: 0,
    ));
    await YtCategoryOrderStore(
      a,
    ).saveRecord(YtCategoryOrderRecord(order: const ['x', 'y'], updatedAt: t0));
    expect(
      (await service(a).syncYtCategoryOrder(YtCategoryOrderStore(a))).uploaded,
      1,
    );
    // B 沒設定過：拉下來。
    expect(
      (await service(
        b,
      ).syncYtCategoryOrder(YtCategoryOrderStore(b))).downloaded,
      1,
    );
    expect(await YtCategoryOrderStore(b).load(), ['x', 'y']);
    // B 改得比較新：上傳。
    await YtCategoryOrderStore(b).saveRecord(
      YtCategoryOrderRecord(
        order: const ['y', 'x'],
        updatedAt: t0.add(const Duration(hours: 1)),
      ),
    );
    expect(
      (await service(b).syncYtCategoryOrder(YtCategoryOrderStore(b))).uploaded,
      1,
    );
    // A 的比較舊：拉下來。
    expect(
      (await service(
        a,
      ).syncYtCategoryOrder(YtCategoryOrderStore(a))).downloaded,
      1,
    );
    // 時間一樣（新裝置、同一份）：都不算。
    final c = _MemoryStore();
    await YtCategoryOrderStore(c).saveRecord(
      YtCategoryOrderRecord(
        order: const ['y', 'x'],
        updatedAt: t0.add(const Duration(hours: 1)),
      ),
    );
    expect(await service(c).syncYtCategoryOrder(YtCategoryOrderStore(c)), (
      downloaded: 0,
      uploaded: 0,
    ));
  });

  test('YT 看過了：A 點開兩次 → B 拿到兩次；B 再點一次會上傳', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await YtVideoWatchStore(a).markOpened('v1');
    await YtVideoWatchStore(a).markOpened('v1');
    expect(
      (await service(a).syncYtVideoWatch(YtVideoWatchStore(a))).uploaded,
      1,
    );
    await service(b).syncYtVideoWatch(YtVideoWatchStore(b));
    expect((await YtVideoWatchStore(b).get('v1'))!.openedAt.length, 2);
    await YtVideoWatchStore(b).markOpened('v1');
    expect(
      (await service(b).syncYtVideoWatch(YtVideoWatchStore(b))).uploaded,
      1,
    );
  });

  test('YT 頻道紀錄：聯集；雲端有壞掉的一筆會略過（邊界）', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await YtChannelLogStore(a).addAll([
      YtChannelEvent(
        id: 'e1',
        channelId: 'c',
        at: t0,
        type: YtChannelEventType.added,
      ),
    ]);
    await service(a).syncYtChannelLog(YtChannelLogStore(a));
    // 雲端塞一筆壞的。
    final list =
        jsonDecode(utf8.decode(bucket['yt_channel_log.json']!)) as List;
    list.add({'id': 'bad', 'type': '不存在的種類'});
    bucket['yt_channel_log.json'] = utf8.encode(jsonEncode(list));
    final down = await service(b).syncYtChannelLog(YtChannelLogStore(b));
    expect(down.downloaded, 1);
    expect((await YtChannelLogStore(b).loadAll()).single.id, 'e1');
  });

  test('YT 歌曲標記、評分、播放清單：A 設的 B 拿到；沒變的跳過', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await YtVideoSongStore(a).set('v1', true);
    await YtVideoRatingStore(
      a,
    ).set('v1', YtVideoRating(at: t0, verdict: YtVerdict.ok, claim: '會漲'));
    final lists = await YtPlaylistStore(a).loadAll();
    await YtPlaylistStore(a).saveAll([
      ...lists,
      YtPlaylist(id: 'pl', name: '我的清單', createdAt: t0, updatedAt: t0),
    ]);
    final sa = service(a);
    expect(
      (await sa.syncYtVideoSongs(YtVideoSongStore(a))).uploaded,
      greaterThanOrEqualTo(1),
    );
    await sa.syncYtVideoRatings(YtVideoRatingStore(a));
    await sa.syncYtPlaylists(YtPlaylistStore(a));
    final sb = service(b);
    expect(
      (await sb.syncYtVideoSongs(YtVideoSongStore(b))).downloaded,
      greaterThanOrEqualTo(1),
    );
    await sb.syncYtVideoRatings(YtVideoRatingStore(b));
    await sb.syncYtPlaylists(YtPlaylistStore(b));
    expect(await YtVideoSongStore(b).loadIds(), {'v1'});
    expect((await YtVideoRatingStore(b).load())['v1']!.claim, '會漲');
    expect(
      (await YtPlaylistStore(b).loadAll()).any((p) => p.name == '我的清單'),
      isTrue,
    );
    calls.clear();
    await sb.syncYtVideoSongs(YtVideoSongStore(b));
    await sb.syncYtVideoRatings(YtVideoRatingStore(b));
    await sb.syncYtPlaylists(YtPlaylistStore(b));
    expect(calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  test('導覽列設定：雲端沒有＝上傳；比較新的贏', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await NavBarPrefsStore(
      a,
    ).saveRecord(NavBarPrefs(mode: NavBarMode.values.last, updatedAt: t0));
    expect((await service(a).syncNavBarPrefs(NavBarPrefsStore(a))).uploaded, 1);
    expect(
      (await service(b).syncNavBarPrefs(NavBarPrefsStore(b))).downloaded,
      1,
    );
    expect((await NavBarPrefsStore(b).load()).mode, NavBarMode.values.last);
    await NavBarPrefsStore(b).saveRecord(
      NavBarPrefs(
        mode: NavBarMode.values.first,
        updatedAt: t0.add(const Duration(hours: 1)),
      ),
    );
    expect((await service(b).syncNavBarPrefs(NavBarPrefsStore(b))).uploaded, 1);
    expect(
      (await service(a).syncNavBarPrefs(NavBarPrefsStore(a))).downloaded,
      1,
    );
    expect((await NavBarPrefsStore(a).load()).mode, NavBarMode.values.first);
  });

  test('同步紀錄、錯誤日誌：只增不刪，兩邊聯集；上傳數＝雲端還沒有的', () async {
    final a = _MemoryStore(), b = _MemoryStore();
    await SyncLogRepository(a).add(
      SyncLogEntry(at: t0, action: SyncLogAction.values.first, success: true),
    );
    await ErrorLogRepository(
      a,
    ).add(AppLogEntry(message: '壞了', at: t0, isError: true));
    expect((await service(a).syncLog(SyncLogRepository(a))).uploaded, 1);
    expect((await service(a).syncErrorLog(ErrorLogRepository(a))).uploaded, 1);
    await SyncLogRepository(b).add(
      SyncLogEntry(
        at: t0.add(const Duration(minutes: 1)),
        action: SyncLogAction.values.last,
        success: false,
      ),
    );
    final down = await service(b).syncLog(SyncLogRepository(b));
    expect(down, (downloaded: 1, uploaded: 1));
    expect(await SyncLogRepository(b).loadAll(), hasLength(2));
    final err = await service(b).syncErrorLog(ErrorLogRepository(b));
    expect(err.downloaded, 1);
    expect((await ErrorLogRepository(b).loadAll()).single.message, '壞了');
  });

  test('同步憑證：沒存過＝null；存了讀得回來；清掉又是 null', () async {
    final s = _MemoryStore();
    final store = R2CredentialsStore(s);
    expect(await store.load(), isNull);
    await store.save(
      const R2Credentials(
        endpoint: 'https://e',
        accessKeyId: 'a',
        secretAccessKey: 'b',
      ),
    );
    expect((await store.load())!.accessKeyId, 'a');
    await store.clear();
    expect(await store.load(), isNull);
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
