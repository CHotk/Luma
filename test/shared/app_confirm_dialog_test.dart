import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/app_confirm_dialog.dart';

void main() {
  testWidgets('確認對話框：按確認回傳 true、按取消回傳 false', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showAppConfirmDialog(
                context,
                title: '刪除這筆紀錄？',
                message: '刪除後無法復原。',
                confirmLabel: '刪除',
              ),
            ),
            child: const Text('開'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    expect(find.text('刪除這筆紀錄？'), findsOneWidget);
    expect(find.text('刪除後無法復原。'), findsOneWidget);
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(results, [true, false]);
  });
}
