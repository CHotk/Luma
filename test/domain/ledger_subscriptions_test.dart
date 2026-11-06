import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/ledger_subscriptions.dart';
import 'package:lume/domain/models/ledger.dart';

LedgerSubscription sub(
  String name,
  int amount,
  int day, {
  bool active = true,
  DateTime? deletedAt,
}) => LedgerSubscription(
  id: name,
  name: name,
  amount: amount,
  day: day,
  active: active,
  deletedAt: deletedAt,
);

/// 每月訂閱（單純紀錄用）：扣款日遇到沒有那天的月份算月底、下一次扣款日、每月合計。
void main() {
  test('31 號碰到短月份算那個月最後一天（含閏年）', () {
    expect(subChargeDate(2026, 2, 31), DateTime(2026, 2, 28));
    expect(subChargeDate(2028, 2, 31), DateTime(2028, 2, 29));
    expect(subChargeDate(2026, 4, 31), DateTime(2026, 4, 30));
    expect(subChargeDate(2026, 5, 31), DateTime(2026, 5, 31));
    expect(subChargeDate(2026, 11, 12), DateTime(2026, 11, 12));
  });

  test('下一次扣款日：今天還沒過就是今天，過了就是下個月，跨年也對', () {
    final s = sub('Netflix', 390, 12);
    expect(nextSubCharge(s, DateTime(2026, 11, 5, 23)), DateTime(2026, 11, 12));
    expect(daysUntilSubCharge(s, DateTime(2026, 11, 5, 23)), 7);
    // 當天扣＝今天。
    expect(nextSubCharge(s, DateTime(2026, 11, 12, 8)), DateTime(2026, 11, 12));
    expect(daysUntilSubCharge(s, DateTime(2026, 11, 12, 8)), 0);
    // 過了就是下個月。
    expect(nextSubCharge(s, DateTime(2026, 11, 13)), DateTime(2026, 12, 12));
    // 12 月過了 → 隔年 1 月。
    expect(nextSubCharge(s, DateTime(2026, 12, 20)), DateTime(2027, 1, 12));
    // 31 號：1/31 之後下一次是 2/28。
    final e = sub('iCloud', 30, 31);
    expect(nextSubCharge(e, DateTime(2027, 1, 31)), DateTime(2027, 1, 31));
    expect(nextSubCharge(e, DateTime(2027, 2, 1)), DateTime(2027, 2, 28));
  });

  test('每月合計只算訂閱中、沒刪掉的', () {
    final list = [
      sub('A', 390, 12),
      sub('B', 100, 1),
      sub('C', 500, 5, active: false),
      sub('D', 70, 9, deletedAt: DateTime(2026, 11, 1)),
    ];
    expect(subsMonthlyTotal(list), 490);
    expect(subsMonthlyTotal(const []), 0);
  });

  test('排序：訂閱中的在前、照扣款日；已停用的在後；刪掉的不出現', () {
    final list = sortSubs([
      sub('C', 500, 5, active: false),
      sub('A', 390, 12),
      sub('D', 70, 9, deletedAt: DateTime(2026, 11, 1)),
      sub('B', 100, 1),
    ]);
    expect(list.map((s) => s.name), ['B', 'A', 'C']);
  });

  test('存取格式往返不變；舊資料缺欄位也讀得進來', () {
    final s = LedgerSubscription(
      id: 'x',
      name: 'Spotify',
      amount: 149,
      day: 3,
      note: '家庭方案',
      active: false,
      createdAt: DateTime(2026, 11, 5, 9),
      updatedAt: DateTime(2026, 11, 5, 10),
    );
    final back = LedgerSubscription.fromJson(s.toJson());
    expect(back.name, 'Spotify');
    expect(back.amount, 149);
    expect(back.day, 3);
    expect(back.note, '家庭方案');
    expect(back.active, isFalse);
    final minimal = LedgerSubscription.fromJson({'id': 'y', 'day': 99});
    expect(minimal.day, 31);
    expect(minimal.active, isTrue);
    expect(minimal.amount, 0);
  });
}
