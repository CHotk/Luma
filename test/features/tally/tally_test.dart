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
      filename: 'x.png',
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
      TallyAction.exportImage,
    ]);
    final upd = es.firstWhere((e) => e.action == TallyAction.itemUpdate);
    expect(upd.before!['amount'], 1000);
    expect(upd.after!['amount'], 1200);
    expect(upd.balanceBefore, 700);
    expect(upd.balanceAfter, 900);
    expect(upd.device, '測試機');
    expect(upd.bookName, '阿明');
    final exp = es.first;
    expect(exp.extra!['filename'], 'x.png');
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
    expect(tallyStatus(500), '還欠 NT\$500');
    expect(tallyStatus(0), '已還清');
    expect(tallyStatus(-1234), '多還了 NT\$1,234');
  });

  testWidgets('匯出圖片的收據畫得出來', (t) async {
    final now = DateTime(2026, 10, 19, 12);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TallyReceipt(
              book: TallyBook(
                id: 'b',
                name: '阿明',
                createdAt: now,
                updatedAt: now,
              ),
              items: [
                TallyItem(
                  id: 'i',
                  bookId: 'b',
                  plus: true,
                  amount: 500,
                  note: '車錢',
                  at: now,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              at: now,
            ),
          ),
        ),
      ),
    );
    expect(find.text('還欠 NT\$500'), findsOneWidget);
    expect(find.text('車錢'), findsOneWidget);
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
  testWidgets('分享用獨立頁：自動用標題建一本帳；沒有返回、選單、設定、更多', (t) async {
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
        child: const MaterialApp(
          home: TallyEntryPage(name: '欠小明的錢', solo: true),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('欠小明的錢'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byTooltip('設定'), findsNothing);
    expect(find.byTooltip('改標題'), findsNothing);
    expect(find.byTooltip('異動紀錄'), findsNothing);
    expect(find.byTooltip('匯出圖片'), findsOneWidget);
    expect(find.text('借出'), findsOneWidget);
    expect(find.text('還款'), findsOneWidget);
    // 再開一次，同標題不重複建。
    final repo = c.read(tallyRepositoryProvider);
    expect((await repo.books()).length, 1);
  });
}
