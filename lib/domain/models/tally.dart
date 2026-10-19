/// 簡單記帳（2026-10-19 使用者要求）：跟朋友算錢用，一個帳本一個人，只有
/// ＋（借出／代墊，欠的變多）跟 −（還款，欠的變少）兩種。跟 docs/記帳功能構想.md
/// 那套「帳戶＋對帳」的完整記帳是兩回事，各自獨立一份。
///
/// 每筆都留新增時間 [TallyItem.createdAt]、最後修改時間 [TallyItem.updatedAt]；
/// 刪除用墓碑標記，所有新增／修改／刪除另外記一筆 [TallyEvent]（一筆都不刪）。
library;

// 時間存成 UTC、讀回來轉成這台裝置的時區，兩台裝置時區不同也不會錯。
DateTime? _date(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

/// 一個帳本（通常就是一個朋友）。
class TallyBook {
  const TallyBook({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  TallyBook copyWith({
    String? name,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => TallyBook(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TallyBook.fromJson(Map<String, dynamic> j) => TallyBook(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    createdAt: _date(j['createdAt'])!,
    updatedAt: _date(j['updatedAt'])!,
    deletedAt: _date(j['deletedAt']),
  );
}

/// 一筆 ＋ 或 −。金額一律是正整數（新台幣到元），方向看 [plus]。
class TallyItem {
  const TallyItem({
    required this.id,
    required this.bookId,
    required this.plus,
    required this.amount,
    required this.note,
    required this.at,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String bookId;

  /// true＝＋（欠的變多），false＝−（還款）。
  final bool plus;
  final int amount;
  final String note;

  /// 這筆錢實際發生的日子（使用者可以改）。
  final DateTime at;

  /// 第一次記下來的時間，之後不會變。
  final DateTime createdAt;

  /// 最後一次修改（或刪除）的時間；沒改過就跟 [createdAt] 一樣。
  final DateTime updatedAt;
  final DateTime? deletedAt;

  int get signed => plus ? amount : -amount;
  bool get edited => updatedAt != createdAt;

  TallyItem copyWith({
    bool? plus,
    int? amount,
    String? note,
    DateTime? at,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => TallyItem(
    id: id,
    bookId: bookId,
    plus: plus ?? this.plus,
    amount: amount ?? this.amount,
    note: note ?? this.note,
    at: at ?? this.at,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'plus': plus,
    'amount': amount,
    'note': note,
    'at': at.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TallyItem.fromJson(Map<String, dynamic> j) => TallyItem(
    id: j['id'] as String,
    bookId: j['bookId'] as String,
    plus: j['plus'] as bool? ?? true,
    amount: (j['amount'] as num).toInt(),
    note: j['note'] as String? ?? '',
    at: _date(j['at'])!,
    createdAt: _date(j['createdAt'])!,
    updatedAt: _date(j['updatedAt'])!,
    deletedAt: _date(j['deletedAt']),
  );
}

/// 異動紀錄的動作種類（存檔用 [code]，別改）。
enum TallyAction {
  bookCreate('book.create', '新增帳本'),
  bookRename('book.rename', '帳本改名'),
  bookDelete('book.delete', '刪除帳本'),
  itemCreate('item.create', '新增'),
  itemUpdate('item.update', '修改'),
  itemDelete('item.delete', '刪除'),
  exportImage('export.image', '匯出圖片');

  const TallyAction(this.code, this.label);
  final String code;
  final String label;

  static TallyAction from(String? c) =>
      values.firstWhere((a) => a.code == c, orElse: () => itemUpdate);
}

/// 異動紀錄一筆（2026-10-19 使用者要求「log 必須專業等級」）：只增不改不刪，
/// 跨裝置聯集。每筆都留：什麼時候、哪台裝置、什麼動作、哪個帳本／哪一筆、
/// 改之前跟改之後的完整資料（[before]／[after]，就是當下的 JSON 快照）、
/// 異動前後的結餘；匯出圖片在 [extra] 留檔名、筆數、結餘、存的方式、成不成功。
class TallyEvent {
  const TallyEvent({
    required this.id,
    required this.at,
    required this.action,
    required this.bookId,
    required this.bookName,
    required this.text,
    this.device = '',
    this.itemId,
    this.before,
    this.after,
    this.balanceBefore,
    this.balanceAfter,
    this.extra,
  });

  final String id;
  final DateTime at;
  final TallyAction action;
  final String bookId;

  /// 當下的帳本名稱（帳本之後改名、刪掉也看得懂）。
  final String bookName;

  /// 給人看的一句話摘要。
  final String text;
  final String device;
  final String? itemId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final int? balanceBefore;
  final int? balanceAfter;
  final Map<String, dynamic>? extra;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'action': action.code,
    'bookId': bookId,
    'bookName': bookName,
    'text': text,
    'device': device,
    'itemId': itemId,
    'before': before,
    'after': after,
    'balanceBefore': balanceBefore,
    'balanceAfter': balanceAfter,
    'extra': extra,
  };

  static Map<String, dynamic>? _map(Object? v) =>
      v == null ? null : Map<String, dynamic>.from(v as Map);

  factory TallyEvent.fromJson(Map<String, dynamic> j) => TallyEvent(
    id: j['id'] as String,
    at: _date(j['at'])!,
    action: TallyAction.from(j['action'] as String?),
    bookId: j['bookId'] as String? ?? '',
    bookName: j['bookName'] as String? ?? '',
    text: j['text'] as String? ?? '',
    device: j['device'] as String? ?? '',
    itemId: j['itemId'] as String?,
    before: _map(j['before']),
    after: _map(j['after']),
    balanceBefore: (j['balanceBefore'] as num?)?.toInt(),
    balanceAfter: (j['balanceAfter'] as num?)?.toInt(),
    extra: _map(j['extra']),
  );
}

/// 金額顯示：NT$1,234。
String tallyMoney(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'NT\$$b';
}

/// 一筆的簡短描述，異動紀錄用：「＋ NT$500「晚餐」（10/19）」。
String tallyItemLabel(TallyItem i) =>
    '${i.plus ? '＋' : '−'} ${tallyMoney(i.amount)}'
    '${i.note.isEmpty ? '' : '「${i.note}」'}（${i.at.month}/${i.at.day}）';

/// 帶正負號的金額：+NT$500／−NT$300／NT$0。
String tallySigned(int v) =>
    v == 0 ? tallyMoney(0) : '${v > 0 ? '+' : '−'}${tallyMoney(v)}';
