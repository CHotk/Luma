import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/yt_tracker/yt_floating_player.dart';

/// 浮動播放器（2026-11-12 補到 95%）：開、只能有一個、拖標題列（拖出畫面會夾住）、
/// 收合成泡泡、拖泡泡、點泡泡展開、在 YouTube 開（打不開會複製網址）、關閉、
/// 螢幕還沒排版（大小 0）時不會壞。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BuildContext ctx;

  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(390, 860),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: Text('底下的頁面'));
          },
        ),
      ),
    );
  }

  void open(String title) => YtFloatingPlayer.show(
    ctx,
    videoId: 'v1',
    title: title,
    watchUrl: 'https://youtu.be/v1',
  );

  testWidgets('開、只能有一個、拖、收合、拖泡泡、展開、關閉', (tester) async {
    await host(tester);
    open('第一支');
    await tester.pump();
    expect(find.text('第一支'), findsOneWidget);
    // 開第二支，第一支自己關掉。
    open('第二支');
    await tester.pump();
    expect(find.text('第一支'), findsNothing);
    expect(find.text('第二支'), findsOneWidget);
    expect(find.text('這個平台不支援內嵌播放'), findsOneWidget);
    // 底下的頁面還點得到（沒有擋觸控的遮罩）。
    expect(find.text('底下的頁面').hitTestable(), findsOneWidget);

    final before = tester.getTopLeft(find.text('第二支'));
    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded),
      const Offset(-40, -100),
    );
    await tester.pump();
    final after = tester.getTopLeft(find.text('第二支'));
    expect(after.dy, lessThan(before.dy));
    // 拖到畫面外面會被夾在畫面裡。
    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded),
      const Offset(-2000, -3000),
    );
    await tester.pump();
    final panel = tester.getTopLeft(find.byIcon(Icons.drag_indicator_rounded));
    expect(panel.dx, greaterThanOrEqualTo(0));
    expect(panel.dy, greaterThanOrEqualTo(0));

    await tester.tap(find.byTooltip('收合成小圖示'));
    await tester.pump();
    expect(find.byIcon(Icons.smart_display_rounded), findsOneWidget);
    await tester.drag(
      find.byIcon(Icons.smart_display_rounded),
      const Offset(3000, 3000),
    );
    await tester.pump();
    final bubble = tester.getBottomRight(
      find.byIcon(Icons.smart_display_rounded),
    );
    expect(bubble.dx, lessThanOrEqualTo(390));
    expect(bubble.dy, lessThanOrEqualTo(860));
    await tester.tap(find.byIcon(Icons.smart_display_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.smart_display_rounded), findsNothing);
    expect(find.text('第二支'), findsOneWidget);

    await tester.tap(find.byTooltip('關閉'));
    await tester.pump();
    expect(find.text('第二支'), findsNothing);
    // 已經關了再叫 close 不會壞。
    YtFloatingPlayer.close();
  });

  testWidgets('在 YouTube 開：這個平台開不了，網址複製到剪貼簿並說一聲', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await host(tester);
    open('影片');
    await tester.pump();
    await tester.tap(find.byTooltip('在 YouTube 開啟'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, 'https://youtu.be/v1');
    expect(find.textContaining('打不開連結'), findsOneWidget);
    YtFloatingPlayer.close();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('畫面比面板還小：位置夾在 0，不會丟例外', (tester) async {
    await host(tester, size: const Size(200, 150));
    open('小螢幕');
    await tester.pump();
    expect(tester.takeException(), isNull);
    YtFloatingPlayer.close();
    await tester.pump();
  });
}
