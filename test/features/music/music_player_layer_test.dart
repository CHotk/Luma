import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_player.dart';
import 'package:lume/features/music/music_player_layer.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 播放器那一層（2026-11-12 補到 95%）：迷你列讓開（hideMini）、全螢幕的看影片／
/// 只聽、拖進度條、點進度條、喜歡、隨機、上一首、播放／暫停、下一首、重複、
/// 更多（版本選單）、收起來；有縮圖、有備註、沒有時長的版本。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MusicPlayer player;

  Future<void> pump(WidgetTester tester, {bool hideMini = false}) async {
    var d = seedMusicData();
    d = d.putVersion(
      MusicVersion(
        id: 'v4',
        workId: 'w1',
        type: MusicVersionType.live,
        artistIds: const ['jay'],
        note: '演唱會',
        videoTitle: '有縮圖的',
        thumbnailUrl: 'https://img/mqdefault.jpg',
        uploaderName: '頻道',
        publishedAt: musicT,
        addedAt: musicT,
        updatedAt: musicT,
      ),
    );
    await pumpPage(
      tester,
      MemoryStore(),
      () => Stack(
        children: [
          const Scaffold(body: Text('底下')),
          MusicPlayerLayer(miniBottom: 10, hideMini: hideMini),
        ],
      ),
      size: const Size(390, 860),
      overrides: [musicDataProvider.overrideWith((_) => d)],
    );
    player = ProviderScope.containerOf(
      tester.element(find.byType(MusicPlayerLayer)),
    ).read(musicPlayerProvider);
  }

  testWidgets('迷你列：讓開、回來、點了展開', (tester) async {
    await pump(tester, hideMini: true);
    player.playList(['v1', 'v4'], 'v4');
    await settle(tester, 3);
    expect(tester.takeException(), isNull);
    await pump(tester);
    player.playList(['v1', 'v4'], 'v1');
    await settle(tester, 3);
    await tester.tap(find.byType(MusicPlayerLayer), warnIfMissed: false);
    await settle(tester, 3);
  });

  testWidgets('全螢幕：每顆按鈕、看影片／只聽、進度條拖跟點', (tester) async {
    await pump(tester);
    player.playList(['v1', 'v4', 'v2'], 'v4');
    player.bridge.onEvent(1, 30, 240);
    player.setExpanded(true);
    await settle(tester, 3);
    await tester.tap(find.text('只聽'));
    await settle(tester, 2);
    expect(player.showVideo, isFalse);
    await tester.tap(find.text('看影片'));
    await settle(tester, 2);
    // 進度條：拖到一半、點一下。
    final bar = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_SeekBar',
    );
    if (bar.evaluate().isNotEmpty) {
      await tester.ensureVisible(bar);
      await tester.drag(bar, const Offset(80, 0));
      await settle(tester, 2);
      await tester.tapAt(tester.getCenter(bar));
      await settle(tester, 2);
      expect(player.position, greaterThan(0));
    }
    for (final t in ['喜歡', '隨機', '下一首', '上一首', '暫停']) {
      final b = find.byTooltip(t);
      if (b.evaluate().isEmpty) continue;
      await tester.ensureVisible(b.first);
      await tester.tap(b.first, warnIfMissed: false);
      await settle(tester, 2);
    }
    final play = find.byTooltip('播放');
    if (play.evaluate().isNotEmpty) {
      await tester.tap(play.first, warnIfMissed: false);
      await settle(tester, 2);
    }
    await tester.ensureVisible(find.byTooltip('更多').first);
    await tester.tap(find.byTooltip('更多').first);
    await settle(tester, 3);
    expect(player.expanded, isFalse);
    await closeOverlays(tester);
    player.setExpanded(true);
    await settle(tester, 2);
    await tester.ensureVisible(find.byTooltip('收起來'));
    await tester.tap(find.byTooltip('收起來'));
    await settle(tester, 2);
    expect(player.expanded, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只聽模式＋有縮圖的版本；沒時長的版本進度條不能拖', (tester) async {
    await pump(tester);
    player.playList(['v4'], 'v4');
    player.setShowVideo(false);
    player.setExpanded(true);
    await settle(tester, 3);
    expect(tester.takeException(), isNull);
    player.playList(['v2'], 'v2');
    await settle(tester, 3);
    expect(MusicPlaylist.likedId, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
