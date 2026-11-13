import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/app_logo_store.dart';
import 'package:lume/data/repositories/debt_repository.dart';
import 'package:lume/data/repositories/diary_repository.dart';
import 'package:lume/data/repositories/fitness_repository.dart';
import 'package:lume/data/repositories/history_repository.dart';
import 'package:lume/data/repositories/jp_light_style_store.dart';
import 'package:lume/data/repositories/kana_exam_repository.dart';
import 'package:lume/data/repositories/music_play_mode_store.dart';
import 'package:lume/data/repositories/settings_repository.dart';
import 'package:lume/data/repositories/yt_api_key_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_subscriber_history_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/repositories/yt_video_hidden_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/daily_limit.dart';
import 'package:lume/domain/models/debt.dart';
import 'package:lume/domain/models/diary_entry.dart';
import 'package:lume/domain/models/fitness.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/domain/models/yt_subscriber_snapshot.dart';

/// 各功能的存取（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：新增、編輯、刪除
/// （蓋墓碑不真刪）、找不到就不做事、快照／雲端合併、匯出，以及小設定的預設值與亂寫的值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 11, 1, 9);

  group('日記', () {
    test('新增、編輯、刪除（墓碑）、找不到不做事、快照合併、匯出', () async {
      final s = _MemoryStore();
      final r = DiaryRepository(s);
      await r.add(DiaryEntry(id: 'd1', mood: '😀', text: '早', savedAt: t0));
      await r.update(DiaryEntry(id: 'd1', mood: '😢', text: '改了', savedAt: t0));
      await r.update(DiaryEntry(id: '沒有', mood: '😢', text: 'x', savedAt: t0));
      expect((await r.loadAll()).single.text, '改了');
      await r.delete('沒有');
      await r.delete('d1');
      expect(await r.loadAll(), isEmpty);
      expect((await r.loadAllIncludingDeleted()).single.deletedAt, isNotNull);
      await r.mergeSeed(const []);
      await r.mergeSeed([
        DiaryEntry(id: 's1', mood: '🙂', text: '快照', savedAt: t0),
      ]);
      expect((await r.loadAll()).single.text, '快照');
      expect(await r.mergeFromCloud(const []), 0);
      final ex = await r.exportJson();
      expect(ex.count, 1);
      expect(ex.text, contains('快照'));
    });
  });

  group('健身', () {
    test('新增、編輯、刪除、找不到不做事、快照合併、匯出', () async {
      final r = FitnessRepository(_MemoryStore());
      FitnessEntry e(String id, int min) => FitnessEntry(
        id: id,
        date: t0,
        type: FitnessType.strength,
        durationMinutes: min,
        loggedAt: t0,
      );
      await r.addEntry(e('f1', 10));
      await r.updateEntry(e('f1', 45));
      await r.updateEntry(e('沒有', 1));
      expect((await r.loadEntries()).single.durationMinutes, 45);
      await r.deleteEntry('沒有');
      await r.deleteEntry('f1');
      expect(await r.loadEntries(), isEmpty);
      expect(await r.loadAllIncludingDeleted(), hasLength(1));
      await r.mergeSeed(const []);
      await r.mergeSeed([e('s1', 20)]);
      expect(await r.mergeFromCloud(const []), 0);
      expect((await r.exportJson()).count, 1);
    });
  });

  group('50 音考試', () {
    KanaExamEntry e(String id, {bool ok = true, String type = 'hira'}) =>
        KanaExamEntry(
          id: id,
          roundId: 'r',
          kana: 'あ',
          romaji: 'a',
          isCorrect: ok,
          examType: type,
          savedAt: t0,
          strokes: const [],
        );

    test('新增、覆寫、刪除、清空（全部墓碑）、統計、快照、匯出；沒紀錄的統計是 0/0（邊界）', () async {
      final r = KanaExamRepository(_MemoryStore());
      expect(await r.getStats('hira'), (0, 0));
      await r.add(e('a'));
      await r.upsert(e('a', ok: false));
      await r.upsert(e('b'));
      await r.add(e('c', type: 'kata'));
      expect(await r.getStats('hira'), (1, 2));
      expect(await r.findByExamType('kata'), hasLength(1));
      await r.delete('沒有');
      await r.delete('b');
      expect(await r.getStats('hira'), (0, 1));
      await r.clearAll();
      expect(await r.loadAll(), isEmpty);
      expect(
        (await r.allForUpload()).every((x) => x.deletedAt != null),
        isTrue,
      );
      await r.mergeSeed(const []);
      await r.mergeSeed([e('s')]);
      expect(await r.mergeFromCloud(const []), 0);
      expect((await r.exportJson()).count, 1);
    });
  });

  group('債務', () {
    Debt draft() => Debt.fromJson({
      'id': '',
      'name': '信貸',
      'lender': '銀行',
      'type': DebtType.loan.name,
      'principal': 100000,
      'rate': 3.5,
      'term': 12,
      'firstYear': 2026,
      'firstMonth': 1,
      'dueDay': 5,
      'flexible': false,
      'flexPay': 0,
    });

    test('新增、改、刪（連繳款一起墓碑）、找不到不做事；取消一筆繳款；收入設定', () async {
      final r = DebtRepository(_MemoryStore());
      final d = await r.addDebt(draft());
      expect(d.id, isNotEmpty);
      await r.updateDebt(d.copyWith(name: '改名'));
      await r.updateDebt(Debt.fromJson({...draft().toJson(), 'id': '沒有'}));
      expect((await r.loadDebts()).single.name, '改名');
      final p1 = await r.addPayment(
        debtId: d.id,
        date: t0,
        amount: 9000,
        period: 1,
      );
      await r.addPayment(debtId: 'other', date: t0, amount: 1);
      await r.cancelPayment('沒有');
      await r.cancelPayment(p1.id);
      expect(await r.loadPayments(), hasLength(1));
      await r.addPayment(debtId: d.id, date: t0, amount: 9000, period: 2);
      await r.deleteDebt(d.id);
      await r.deleteDebt('沒有');
      expect(await r.loadDebts(), isEmpty);
      expect((await r.loadPayments()).single.debtId, 'other');
      expect(await r.loadIncome(), isNull);
      await r.setIncome(50000);
      await r.setIncome(60000);
      expect(await r.loadIncome(), 60000);
      expect(await r.mergeDebtsFromCloud(const []), 0);
      expect(await r.mergeSettingsFromCloud(await r.settingsForUpload()), 0);
    });
  });

  group('英文作答紀錄', () {
    test('匯出文字（同一輪同一個序號、沒打字寫 -）、總計、某一輪、某個字；沒紀錄＝空的總計', () async {
      final r = HistoryRepository(_MemoryStore());
      expect((await r.lifetime()).rounds, 0);
      await r.appendAnswer(
        HistoryEntry(word: 'Apple', correct: true, at: t0, seconds: 3),
      );
      await r.appendAnswer(
        HistoryEntry(
          word: 'book',
          correct: false,
          at: t0,
          typed: true,
          input: 'bok',
        ),
      );
      final t1 = t0.add(const Duration(days: 1));
      await r.appendAnswer(
        HistoryEntry(word: 'apple', correct: false, at: t1),
        stealth: true,
      );
      await r.finishRound(t0, const Duration(seconds: 40));
      await r.finishRound(DateTime(2000), const Duration(seconds: 1)); // 找不到那一輪
      final text = await r.exportText();
      expect(text, contains('R1  Apple  O  tap  -  3'));
      expect(text, contains('R1  book  X  type  bok'));
      expect(text, contains('R2  apple  X'));
      final life = await r.lifetime();
      expect(life.rounds, 2);
      expect(life.questions, 3);
      expect(life.right, 1);
      expect(life.wrong, 2);
      expect(life.stealthRounds, 1);
      expect(life.activeDays, 2);
      expect(life.seconds, 40);
      expect(await r.forRound(t0), hasLength(2));
      final apple = await r.forWord('APPLE');
      expect(apple.first.at, t1);
      expect(apple, hasLength(2));
    });
  });

  group('YT 小東西', () {
    test('訂閱人數歷史：照時間排、最多 200 筆、雲端合併只加新的', () async {
      final r = YtSubscriberHistoryStore(_MemoryStore());
      expect(await r.load('c'), isEmpty);
      for (var i = 0; i < 205; i++) {
        await r.add(
          'c',
          YtSubscriberSnapshot(
            at: t0.add(Duration(hours: i)),
            count: i,
          ),
        );
      }
      final all = await r.load('c');
      expect(all, hasLength(200));
      expect(all.first.count, 5);
      expect(await r.mergeFromCloud('c', const []), 0);
      expect(await r.mergeFromCloud('c', [all.first]), 0);
      expect(
        await r.mergeFromCloud('c', [YtSubscriberSnapshot(at: t0, count: 0)]),
        1,
      );
      expect((await r.load('c')).first.count, 0);
    });

    test('隱藏影片：藏、重複藏不變、取消、取消沒藏的不變、雲端合併', () async {
      final r = YtVideoHiddenStore(_MemoryStore());
      await r.hide('v1');
      await r.hide('v1');
      expect(await r.contains('v1'), isTrue);
      await r.unhide('v2');
      await r.unhide('v1');
      expect(await r.loadAll(), isEmpty);
      expect(await r.mergeFromCloud({}), 0);
      expect(await r.mergeFromCloud({'a', 'b'}), 2);
      expect(await r.mergeFromCloud({'a'}), 0);
    });

    test('影片評價：準度段位 S／A／B／C、資料少；待驗證、到期；copyWith 清掉欄位', () {
      YtVideoRating r(YtVerdict? v, {String ch = 'c', DateTime? due}) =>
          YtVideoRating(at: t0, verdict: v, channelId: ch, dueAt: due);
      expect(ytAccuracyOf([r(YtVerdict.ok), r(YtVerdict.ok)]).label, '資料少');
      expect(ytAccuracyOf(const []).rate, isNull);
      expect(ytAccuracyOf(List.filled(3, r(YtVerdict.ok))).grade, 'S');
      expect(
        ytAccuracyOf([
          r(YtVerdict.ok),
          r(YtVerdict.ok),
          r(YtVerdict.half),
        ]).grade,
        'S',
      );
      expect(
        ytAccuracyOf([
          r(YtVerdict.ok),
          r(YtVerdict.ok),
          r(YtVerdict.bad),
        ]).grade,
        'A',
      );
      expect(
        ytAccuracyOf([
          r(YtVerdict.ok),
          r(YtVerdict.half),
          r(YtVerdict.bad),
        ]).grade,
        'B',
      );
      final c = ytAccuracyOf([
        r(YtVerdict.bad),
        r(YtVerdict.bad),
        r(YtVerdict.ok),
        r(YtVerdict.none),
        r(null, due: t0),
        r(YtVerdict.ok, ch: '別的'),
      ], channelId: 'c');
      expect(c.grade, 'C');
      expect(c.label, 'C 33%');
      expect(c.none, 1);
      expect(c.pending, 1);
      final p = r(null, due: t0);
      expect(p.pending, isTrue);
      expect(p.isDue(t0), isTrue);
      expect(p.isDue(t0.subtract(const Duration(days: 1))), isFalse);
      expect(r(null).isEmpty, isTrue);
      final full = p.copyWith(verdict: YtVerdict.ok, ratedAt: t0, note: 'n');
      expect(full.pending, isFalse);
      final cleared = full.copyWith(
        clearVerdict: true,
        clearDue: true,
        clearRatedAt: true,
        note: '',
      );
      expect(cleared.isEmpty, isTrue);
      expect(cleared.ratedAt, isNull);
      expect(YtVerdict.parse('ok'), YtVerdict.ok);
      expect(YtVerdict.parse('亂寫'), isNull);
      expect(YtVerdict.parse(null), isNull);
    });

    test('播放清單：壞掉的資料當沒有、一定有稍後觀看；看得到的排序；影片 JSON 來回', () async {
      final s = _MemoryStore();
      s.data['yt_tracker.playlists.v1'] = '{壞掉';
      final store = YtPlaylistStore(s);
      final first = await store.loadAll();
      expect(first.single.isLater, isTrue);
      final v = YoutubeVideo(
        videoId: 'v1',
        title: '影片',
        publishedAt: t0,
        thumbnailUrl: 'https://x/y.jpg',
      );
      final item = YtPlaylistItem(video: v, channelName: '頻道', addedAt: t0);
      final pl = YtPlaylist(
        id: 'p',
        name: '清單',
        items: [item],
        createdAt: t0,
        updatedAt: t0,
      );
      await store.saveAll([
        pl,
        YtPlaylist(
          id: 'gone',
          name: '刪了',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: t0,
        ),
      ]);
      final all = await store.loadAll();
      expect(all.first.isLater, isTrue);
      final vis = YtPlaylistStore.visible(all);
      expect(vis.map((p) => p.id), ['later', 'p']);
      expect(vis.last.contains('v1'), isTrue);
      expect(vis.last.items.single.videoId, 'v1');
      final back = YtPlaylistItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())),
      );
      expect(back.channelName, '頻道');
      final renamed = pl.copyWith(name: '新名', items: const []);
      expect(renamed.name, '新名');
      expect(renamed.contains('v1'), isFalse);
      // 合併：後改的贏、只有一邊有的留下。
      final newer = pl.copyWith(
        name: '後改',
        updatedAt: t0.add(const Duration(hours: 1)),
      );
      final m = YtPlaylistStore.merge([pl], [newer, YtPlaylist.emptyLater()]);
      expect(m.firstWhere((p) => p.id == 'p').name, '後改');
      expect(m.any((p) => p.isLater), isTrue);
    });

    test('API 金鑰：存了讀得到；過期自動清掉；清除', () async {
      final s = _MemoryStore();
      final r = YtApiKeyStore(s);
      expect(await r.load(), isNull);
      await r.save('KEY');
      expect(await r.load(), 'KEY');
      s.data['yt_tracker.api_key.v1'] = jsonEncode({
        'key': 'OLD',
        // 效期改成三個月（2026-11-13）：存了超過 90 天才過期。
        'savedAt': DateTime.now()
            .subtract(const Duration(days: 90, seconds: 1))
            .toIso8601String(),
      });
      expect(await r.load(), isNull);
      expect(s.data.containsKey('yt_tracker.api_key.v1'), isFalse);
      await r.save('K2');
      await r.clear();
      expect(await r.load(), isNull);
    });
  });

  group('小設定', () {
    test('櫻花點亮樣式、音樂播放方式：預設、可改、亂寫的當預設', () async {
      final s = _MemoryStore();
      expect(await JpLightStyleStore(s).load(), JpLightStyleStore.defaultStyle);
      await JpLightStyleStore(s).save(JpLightStyle.classic);
      expect(await JpLightStyleStore(s).load(), JpLightStyle.classic);
      await JpLightStyleStore(s).record.saveValue('亂寫');
      expect(await JpLightStyleStore(s).load(), JpLightStyle.gpt);
      expect(
        await MusicPlayModeStore(s).load(),
        MusicPlayModeStore.defaultMode,
      );
      await MusicPlayModeStore(s).save(MusicPlayMode.embedded);
      expect(await MusicPlayModeStore(s).load(), MusicPlayMode.embedded);
      await MusicPlayModeStore(s).record.saveValue('亂寫');
      expect(await MusicPlayModeStore(s).load(), MusicPlayMode.youtube);
    });

    test('App 圖示：沒選＝null、選了、清掉', () async {
      final r = AppLogoStore(_MemoryStore());
      expect(await r.load(), isNull);
      await r.save('assets/logo.png');
      expect(await r.load(), 'assets/logo.png');
      await r.clear();
      expect(await r.load(), isNull);
    });

    test('一般設定：規則沒存用預設、存了讀回；今天的用量、跨天歸零；上次的語言', () async {
      final r = SettingsRepository(_MemoryStore());
      final rules = await r.loadRules();
      await r.saveRules(rules);
      expect((await r.loadRules()).toJson(), rules.toJson());
      final today = DateTime(2026, 11, 12, 10);
      expect((await r.loadUsage(today)).roundsDone, 0);
      await r.saveUsage(DailyUsage(date: today, roundsDone: 3));
      expect((await r.loadUsage(today)).roundsDone, 3);
      expect(
        (await r.loadUsage(today.add(const Duration(days: 1)))).roundsDone,
        0,
      );
      expect(await r.loadLastTrack(), isNull);
      await r.saveLastTrack('jp');
      expect(await r.loadLastTrack(), 'jp');
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
