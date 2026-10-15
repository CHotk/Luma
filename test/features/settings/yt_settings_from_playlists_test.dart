import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/settings/all_settings_page.dart';
import 'package:lume/features/settings/other_settings_page.dart';

/// 2026-10-14 使用者回報：播放清單頁的齒輪跑到首頁的設定；YT 設定裡也
/// 找不到「影片」要開哪個頻道。2026-10-15 設定併成一頁：從哪個功能進來
/// 就先跳到那段、分頁籤亮那格；搜尋找得到設定、點了跳過去。
void main() {
  Future<void> pump(WidgetTester tester, String from) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: MaterialApp(home: AllSettingsPage(fromLocation: from)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  bool onScreen(WidgetTester tester, Finder f) {
    final r = tester.getRect(f.first);
    return r.top >= 0 && r.top < 900;
  }

  testWidgets('從播放清單開設定：直接跳到 YT 那段，底部分頁列就在上面', (tester) async {
    await pump(tester, '/yt-playlists');
    expect(onScreen(tester, find.byType(YtSettingsSection)), isTrue);
    expect(find.text('底部分頁列「影片」開的頻道'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('哪個功能對到哪段', () {
    expect(settingsSectionFor('/yt-tracker/browse'), SettingsSection.yt);
    expect(settingsSectionFor('/kana-practice'), SettingsSection.jp);
    expect(settingsSectionFor('/crypto-watch'), SettingsSection.trade);
    expect(settingsSectionFor('/debt'), SettingsSection.lock);
    expect(settingsSectionFor('/start'), SettingsSection.app);
    expect(settingsSectionFor('/home'), SettingsSection.english);
    expect(settingsSectionFor(null), SettingsSection.english);
  });

  testWidgets('搜尋「冷藏」列出結果，點了跳回清單', (tester) async {
    await pump(tester, '/start');
    await tester.enterText(find.byType(TextField).first, '冷藏');
    await tester.pump();
    expect(find.text('找到 1 項，點了跳過去'), findsOneWidget);
    await tester.tap(find.text('依影片顯示也抓冷藏頻道'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(onScreen(tester, find.text('依影片顯示也抓冷藏頻道')), isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('不是從日記／負債進來，改密碼要先輸入舊密碼', (tester) async {
    await pump(tester, '/start');
    await tester.enterText(find.byType(TextField).first, '密碼');
    await tester.pump();
    await tester.tap(find.text('日記／負債密碼'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('變更'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('先輸入目前的密碼'), findsOneWidget);
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}
