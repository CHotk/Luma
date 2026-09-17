import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/seed/app_defaults_loader.dart';
import 'package:lume/features/library/library_page.dart';

/// 標籤排序偏好是設定檔驅動的，這個邏輯改壞了不會當掉，只會讓下拉
/// 選單排得跟使用者要求的不一樣——這種「看起來能動但其實錯了」的
/// bug 最值得測。
void main() {
  test('相黏群組：git 排到工程師前面，兩個變成鄰居', () {
    final order = LibraryTagOrder(
      adjacentGroups: const [
        ['git', '工程師'],
      ],
      trailingOrder: const [],
    );
    final tags = sortLibraryTags(['動物', '工程師', 'git', '食物'], order);
    // git 是 ASCII，字母序本來就排在所有中文標籤前面，這是預期行為，
    // 不是 bug——使用者只要求「相鄰、git 在前」，沒要求特定絕對位置。
    expect(tags, ['git', '工程師', '動物', '食物']);
  });

  test('相黏群組裡有一個標籤不存在就整組跳過', () {
    final order = LibraryTagOrder(
      adjacentGroups: const [
        ['git', '工程師'],
      ],
      trailingOrder: const [],
    );
    final tags = sortLibraryTags(['動物', '工程師', '食物'], order);
    expect(tags, ['動物', '工程師', '食物']);
  });

  test('trailingOrder 依序排到最後面', () {
    final order = LibraryTagOrder(
      adjacentGroups: const [],
      trailingOrder: const ['中等字', '基礎字', '超基礎字'],
    );
    final tags = sortLibraryTags([
      '超基礎字',
      '動物',
      '基礎字',
      '食物',
      '中等字',
    ], order);
    expect(tags, ['動物', '食物', '中等字', '基礎字', '超基礎字']);
  });

  test('trailingOrder 裡沒出現在資料裡的標籤直接跳過', () {
    final order = LibraryTagOrder(
      adjacentGroups: const [],
      trailingOrder: const ['中等字', '基礎字', '超基礎字'],
    );
    final tags = sortLibraryTags(['動物', '基礎字'], order);
    expect(tags, ['動物', '基礎字']);
  });

  test('沒有任何偏好設定就是單純字母序', () {
    final tags = sortLibraryTags(['食物', '動物', '居家'], LibraryTagOrder.empty);
    expect(tags, ['動物', '居家', '食物']);
  });
}
