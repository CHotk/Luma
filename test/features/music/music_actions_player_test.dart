import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_actions.dart';
import 'package:lume/features/music/music_player.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 音樂的動作與播放器（2026-11-12 補到 95%）：新增歌手（同名沿用、補性別／大頭貼）、
/// 改歌手（每種改法、名字空白不改、沒改不記）、改名、改歌（歌名空白沿用、原唱）、
/// 加版本（新歌、已有的歌）、改版本（每個欄位、年份清掉）、換歌名（併到已有、新開、
/// 原本那首沒版本了收起來）、不喜歡（順便拿出喜歡）、喜歡／歌單、刪歌單（最愛不能刪）；
/// 播放器：上一首（超過 3 秒回開頭）、下一首（到底、重複整份、重複這首）、
/// 隨機、下一首播放、YouTube 回報的狀態、從佇列拿掉、關掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef ref;

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          musicDataProvider.overrideWith((_) => seedMusicData()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (_, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  MusicData d() => ref.read(musicDataProvider);
  List<String> log() =>
      ref.read(musicEventLogProvider).map((e) => e.text).toList();

  testWidgets('歌手：新增、同名沿用並補性別與大頭貼、改各種欄位、改名', (tester) async {
    await host(tester);
    final a = MusicActions(ref);
    await tester.runAsync(() async {
      final id = await a.ensureArtist(
        ' 新人 ',
        avatarUrls: [' https://img/a.png ', '  ', 'https://img/b.png'],
        shownAvatar: 9,
        gender: 'f',
        crops: const {
          'https://img/a.png': [0, 0, 1.2],
        },
      );
      expect(d().artist(id)!.name, '新人');
      expect(d().artist(id)!.avatarUrls, hasLength(2));
      expect(d().artist(id)!.shownAvatar, 1);
      expect(log().last, contains('大頭貼 2 張'));
      final plain = await a.ensureArtist('沒圖的');
      expect(log().last, '新增歌手「沒圖的」');
      // 同名：沿用，性別、大頭貼不一樣就以這次為準；一樣就不動。
      expect(await a.ensureArtist('小花', gender: 'm'), 'hana');
      expect(d().artist('hana')!.gender, 'm');
      expect(
        await a.ensureArtist('小花', avatarUrls: ['https://img/h.png']),
        'hana',
      );
      expect(d().artist('hana')!.avatarUrls, ['https://img/h.png']);
      final n = log().length;
      await a.ensureArtist(
        '小花',
        avatarUrls: ['https://img/h.png'],
        gender: 'm',
      );
      expect(log().length, n);

      // 改歌手：名字空白、找不到、沒改都不動。
      await a.updateArtist(
        'jay',
        name: '  ',
        avatarUrls: const [],
        shownAvatar: 0,
      );
      await a.updateArtist(
        '沒有',
        name: 'x',
        avatarUrls: const [],
        shownAvatar: 0,
      );
      final j = d().artist('jay')!;
      await a.updateArtist(
        'jay',
        name: j.name,
        avatarUrls: j.avatarUrls,
        shownAvatar: j.shownAvatar,
      );
      expect(log().length, n);
      await a.updateArtist(
        'jay',
        name: 'Jay',
        avatarUrls: ['https://img/jay1.png'],
        shownAvatar: 0,
        gender: 'f',
        crops: const {
          'https://img/jay1.png': [0.2, 0, 1],
        },
      );
      expect(
        log().last,
        allOf(
          contains('名字'),
          contains('大頭貼改成 1 張'),
          contains('性別改成女'),
          contains('調整大頭貼圓框'),
        ),
      );
      await a.updateArtist(
        'jay',
        name: 'Jay',
        avatarUrls: ['https://img/jay1.png', 'https://img/jay3.png'],
        shownAvatar: 1,
        gender: 'm',
      );
      expect(log().last, allOf(contains('改顯示第 2 張'), contains('性別改成男')));

      await a.renameArtist(plain, '  ');
      await a.renameArtist(plain, '沒圖的');
      await a.renameArtist('沒有', 'x');
      await a.renameArtist(plain, '改了');
      expect(d().artist(plain)!.name, '改了');
    });
  });

  testWidgets('歌曲與版本：改歌、加版本、改版本、換歌名、不喜歡、喜歡、歌單', (tester) async {
    await host(tester);
    final a = MusicActions(ref);
    await tester.runAsync(() async {
      await a.editWork('沒有', title: 'x');
      final n0 = log().length;
      await a.editWork('w1', title: '  ');
      expect(log().length, n0);
      await a.editWork('w1', title: '晴天2', originalArtistIds: const ['hana']);
      expect(d().work('w1')!.title, '晴天2');
      expect(log().last, contains('原唱'));
      await a.editWork('w3', originalArtistIds: const []);

      // 加版本：給了已有的歌、沒給就開新歌（標題空白用影片標題、原唱用第一位歌手）。
      final v = await a.addVersion(
        videoId: 'nv1',
        videoTitle: '新影片',
        thumbnailUrl: '',
        uploaderName: 'up',
        publishedAt: musicT,
        workId: 'w1',
        type: MusicVersionType.cover,
        artistIds: const ['band'],
        note: ' 好聽 ',
      );
      expect(v.workId, 'w1');
      expect(log().last, contains('・好聽'));
      final v2 = await a.addVersion(
        videoId: 'nv2',
        videoTitle: '另一部',
        thumbnailUrl: '',
        uploaderName: 'up',
        publishedAt: musicT,
        type: MusicVersionType.sing,
        artistIds: const ['band'],
        durationSec: 200,
        releaseYear: 2020,
      );
      expect(d().work(v2.workId)!.title, '另一部');
      expect(d().work(v2.workId)!.originalArtistIds, ['band']);
      expect(log().last, contains('（新歌曲）'));
      await a.addVersion(
        videoId: 'nv3',
        videoTitle: 'x',
        thumbnailUrl: '',
        uploaderName: 'up',
        publishedAt: musicT,
        workId: '不存在',
        newWorkTitle: ' 自訂歌名 ',
        originalArtistIds: const ['jay'],
        type: MusicVersionType.other,
        artistIds: const [],
      );
      expect(d().works.any((w) => w.title == '自訂歌名'), isTrue);

      // 改版本：找不到、沒改不動；每個欄位；年份清掉；只換歌也算。
      await a.editVersion('沒有', note: 'x');
      final n1 = log().length;
      await a.editVersion('v1', note: '', setYear: true, releaseYear: 2003);
      expect(log().length, n1);
      await a.editVersion(
        'v1',
        type: MusicVersionType.live,
        artistIds: const ['hana'],
        note: ' 新備註 ',
        setYear: true,
        releaseYear: 2004,
      );
      expect(
        log().last,
        allOf(contains('種類'), contains('誰唱'), contains('備註'), contains('發行年份')),
      );
      await a.editVersion('v1', setYear: true, releaseYear: null);
      expect(d().version('v1')!.releaseYear, isNull);
      await a.editVersion('v1', workId: 'w2');
      expect(d().version('v1')!.workId, 'w2');

      // 換歌名：空白、找不到、跟原本一樣都不動；新開一首；併到已有的；原本那首空了收起來。
      await a.moveVersionToTitle('v5', '  ');
      await a.moveVersionToTitle('沒有', 'x');
      await a.moveVersionToTitle('v5', '無名曲');
      await a.moveVersionToTitle('v5', '全新歌名');
      expect(d().work(d().version('v5')!.workId)!.title, '全新歌名');
      await a.moveVersionToTitle('v6', '全新歌名');
      expect(log().last, contains('併到已有的'));
      expect(d().workMap['w3']!.deletedAt, isNotNull);

      // 不喜歡：喜歡的順便拿掉；再按取消。
      expect(a.isLiked('v3'), isTrue);
      await a.toggleDislike('v3');
      expect(d().version('v3')!.disliked, isTrue);
      expect(a.isLiked('v3'), isFalse);
      await a.toggleDislike('v3');
      expect(d().version('v3')!.disliked, isFalse);
      await a.toggleDislike('v2');
      await a.toggleDislike('沒有');

      await a.toggleLike('v2');
      expect(log().last, contains('標成喜歡'));
      await a.toggleLike('v2');
      expect(log().last, contains('取消喜歡'));
      final pid = await a.createPlaylist(' 新歌單 ');
      await a.togglePlaylistItem(pid, 'v2');
      expect(log().last, contains('加進歌單「新歌單」'));
      await a.togglePlaylistItem(pid, 'v2');
      expect(log().last, contains('移出'));
      await a.togglePlaylistItem(pid, '不存在的版本');
      expect(log().last, contains('不存在的版本'));
      await a.togglePlaylistItem('沒有這個歌單', 'v2');
      await a.deletePlaylist(MusicPlaylist.likedId);
      await a.deletePlaylist('沒有');
      await a.deletePlaylist(pid);
      expect(d().playlistMap[pid]!.deletedAt, isNotNull);
    });
  });

  group('播放器', () {
    test('上一首、下一首、重複、隨機、下一首播放、拿掉、關掉', () {
      final started = <String>[];
      final p = MusicPlayer(onStart: (id, from) => started.add('$id/$from'));
      expect(p.current, isNull);
      p.toggle(); // 沒東西不會壞
      p.next();
      p.prev();
      p.playNext('a');
      expect(p.current, 'a');
      p.playList(['a', 'b', 'c'], 'b', from: '歌單');
      expect(p.current, 'b');
      p.toggle();
      expect(p.playing, isFalse);
      p.toggle();
      p.next();
      expect(p.current, 'c');
      expect(started.last, 'c/歌單・按下一首');
      // 自動接：到底、不重複就停。
      p.next(auto: true);
      expect(p.playing, isFalse);
      // 手動按下一首到底會回第一首。
      p.next();
      expect(p.current, 'a');
      p.cycleRepeat(); // 重複整份
      p.index = 2;
      p.next(auto: true);
      expect(p.current, 'a');
      p.cycleRepeat(); // 重複這首
      p.next(auto: true);
      expect(p.current, 'a');
      p.cycleRepeat();
      expect(p.repeat, 0);
      // 上一首：超過 3 秒回開頭。
      p.seek(10);
      p.prev();
      expect(p.position, 0);
      p.prev();
      expect(p.current, 'a');
      p.playNext('c');
      expect(p.queue, ['a', 'c', 'b']);
      p.toggleShuffle();
      p.playList(['a', 'b', 'c', 'd'], 'd');
      expect(p.current, 'd');
      p.toggleShuffle();
      p.shuffleAll(const []);
      p.shuffleAll(['x', 'y'], from: '隨機');
      expect(p.shuffle, isTrue);
      p.setExpanded(true);
      p.setShowVideo(false);
      expect(p.expanded && !p.showVideo, isTrue);
      // 從佇列拿掉：不在的不動、正在播的接下一首、拿到空就關掉。
      p.playList(['a', 'b'], 'a');
      p.removeFromQueue('zz');
      p.removeFromQueue('b');
      expect(p.queue, ['a']);
      p.playList(['a', 'b'], 'a');
      p.removeFromQueue('a');
      expect(p.current, 'b');
      p.removeFromQueue('b');
      expect(p.current, isNull);
      p.dispose();
    });

    test('YouTube 回報的狀態：時間、長度、播放／暫停、播完接下一首', () {
      final p = MusicPlayer();
      p.playList(['a', 'b'], 'a');
      var notified = 0;
      p.addListener(() => notified++);
      final on = p.bridge.onEvent;
      on(null, 0.2, null); // 差不到 0.5 秒不更新
      expect(notified, 0);
      on(null, 12, 200);
      expect(p.position, 12);
      expect(p.duration, 200);
      on(2, null, null);
      expect(p.playing, isFalse);
      on(1, null, null);
      expect(p.playing, isTrue);
      on(3, null, null); // 緩衝不改播放狀態
      on(5, null, 0); // 長度 0 不算
      on(0, null, null);
      expect(p.current, 'b');
      p.close();
      expect(p.queue, isEmpty);
    });
  });
}
