import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/settings/debug_log_page.dart';

import '../../support/poke.dart';

/// 除錯紀錄頁右上角七顆按鈕（2026-11-12 補測試時發現）：手機寬度 360／390／420 都不能超出
/// 畫面（原本 390 寬超出 26px、360 寬超出 56px）；頁面自己的五顆至少 32×36 還點得到。
void main() {
  for (final w in [360.0, 390.0, 420.0]) {
    testWidgets('寬 $w：頂列不超出畫面', (tester) async {
      await pumpPage(
        tester,
        MemoryStore(),
        () => const DebugLogPage(),
        size: Size(w, 900),
      );
      expect(tester.takeException(), isNull);
      for (final tip in ['新增測試訊息', '測試通知', '複製全部']) {
        final b = find.byWidgetPredicate(
          (x) => x is IconButton && x.tooltip == tip,
        );
        final size = tester.getSize(b);
        expect(size.width, greaterThanOrEqualTo(32), reason: tip);
        expect(size.height, greaterThanOrEqualTo(36), reason: tip);
      }
    });
  }
}
