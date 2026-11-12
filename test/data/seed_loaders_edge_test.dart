import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/export/file_download_stub.dart' as dl;
import 'package:lume/data/notifications/notification_service_stub.dart' as ns;
import 'package:lume/data/notifications/test_notification_action.dart';
import 'package:lume/data/seed/app_defaults_loader.dart';
import 'package:lume/data/seed/diary_seed_loader.dart';
import 'package:lume/data/seed/fitness_seed_loader.dart';
import 'package:lume/data/seed/kana_exam_seed_loader.dart';
import 'package:lume/data/seed/kana_practice_seed_loader.dart';
import 'package:lume/data/seed/note_loader.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/data/storage/platform_store_stub.dart' as ps;
import 'package:lume/domain/models/usage_note.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打包進 App 的資料（快照、設定檔、用法筆記）讀取，跟沒有實作的平台（2026-11-12 使用者：
/// 每個功能都補到 95%、更多邊界）：檔案不存在／壞掉＝空的或預設值，不會炸；筆記 Markdown 每種語法。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 換掉打包的檔案：[files] 有的回內容，沒有的回 null（＝檔案不存在）。
  void fakeAssets(Map<String, String> files) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (msg) async {
          final key = utf8.decode(msg!.buffer.asUint8List());
          final s = files[Uri.decodeFull(key)];
          return s == null
              ? null
              : ByteData.sublistView(Uint8List.fromList(utf8.encode(s)));
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    rootBundle.clear();
  });

  test('快照檔不存在或壞掉：日記、健身、50 音練習／考試都回空的', () async {
    fakeAssets({'assets/data/diary.json': '壞掉'});
    expect(await loadDiarySeed(), isEmpty);
    expect(await loadFitnessSeed(), isEmpty);
    expect(await loadKanaExamSeed(), isEmpty);
    expect(await loadKanaPracticeSeed(), isEmpty);
  });

  test('快照檔是空清單：讀得到、0 筆', () async {
    fakeAssets({
      'assets/data/diary.json': '[]',
      'assets/data/fitness_entries.json': '[]',
      'assets/data/kana_exam.json': '[]',
      'assets/data/kana_practice.json': '[]',
    });
    expect(await loadDiarySeed(), isEmpty);
    expect(await loadFitnessSeed(), isEmpty);
    expect(await loadKanaExamSeed(), isEmpty);
    expect(await loadKanaPracticeSeed(), isEmpty);
  });

  test('設定檔壞掉：手寫 GIF、標籤順序用預設；R2 bucket 名稱讀不到就直接壞（不偷用舊的）', () async {
    fakeAssets({'assets/config/app_defaults.yaml': ': : 壞掉 ['});
    final gif = await loadKanaGifDefaults();
    expect(gif.size, const KanaGifDefaults().size);
    expect((await loadLibraryTagOrder()).adjacentGroups, isEmpty);
    await expectLater(loadR2BucketName(), throwsA(anything));
  });

  test('設定檔正常：手寫 GIF、標籤順序、bucket 名稱都讀得到', () async {
    fakeAssets({
      'assets/config/app_defaults.yaml': '''
kanaGifFrameIntervalMs: 40
kanaGifMaxFrames: 90
kanaGifSize: 256
kanaGifNumColors: 16
r2BucketName: my-bucket
libraryTagAdjacentGroups:
  - [a, b]
libraryTagTrailingOrder: [z]
''',
    });
    final gif = await loadKanaGifDefaults();
    expect(gif.frameIntervalMs, 40);
    expect(gif.maxFrames, 90);
    expect(gif.numColors, 16);
    expect(await loadR2BucketName(), 'my-bucket');
    final order = await loadLibraryTagOrder();
    expect(order.adjacentGroups, [
      ['a', 'b'],
    ]);
    expect(order.trailingOrder, ['z']);
  });

  test('用法筆記：標題、日期狀態、小標、段落、條列、表格、引言、相關單字；前言丟掉、--- 結束', () async {
    fakeAssets({
      'notes/test.md': '''
# 前言（丟掉）

## 001　說人胖不要用 fat
**日期：2026-01-01　狀態：已確認**

第一段
接著同一段

### 小標
- 條列一
- 條列二
| 中文 | 英文 |
|---|---|
| 胖 | chubby |

> 引言

相關單字：fat、chubby, plump
---
這行在分隔線後面，不算

## 002　只有表頭的表格
| a | b |
|---|---|

##
''',
    });
    final notes = await const NoteLoader('notes/test.md').load();
    expect(notes, hasLength(2));
    final n = notes.first;
    expect(n.no, '001');
    expect(n.title, '說人胖不要用 fat');
    expect(n.date, '2026-01-01');
    expect(n.status, '已確認');
    expect(n.relatedWords, ['fat', 'chubby', 'plump']);
    expect(n.blocks.whereType<NoteParagraph>().first.text, '第一段 接著同一段');
    expect(n.blocks.whereType<NoteHeading>().single.text, '小標');
    expect(n.blocks.whereType<NoteBullets>().single.items, ['條列一', '條列二']);
    final table = n.blocks.whereType<NoteTable>().single;
    expect(table.headers, ['中文', '英文']);
    expect(table.rows.single, ['胖', 'chubby']);
    expect(n.blocks.whereType<NoteQuote>().single.text, '引言');
    expect(
      n.blocks.whereType<NoteParagraph>().any((p) => p.text.contains('分隔線後面')),
      isFalse,
    );
    // 只有表頭沒有內容的表格不顯示。
    expect(notes[1].blocks.whereType<NoteTable>(), isEmpty);
  });

  test('沒有實作的平台：下載、分享、通知都回「做不到」；儲存空間不知道', () async {
    expect(dl.saveTextFile('a.txt', 'x'), isFalse);
    expect(
      dl.saveBytesFile('a.bin', const [1], 'application/octet-stream'),
      isFalse,
    );
    expect(await dl.shareOrSaveImage('a.png', const [1]), isFalse);
    expect(await ns.requestNotificationPermission(), isFalse);
    await ns.showTestNotification();
    final est = await ps.estimateStorage();
    expect(est.usage, isNull);
    expect(est.quota, isNull);
  });

  test('本機儲存（SharedPreferences）：存讀刪、列出全部只列文字', () async {
    SharedPreferences.setMockInitialValues({'n': 1, 's': 'x'});
    final s = await SharedPrefsStore.open();
    expect(await s.read('s'), 'x');
    await s.write('a', 'b');
    expect(await s.readAll(), {'s': 'x', 'a': 'b'});
    await s.remove('a');
    expect(await s.read('a'), isNull);
    final p = await ps.openPlatformStore();
    expect(await p.read('s'), 'x');
  });

  testWidgets('測試通知：沒權限（這個平台不支援）就提示去設定允許', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => testNotification(c),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('沒有通知權限'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
