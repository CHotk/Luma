import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/tally_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/tally.dart';
import 'package:lume/features/tally/tally_pages.dart';

void main() {
  setUp(() => TallyRepository.deviceLabel = () => '測試機');
  soloTests();

  test('結餘、新增／修改時間、每個動作都留完整異動紀錄', () async {
    final repo = TallyRepository(_MemoryStore());
    final b = await repo.addBook('阿明');
    final a = await repo.addItem(
      bookId: b.id,
      plus: true,
      amount: 1000,
      note: '晚餐',
      at: DateTime(2026, 10, 1),
    );
    await repo.addItem(
      bookId: b.id,
      plus: false,
      amount: 300,
      note: '',
      at: DateTime(2026, 10, 5),
    );
    expect(await repo.balance(b.id), 700);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.editItem(a, plus: true, amount: 1200, note: '晚餐', at: a.at);
    final edited = (await repo.items(b.id)).first;
    expect(edited.createdAt, a.createdAt);
    expect(edited.edited, isTrue);
    expect(await repo.balance(b.id), 900);

    await repo.deleteItem(edited);
    expect(await repo.balance(b.id), -300);
    expect((await repo.itemsForUpload()).length, 2); // 墓碑還在

    await repo.logExport(
      b.id,
      filename: 'x.pdf',
      itemCount: 1,
      balance: -300,
      ok: true,
    );

    final es = await repo.events(b.id);
    expect(es.map((e) => e.action).toList().reversed, [
      TallyAction.bookCreate,
      TallyAction.itemCreate,
      TallyAction.itemCreate,
      TallyAction.itemUpdate,
      TallyAction.itemDelete,
      TallyAction.exportPdf,
    ]);
    final upd = es.firstWhere((e) => e.action == TallyAction.itemUpdate);
    expect(upd.before!['amount'], 1000);
    expect(upd.after!['amount'], 1200);
    expect(upd.balanceBefore, 700);
    expect(upd.balanceAfter, 900);
    expect(upd.device, '測試機');
    expect(upd.bookName, '阿明');
    final exp = es.first;
    expect(exp.extra!['filename'], 'x.pdf');
  });

  test('同步合併：異動紀錄聯集、內容一樣異動數是 0', () async {
    final a = TallyRepository(_MemoryStore());
    final b = TallyRepository(_MemoryStore());
    final book = await a.addBook('小華');
    await b.addBook('別本');
    expect(await a.mergeEventsFromCloud(await b.eventsForUpload()), 1);
    expect((await a.events()).length, 2);
    expect(await a.mergeBooksFromCloud(await a.booksForUpload()), 0);
    expect(book.name, '小華');
  });

  test('結餘說法', () {
    expect(tallyStatus(500), r'結餘 +NT$500');
    expect(tallyStatus(0), r'結餘 NT$0');
    expect(tallyStatus(-1234), r'結餘 −NT$1,234');
  });

  test('匯出 PDF 依筆數分頁：第一頁 9 筆、之後每頁 14 筆', () {
    final now = DateTime(2026, 10, 19, 12);
    List<TallyItem> n(int k) => [
      for (var i = 0; i < k; i++)
        TallyItem(
          id: '$i',
          bookId: 'b',
          plus: true,
          amount: 1,
          note: '',
          at: now,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    expect(tallyPages(n(0)).length, 1);
    expect(tallyPages(n(9)).length, 1);
    expect(tallyPages(n(10)).map((p) => p.length), [9, 1]);
    expect(tallyPages(n(9 + 14 * 2 + 1)).map((p) => p.length), [9, 14, 14, 1]);
  });

  testWidgets('PDF 的一頁畫得出來', (t) async {
    final now = DateTime(2026, 10, 19, 12);
    final it = TallyItem(
      id: 'i',
      bookId: 'b',
      plus: true,
      amount: 500,
      note: '車錢',
      at: now,
      createdAt: now,
      updatedAt: now,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TallyReceipt(
              items: [it],
              running: {'i': 500},
              balance: 500,
              at: now,
              page: 1,
              pageCount: 1,
              total: 1,
            ),
          ),
        ),
      ),
    );
    expect(find.text('車錢'), findsOneWidget);
    expect(find.text(r'NT$500'), findsOneWidget);
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

void soloTests() {
  testWidgets('分享用獨立頁：自動建一本帳；沒有返回、選單、設定、更多', (t) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = _MemoryStore();
    final c = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: TallyEntryPage(solo: true),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('記帳'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byTooltip('設定'), findsNothing);
    expect(find.byTooltip('改標題'), findsNothing);
    expect(find.byTooltip('異動紀錄'), findsNothing);
    expect(find.byTooltip('匯出 PDF'), findsOneWidget);
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
    expect(find.textContaining('欠'), findsNothing);
    // 再開一次，同標題不重複建。
    final repo = c.read(tallyRepositoryProvider);
    expect((await repo.books()).length, 1);
  });
}
