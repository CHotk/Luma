import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/marquee_text.dart';

/// 2026-10-12 使用者要求：YT 頻道詳情頁標題太長要走馬燈。
Widget _host(String text) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 120,
        child: MarqueeText(text, style: const TextStyle(fontSize: 16)),
      ),
    ),
  ),
);

void main() {
  testWidgets('放得下：一般文字，不捲', (tester) async {
    await tester.pumpWidget(_host('短名'));
    await tester.pump();
    expect(find.text('短名'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('放不下：先停一下，再往左捲，循環', (tester) async {
    const name = '一個名字非常非常非常非常長的頻道名稱';
    await tester.pumpWidget(_host(name));
    await tester.pump();
    // 兩份接在一起捲。
    expect(find.text(name), findsNWidgets(2));
    final start = tester.getTopLeft(find.text(name).first).dx;

    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.getTopLeft(find.text(name).first).dx, start);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.getTopLeft(find.text(name).first).dx, lessThan(start));

    // 換成短名字就停。
    await tester.pumpWidget(_host('短名'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('短名'), findsOneWidget);
  });
}
