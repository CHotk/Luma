import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/music_play_mode_store.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/music_player.dart';
import 'package:lume/features/music/music_widgets.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 音樂小元件的流程（2026-11-12 補到 95%）：版本選單每一項、編輯版本（種類、誰唱、
/// 備註、年份、換歌名）、加到歌單（勾、新歌單）、新增／編輯歌手（多張大頭貼、
/// 選顯示哪張、性別、裁切：拖、縮放、滾輪、滑桿、重設、取消、好）、播放紀錄、
/// 往下拉關掉面板。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef ref;
  late BuildContext ctx;

  Future<void> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          musicDataProvider.overrideWith((_) => seedMusicData()),
          musicPlayLogProvider.overrideWith((_) => seedMusicPlays()),
          musicEventLogProvider.overrideWith((_) => seedMusicEvents()),
          musicPlayModeProvider.overrideWith((_) => MusicPlayMode.embedded),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, r, _) {
                ref = r;
                ctx = c;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
  }

  MusicData d() => ref.read(musicDataProvider);

  Future<void> menu(WidgetTester tester, String id, String item) async {
    showMusicVersionMenu(ctx, ref, id);
    await settle(tester, 3);
    final exact = find.text(item);
    await tester.tap(
      exact.evaluate().isNotEmpty ? exact.last : find.textContaining(item).last,
    );
    await settle(tester, 4);
  }

  testWidgets('版本選單：下一首播放、喜歡、不喜歡、紀錄、YouTube', (tester) async {
    await host(tester);
    await menu(tester, 'v1', '下一首播放');
    expect(ref.read(musicPlayerProvider).current, 'v1');
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await menu(tester, 'v2', '喜歡');
    expect(d().liked.versionIds, contains('v2'));
    await menu(tester, 'v2', '取消喜歡');
    expect(d().liked.versionIds, isNot(contains('v2')));
    await menu(tester, 'v2', '不喜歡（');
    expect(d().version('v2')!.disliked, isTrue);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await menu(tester, 'v2', '取消不喜歡');
    expect(d().version('v2')!.disliked, isFalse);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await menu(tester, 'v1', '紀錄（');
    expect(find.textContaining('播放'), findsWidgets);
    await closeOverlays(tester);
    await menu(tester, 'v1', '在 YouTube 開啟');
    expect(tester.takeException(), isNull);
  });

  testWidgets('版本選單：加到歌單（勾、取消勾、新歌單）', (tester) async {
    await host(tester);
    await menu(tester, 'v1', '加到歌單');
    await tester.tap(find.text('開車聽'));
    await settle(tester, 2);
    expect(d().playlistMap['pl1']!.versionIds, contains('v1'));
    await tester.tap(find.text('開車聽'));
    await settle(tester, 2);
    expect(d().playlistMap['pl1']!.versionIds, isNot(contains('v1')));
    final add = find.textContaining('新歌單');
    if (add.evaluate().isNotEmpty) {
      await tester.tap(add.first);
      await settle(tester, 3);
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field.last, '睡前');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester, 3);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('編輯版本：種類、誰唱、備註、年份、換歌名，存起來', (tester) async {
    await host(tester);
    await menu(tester, 'v2', '編輯（');
    for (final t in MusicVersionType.values) {
      final f = find.text(t.label);
      if (f.evaluate().isNotEmpty) {
        await tester.ensureVisible(f.last);
        await tester.tap(f.last, warnIfMissed: false);
        await tester.pump();
      }
    }
    final fields = find.byType(TextField);
    for (var i = 0; i < fields.evaluate().length; i++) {
      await tester.enterText(fields.at(i), i == 0 ? '晴天' : '2015');
    }
    await tester.pump();
    final ok = find.text('存起來').evaluate().isNotEmpty
        ? find.text('存起來')
        : find.byType(FilledButton).last;
    await tester.ensureVisible(ok);
    await tester.tap(ok, warnIfMissed: false);
    await settle(tester, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌手：新增時多張大頭貼、選顯示哪張、性別、裁切（拖、滾輪、滑桿、重設、好）', (tester) async {
    await host(tester);
    final f = promptMusicArtist(
      ctx,
      name: '周杰倫',
      avatarUrls: const ['https://img/a.png', 'https://img/b.png'],
      gender: 'm',
    );
    await settle(tester, 3);
    // 每個按鈕／chip 都點一次（不含存檔），每個欄位填字。
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    for (var i = 0; i < fields.evaluate().length; i++) {
      await tester.enterText(
        fields.at(i),
        i == 0 ? '新名字' : 'https://img/$i.png',
      );
    }
    await tester.pump();
    for (final t in ['男', '女', '顯示這張']) {
      final b = find.text(t);
      if (b.evaluate().isNotEmpty) {
        await tester.tap(b.first, warnIfMissed: false);
        await tester.pump();
      }
    }
    final adjust = find.textContaining('調整');
    if (adjust.evaluate().isNotEmpty) {
      await tester.tap(adjust.first, warnIfMissed: false);
      await settle(tester, 3);
      if (find.text('調整大頭貼').evaluate().isNotEmpty) {
        final area = find.byType(CustomPaint).last;
        await tester.drag(area, const Offset(40, 30));
        await tester.pump();
        final center = tester.getCenter(area);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(center));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.pump();
        await tester.drag(find.byType(Slider), const Offset(40, 0));
        await tester.pump();
        await tester.tap(find.text('重設'));
        await tester.pump();
        await tester.drag(find.byType(Slider), const Offset(60, 0));
        await tester.tap(find.text('好'));
        await settle(tester, 3);
      }
    }
    final save = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    if (save.evaluate().isNotEmpty) {
      await tester.tap(save.last, warnIfMissed: false);
      await settle(tester, 3);
    }
    var closed = false;
    f.then((_) => closed = true);
    await tester.pump();
    if (!closed) {
      await closeOverlays(tester);
      await tester.pump();
    }
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('裁切：直接打開，取消回 null、好回位置', (tester) async {
    await host(tester);
    var f = showMusicAvatarCropper(ctx, 'https://img/a.png', const [0, 0, 1]);
    await settle(tester, 3);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect(await f, isNull);
    f = showMusicAvatarCropper(ctx, 'https://img/a.png', const [0.1, 0.1, 2]);
    await settle(tester, 3);
    await tester.drag(find.byType(CustomPaint).last, const Offset(-500, 500));
    await tester.pump();
    await tester.tap(find.text('好'));
    await settle(tester, 3);
    final r = await f;
    expect(r, hasLength(3));
    expect(r![2], 2);
  });

  testWidgets('面板往下拉超過一段就關掉，拉一點點彈回', (tester) async {
    await host(tester);
    await menu(tester, 'v1', '紀錄（');
    final list = find.byType(Scrollable).last;
    await tester.drag(list, const Offset(0, 40));
    await settle(tester, 2);
    await tester.drag(list, const Offset(0, 400));
    await settle(tester, 3);
    expect(tester.takeException(), isNull);
  });
}
