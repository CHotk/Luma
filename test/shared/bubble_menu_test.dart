import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/bubble_menu.dart';

void main() {
  Future<String?> open(WidgetTester tester, {required double cardTop}) async {
    String? picked = 'unset';
    final cardKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: cardTop,
                left: 40,
                child: SizedBox(key: cardKey, width: 200, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    final ctx = cardKey.currentContext!;
    showBubbleMenu<String>(
      ctx,
      anchor: bubbleAnchorOf(ctx),
      items: const [
        BubbleMenuItem(
          value: 'del',
          icon: Icons.delete,
          label: '刪除',
          destructive: true,
        ),
        BubbleMenuItem(value: 'pin', icon: Icons.push_pin, label: '置頂'),
      ],
    ).then((v) => picked = v);
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('泡泡選單：刪除排最右邊、預設浮在卡片上方，點了回傳該動作', (tester) async {
    await open(tester, cardTop: 300);
    final pin = tester.getCenter(find.text('置頂'));
    final del = tester.getCenter(find.text('刪除'));
    expect(del.dx, greaterThan(pin.dx));
    expect(pin.dy, lessThan(300));

    String? picked;
    // 重新開一次並接住回傳值。
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    final cardKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 300,
                left: 40,
                child: SizedBox(key: cardKey, width: 200, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    final ctx = cardKey.currentContext!;
    showBubbleMenu<String>(
      ctx,
      anchor: bubbleAnchorOf(ctx),
      items: const [
        BubbleMenuItem(value: 'pin', icon: Icons.push_pin, label: '置頂'),
      ],
    ).then((v) => picked = v);
    await tester.pumpAndSettle();
    await tester.tap(find.text('置頂'));
    await tester.pumpAndSettle();
    expect(picked, 'pin');
  });

  testWidgets('泡泡選單：卡片在最上面、上方放不下時改放卡片下方', (tester) async {
    await open(tester, cardTop: 10);
    expect(tester.getCenter(find.text('置頂')).dy, greaterThan(70));
  });
}
