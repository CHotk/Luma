import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/inline_empty_card.dart';

void main() {
  testWidgets('空狀態卡片：顯示標題、原因，快速動作按得到', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineEmptyCard(
            title: '這裡空空的',
            message: '46 部已看過的被收起來了',
            actions: [EmptyAction('顯示已看過', () => tapped++)],
          ),
        ),
      ),
    );

    expect(find.text('這裡空空的'), findsOneWidget);
    expect(find.text('46 部已看過的被收起來了'), findsOneWidget);
    await tester.tap(find.text('顯示已看過'));
    expect(tapped, 1);
  });
}
