import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/kana_practice_repository.dart';
import 'package:lume/domain/models/kana_practice.dart';
import 'package:lume/features/kana_practice/gojuon_data.dart';
import 'package:lume/features/kana_practice/kana_practice_history_page.dart';
import 'package:lume/features/kana_practice/kana_paper.dart';
import 'package:lume/features/kana_practice/kana_practice_page.dart';

import '../../support/poke.dart';

/// 50 音手寫練習（2026-11-13 第 15 項）：
/// - 練習頁：畫一筆放手就存、同一個字一直是同一筆紀錄、第二根手指不算、pointercancel
///   也存；清除重寫連存過的一起丟（沒寫過按清除不會壞）；切片假名留在同一行同一個字；
///   換行、換字、切純手寫都是新的一筆；從首頁帶起始選擇進來；開紀錄頁前等存完。
/// - 紀錄頁：沒紀錄、來源數量、平／片假名 × 輔助／純手寫篩選（含篩完沒有）、點一筆重播
///   （重播、下載 GIF、匯出 PNG、匯入的圖片沒有筆畫）、匯出（切快照、下載、複製、關閉）、
///   匯入圖片（取消選圖、沒填假名不能存、取消、存進紀錄）、練習頁存檔後紀錄頁自動重整。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  /// 1x1 透明 PNG。
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('lume_kana_'));
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 選照片回傳 [pickPath]；存檔存到暫存資料夾；剪貼簿什麼都不做。
  String? pickPath;
  final saved = <String>[];
  void mockPlatform(WidgetTester tester) {
    kanaSaveFile =
        ({
          required name,
          required bytes,
          required ext,
          required mimeType,
        }) async => saved.add('$name.$ext:${bytes.length}');
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => pickPath,
    );
    addTearDown(() {
      for (final c in [
        SystemChannels.platform,
        const MethodChannel('plugins.flutter.io/image_picker'),
      ]) {
        m.setMockMethodCallHandler(c, null);
      }
    });
  }

  /// 真的事件迴圈跑一陣子（畫 PNG／GIF、寫檔要用到）。
  Future<void> realWork(WidgetTester tester, [int rounds = 30]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<List<KanaPracticeEntry>> entries(
    WidgetTester tester,
    MemoryStore s,
  ) async =>
      (await tester.runAsync(() => KanaPracticeRepository(s).loadAll()))!;

  Finder paper() => find
      .ancestor(
        of: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is InkPainter,
        ),
        matching: find.byType(Listener),
      )
      .first;

  /// 在紙上畫一筆：從左上往右下拖。
  Future<void> stroke(WidgetTester tester, {int pointer = 1}) async {
    final c = tester.getCenter(paper());
    final g = await tester.startGesture(
      c - const Offset(40, 40),
      pointer: pointer,
    );
    await g.moveBy(const Offset(30, 30));
    await g.moveBy(const Offset(30, 30));
    await g.up();
    await settle(tester, 3);
  }

  Future<void> openPractice(
    WidgetTester tester,
    MemoryStore store, {
    KanaPracticeInitial? initial,
  }) async {
    mockPlatform(tester);
    await pumpPage(
      tester,
      store,
      () => KanaPracticePage(initial: initial),
      size: const Size(390, 860),
    );
    await settle(tester, 3);
  }

  testWidgets('畫兩筆：放手就存，同一個字一直是同一筆；第二根手指不算；pointercancel 也存', (tester) async {
    final store = MemoryStore();
    await openPractice(tester, store);
    await stroke(tester);
    var all = await entries(tester, store);
    expect(all.single.kana, 'あ');
    expect(all.single.assisted, isTrue);
    expect(all.single.strokes.single.length, 3);

    // 第一根手指畫的時候第二根手指落下：忽略。
    final c = tester.getCenter(paper());
    final a = await tester.startGesture(c, pointer: 7);
    final b = await tester.startGesture(c + const Offset(20, 0), pointer: 8);
    await b.moveBy(const Offset(10, 10));
    await a.moveBy(const Offset(5, 30));
    await b.up();
    await a.cancel();
    await settle(tester, 3);
    all = await entries(tester, store);
    expect(all.length, 1);
    expect(all.single.strokes.length, 2);
    expect(all.single.strokes[1].length, 2);
  });

  testWidgets('清除重寫：連存過的一起刪；沒寫過按清除不會壞', (tester) async {
    final store = MemoryStore();
    await openPractice(tester, store);
    await tester.tap(find.text('清除重寫'));
    await settle(tester, 3);
    await stroke(tester);
    expect((await entries(tester, store)).length, 1);
    await tester.tap(find.text('清除重寫'));
    await settle(tester, 3);
    expect(await entries(tester, store), isEmpty);
  });

  testWidgets('切片假名留在同一行同一個字；換行、換字、純手寫都是新的一筆', (tester) async {
    final store = MemoryStore();
    await openPractice(tester, store);
    await tester.tap(find.text('か'));
    await settle(tester, 2);
    await tester.tap(find.text('く'));
    await settle(tester, 2);
    await stroke(tester);
    await tester.tap(find.text('片假名'));
    await settle(tester, 2);
    expect(find.text('ク'), findsWidgets);
    // 再點一次片假名不動。
    await tester.tap(find.text('片假名'));
    await settle(tester, 2);
    await stroke(tester);
    await tester.tap(find.text('純手寫'));
    await settle(tester, 2);
    await stroke(tester);
    await tester.tap(find.text('ケ'));
    await settle(tester, 2);
    await stroke(tester);
    final all = await entries(tester, store);
    expect(all.map((e) => e.kana).toSet(), {'く', 'ク', 'ケ'});
    expect(all.length, 4);
    expect(all.where((e) => !e.assisted).length, 2);
    // 切回平假名。
    await tester.tap(find.text('平假名'));
    await settle(tester, 2);
    expect(find.text('け'), findsWidgets);
  });

  testWidgets('從首頁帶起始選擇進來：片假名さ行ス；按紀錄等存完才開', (tester) async {
    final store = MemoryStore();
    await openPractice(
      tester,
      store,
      initial: const KanaPracticeInitial(
        script: KanaScript.katakana,
        row: 'さ',
        kana: ('ス', 'su'),
      ),
    );
    expect(find.text('su'), findsOneWidget);
    await stroke(tester);
    await tester.tap(find.byTooltip('練習紀錄'));
    await settle(tester, 4);
    expect(find.text('route:/kana-practice/history'), findsOneWidget);
    expect((await entries(tester, store)).single.kana, 'ス');
  });

  // ── 紀錄頁 ─────────────────────────────────────────────

  Future<MemoryStore> seed(WidgetTester tester) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = KanaPracticeRepository(store);
      KanaPracticeEntry e(
        String id,
        String kana,
        bool assisted, {
        bool image = false,
      }) => KanaPracticeEntry(
        id: id,
        kana: kana,
        romaji: 'x',
        assisted: assisted,
        savedAt: DateTime(2026, 10, 1, 8, int.parse(id)),
        imageBase64: image ? base64Encode(png) : null,
        strokes: image
            ? const []
            : const [
                [(0.1, 0.1, 0.0), (0.5, 0.5, 30.0)],
                [(0.6, 0.2, 40.0), (0.7, 0.8, 60.0)],
              ],
      );
      await repo.add(e('1', 'あ', true));
      await repo.add(e('2', 'い', false));
      await repo.add(e('3', 'カ', true));
      await repo.add(e('4', 'キ', false, image: true));
    });
    return store;
  }

  Future<void> openHistory(WidgetTester tester, MemoryStore store) async {
    mockPlatform(tester);
    await pumpPage(
      tester,
      store,
      () => const KanaPracticeHistoryPage(),
      size: const Size(390, 1200),
    );
    await settle(tester, 4);
  }

  testWidgets('紀錄頁沒紀錄', (tester) async {
    await openHistory(tester, MemoryStore());
    expect(find.text('還沒有任何練習紀錄'), findsOneWidget);
  });

  testWidgets('紀錄頁：來源數量、平／片假名 × 輔助／純手寫篩選、篩完沒有', (tester) async {
    await openHistory(tester, await seed(tester));
    expect(find.textContaining('這台瀏覽器'), findsOneWidget);
    expect(find.text('符合條件 4 / 4 筆'), findsOneWidget);
    Future<void> chip(String label, {int at = 0}) async {
      await tester.tap(find.textContaining(label).at(at));
      await settle(tester, 2);
    }

    await chip('平假名');
    expect(find.text('符合條件 2 / 4 筆'), findsOneWidget);
    await chip('純手寫');
    expect(find.text('符合條件 1 / 4 筆'), findsOneWidget);
    await chip('片假名');
    expect(find.text('符合條件 1 / 4 筆'), findsOneWidget);
    await chip('輔助描摹');
    expect(find.text('符合條件 1 / 4 筆'), findsOneWidget);
    await chip('全部', at: 1);
    expect(find.text('符合條件 2 / 4 筆'), findsOneWidget);
    await chip('全部');
    expect(find.text('符合條件 4 / 4 筆'), findsOneWidget);
  });

  testWidgets('紀錄頁：篩完一筆都沒有', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(
      () => KanaPracticeRepository(store).add(
        KanaPracticeEntry(
          id: '1',
          kana: 'あ',
          romaji: 'a',
          assisted: true,
          savedAt: DateTime(2026, 10, 1),
          strokes: const [],
        ),
      ),
    );
    await openHistory(tester, store);
    await tester.tap(find.textContaining('片假名'));
    await settle(tester, 2);
    expect(find.text('沒有符合篩選條件的紀錄'), findsOneWidget);
  });

  testWidgets('點一筆重播：重播、下載 GIF、匯出圖片、關閉', (tester) async {
    saved.clear();
    await openHistory(tester, await seed(tester));
    await tester.tap(find.text('あ'));
    await settle(tester, 3);
    expect(find.text('あ（x）'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('重播'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('下載該次筆跡'));
    await tester.pump();
    await realWork(tester, 60);
    expect(find.text('下載該次筆跡'), findsOneWidget);
    await tester.tap(find.text('匯出圖片'));
    await realWork(tester, 30);
    expect(
      saved.where((f) => f.startsWith('20261001_0801_あ_x.gif')),
      hasLength(1),
    );
    expect(
      saved.where((f) => f.startsWith('20261001_0801_あ_x.png')),
      hasLength(1),
    );
    await tester.tap(find.text('關閉'));
    await settle(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('點匯入的圖片：沒有筆畫可以重播、只能匯出圖片', (tester) async {
    await openHistory(tester, await seed(tester));
    await tester.tap(find.text('キ'));
    await settle(tester, 3);
    expect(find.text('這張是匯入的圖片，沒有筆畫紀錄可以重播'), findsOneWidget);
    expect(find.text('重播'), findsNothing);
    saved.clear();
    await tester.tap(find.text('匯出圖片'));
    await realWork(tester, 10);
    // 匯入的圖片直接存原檔（70 bytes 的那張 PNG）。
    expect(saved, ['20261001_0804_キ_x.png:${png.length}']);
    await tester.tap(find.text('關閉'));
    await settle(tester, 2);
  });

  testWidgets('匯出：切快照、下載、複製、關閉', (tester) async {
    await openHistory(tester, await seed(tester));
    await tester.tap(find.byTooltip('匯出紀錄'));
    await settle(tester, 4);
    expect(find.textContaining('共 4 筆 ・'), findsOneWidget);
    await tester.tap(find.text('連手寫紀錄快照一起'));
    await settle(tester, 4);
    await tester.tap(find.text('連手寫紀錄快照一起'));
    await settle(tester, 2);
    expect(find.textContaining('共 4 筆 ・'), findsOneWidget);
    await tester.tap(find.text('下載'));
    await settle(tester, 3);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('複製'));
    await settle(tester, 3);
    expect(find.text('已複製到剪貼簿'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('關閉'));
    await settle(tester, 2);
  });

  testWidgets('匯入圖片：不選、沒填假名不能存、取消、存進紀錄', (tester) async {
    final store = await seed(tester);
    await openHistory(tester, store);
    pickPath = null;
    await tester.tap(find.byTooltip('匯入既有圖片'));
    await realWork(tester, 4);
    expect(find.text('匯入這張圖片'), findsNothing);

    final f = File('${tmp.path}/pick.png')..writeAsBytesSync(png);
    pickPath = f.path;
    await tester.tap(find.byTooltip('匯入既有圖片'));
    await realWork(tester, 6);
    expect(find.text('匯入這張圖片'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect(find.text('匯入這張圖片'), findsNothing);

    await tester.tap(find.byTooltip('匯入既有圖片'));
    await realWork(tester, 6);
    await tester.tap(find.text('存進紀錄'));
    await settle(tester, 2);
    expect(find.text('匯入這張圖片'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, ' ぬ ');
    await tester.enterText(find.byType(TextField).last, 'nu');
    await tester.tap(find.byType(Switch));
    await settle(tester, 2);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 4);
    final all = await entries(tester, store);
    final nu = all.firstWhere((e) => e.kana == 'ぬ');
    expect(nu.romaji, 'nu');
    expect(nu.assisted, isTrue);
    expect(nu.imageBase64, isNotNull);
    expect(find.text('符合條件 5 / 5 筆'), findsOneWidget);
  });
}
