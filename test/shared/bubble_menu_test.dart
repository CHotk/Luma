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

  // 2026-10-06 使用者要求：長按跳出選單後，手指不放開直接滑過去選。
  Future<List<String?>> pumpLongPressCard(WidgetTester tester) async {
    final picked = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 300,
                left: 40,
                child: Builder(
                  builder: (context) => BubbleLongPress(
                    onLongPress: (anchor, drag) => showBubbleMenu<String>(
                      context,
                      anchor: anchor,
                      drag: drag,
                      items: const [
                        BubbleMenuItem(
                          value: 'pin',
                          icon: Icons.push_pin,
                          label: '置頂',
                        ),
                        BubbleMenuItem(
                          value: 'cold',
                          icon: Icons.ac_unit,
                          label: '冷藏',
                        ),
                      ],
                    ).then(picked.add),
                    child: Container(
                      key: const Key('card'),
                      width: 200,
                      height: 60,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('長按不放、滑到按鈕上放開就選那一個', (tester) async {
    final picked = await pumpLongPressCard(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('card'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final target = tester.getCenter(find.text('冷藏'));
    await gesture.moveTo(target - const Offset(0, 40));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    // 滑到的那顆放大（Q 彈），其他維持原大小。
    final scales = tester
        .widgetList<AnimatedScale>(find.byType(AnimatedScale))
        .map((w) => w.scale)
        .toList();
    expect(scales.where((s) => s > 1).length, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, ['cold']);
    expect(find.text('冷藏'), findsNothing);
  });

  testWidgets('拖過去但沒指到按鈕就放開，選單收掉、不選任何一個', (tester) async {
    final picked = await pumpLongPressCard(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('card'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, [null]);
    expect(find.text('置頂'), findsNothing);
  });

  testWidgets('長按後在原地放開，選單留著，之後點一下就選', (tester) async {
    final picked = await pumpLongPressCard(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('card'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('置頂'), findsOneWidget);

    await tester.tap(find.text('置頂'));
    await tester.pumpAndSettle();
    expect(picked, ['pin']);
  });

  testWidgets('泡泡選單：卡片在最上面、上方放不下時改放卡片下方', (tester) async {
    await open(tester, cardTop: 10);
    expect(tester.getCenter(find.text('置頂')).dy, greaterThan(70));
  });
}
