import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_channel_avatar.dart';
import 'package:lume/features/yt_tracker/yt_channel_edit_header.dart';

/// 頻道頁「編輯中」頭部（2026-11-12 補到 95%）：改名（顯示原本名字、點了改回）、
/// 名稱清空顯示（沒有名稱）、分類展開選、未分類、網址輸入（貼上、剪貼簿空的／讀不到）、
/// Enter 收起、外面還原輸入框跟著變、頭像交給頁面；頭像有圖片網址時載入失敗退回 emoji。
void main() {
  final cats = [
    const YtCategory(id: 'c1', name: '投資', colorValue: 0xFF5FC9A8),
    const YtCategory(id: 'c2', name: '音樂', colorValue: 0xFFE07A7A),
  ];
  final base = YtChannel(
    id: 'a',
    name: '原本',
    categoryId: 'c1',
    youtubeChannelId: 'UCa',
    url: 'https://www.youtube.com/@a',
    addedAt: DateTime(2026),
    subscriberCount: 12000,
  );

  late YtChannel draft;
  late StateSetter setOuter;
  var avatarTaps = 0;

  Future<void> pump(WidgetTester tester, {Object? clipboard}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          if (clipboard is Exception) throw clipboard;
          return clipboard == null ? null : {'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    draft = base;
    avatarTaps = 0;
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) {
              setOuter = set;
              return YtChannelEditHeader(
                draft: draft,
                base: base,
                categories: cats,
                originalName: '最早的名字',
                onChanged: (c) => set(() => draft = c),
                onTapAvatar: () => avatarTaps++,
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('改名：顯示原本的名字、點了改回、清空顯示沒有名稱、按好收起', (tester) async {
    await pump(tester);
    await tester.tap(find.text('原本'));
    await tester.pump();
    expect(find.text('（原本：最早的名字）'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '新名字');
    await tester.pump();
    expect(draft.name, '新名字');
    await tester.tap(find.text('（原本：最早的名字）'));
    await tester.pump();
    expect(draft.name, '最早的名字');
    // 跟原本一樣就不用再顯示那顆。
    expect(find.text('（原本：最早的名字）'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('好'));
    await tester.pump();
    expect(find.text('（沒有名稱）'), findsOneWidget);
    // 點同一個再點一次是收起來。
    await tester.tap(find.text('（沒有名稱）'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('外面按還原：輸入框跟著變回去', (tester) async {
    await pump(tester);
    await tester.tap(find.text('原本'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '改了');
    await tester.pump();
    setOuter(() => draft = base);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '原本',
    );
  });

  testWidgets('分類：展開、選音樂、選未分類、再點收起', (tester) async {
    await pump(tester);
    await tester.tap(find.text('● 投資'));
    await tester.pump();
    await tester.tap(find.text('音樂'));
    await tester.pump();
    expect(draft.categoryId, 'c2');
    expect(find.text('● 音樂'), findsOneWidget);
    await tester.tap(find.text('● 音樂'));
    await tester.pump();
    await tester.tap(find.text('未分類'));
    await tester.pump();
    expect(draft.categoryId, isNull);
    expect(find.text('● 未分類'), findsOneWidget);
    await tester.tap(find.text('● 未分類'));
    await tester.pump();
    await tester.tap(find.text('● 未分類'));
    await tester.pump();
    expect(find.text('投資'), findsNothing);
  });

  testWidgets('網址：打字、貼上、Enter 收起；清空顯示加網址', (tester) async {
    await pump(tester, clipboard: '  https://www.youtube.com/@pasted  ');
    await tester.tap(find.text('https://www.youtube.com/@a'));
    await tester.pump();
    await tester.tap(find.byTooltip('貼上'));
    await tester.pump();
    expect(draft.url, 'https://www.youtube.com/@pasted');
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(draft.url, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('＋ 加頻道網址'), findsOneWidget);
  });

  for (final clip in <Object?>[null, '   ', PlatformException(code: 'x')]) {
    testWidgets('貼上時剪貼簿是「$clip」：網址不變', (tester) async {
      await pump(tester, clipboard: clip);
      await tester.tap(find.text('https://www.youtube.com/@a'));
      await tester.pump();
      await tester.tap(find.byTooltip('貼上'));
      await tester.pump();
      expect(draft.url, base.url);
    });
  }

  testWidgets('頭像：點了交給頁面、正在改的欄位收起', (tester) async {
    await pump(tester);
    await tester.tap(find.text('原本'));
    await tester.pump();
    await tester.tap(find.byType(YtChannelAvatar));
    await tester.pump();
    expect(avatarTaps, 1);
    expect(find.byType(TextField), findsNothing);
    // 改過的欄位：頭像網址不一樣也畫得出來（實線）。
    setOuter(() => draft = base.copyWith(avatarImageUrl: 'https://x/y.png'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 測試環境載不到圖，退回 emoji，不會噴錯。
    expect(find.text(base.avatarEmoji), findsWidgets);
    tester.takeException();
  });
}
