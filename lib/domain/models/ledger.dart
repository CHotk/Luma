import 'dart:math';

/// 記帳（Lume 自己用的，2026-11-03）：帳戶＋交易＋對帳。資料格式照
/// `docs/記帳功能構想.md`「資料格式（定案）」，四個檔各自一個清單、各自同步：
/// 帳戶、交易、對帳點、預算。
///
/// 規矩（文件「實作時要守住的規則」）：金額用整數（新台幣到元）、金額永遠
/// 是正數（方向看 type 跟帳戶）、時間帶時區、id 用 32 個十六進位字元、
/// 只存事實不存算出來的數字、刪除用墓碑。
///
/// 跟給朋友用的 cen_tally（另一個 repo）是兩回事，不共用任何東西。

final _rand = Random.secure();

/// 32 個十六進位字元、不加連字號的隨機 id（v4 UUID 的寫法，文件規則 4）。
/// 每個字元各抽一次 0–15，不用位元運算（網頁版整數位元運算只有 32 位）。
String ledgerId() =>
    List.generate(32, (_) => '0123456789abcdef'[_rand.nextInt(16)]).join();

/// 帶時區的 ISO 時間（`2026-10-24T21:08:00.000+08:00`），跨裝置、跨午夜才不會
/// 算錯月份（文件規則 3）。留到毫秒：同步比 updatedAt 誰新，只到秒的話同一秒
/// 內的兩次修改會平手，新的那次可能被舊的蓋掉。
String ledgerTime(DateTime t) {
  final l = t.toLocal();
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '${p(l.year, 4)}-${p(l.month)}-${p(l.day)}T${p(l.hour)}:${p(l.minute)}'
      ':${p(l.second)}.${p(l.millisecond, 3)}$sign${p(m ~/ 60)}:${p(m % 60)}';
}

DateTime? _t(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

enum LedgerAccountType {
  bank('bank', '銀行', '🏦'),
  creditCard('credit_card', '信用卡', '💳'),
  cash('cash', '現金', '💵');

  const LedgerAccountType(this.json, this.label, this.emoji);

  final String json;
  final String label;
  final String emoji;

  static LedgerAccountType parse(String? s) =>
      values.firstWhere((t) => t.json == s, orElse: () => bank);
}

/// 一個帳戶（中信帳戶、中信信用卡、現金⋯）。信用卡多一個總額度。
class LedgerAccount {
  const LedgerAccount({
    required this.id,
    required this.name,
    required this.type,
    this.creditLimit,
    this.order = 0,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final LedgerAccountType type;
  final int? creditLimit;
  final int order;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  bool get isCard => type == LedgerAccountType.creditCard;
  DateTime get syncedAt => updatedAt ?? createdAt ?? DateTime(2000);

  LedgerAccount copyWith({
    String? name,
    int? creditLimit,
    int? order,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => LedgerAccount(
    id: id,
    name: name ?? this.name,
    type: type,
    creditLimit: creditLimit ?? this.creditLimit,
    order: order ?? this.order,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.json,
    'creditLimit': creditLimit,
    'order': order,
    'createdAt': createdAt == null ? null : ledgerTime(createdAt!),
    'updatedAt': updatedAt == null ? null : ledgerTime(updatedAt!),
    'deletedAt': deletedAt == null ? null : ledgerTime(deletedAt!),
  };

  factory LedgerAccount.fromJson(Map<String, dynamic> j) => LedgerAccount(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    type: LedgerAccountType.parse(j['type'] as String?),
    creditLimit: (j['creditLimit'] as num?)?.toInt(),
    order: (j['order'] as num?)?.toInt() ?? 0,
    createdAt: _t(j['createdAt']),
    updatedAt: _t(j['updatedAt']),
    deletedAt: _t(j['deletedAt']),
  );
}

enum LedgerTxType {
  expense('支出'),
  income('收入'),

  /// 帳戶之間搬錢（ATM 提款、繳卡費），不算支出。
  transfer('轉帳'),

  /// 退款，[LedgerTx.linkedId] 指回原本那筆支出。
  refund('退款'),

  /// 收到欠款（別人還你錢），[LedgerTx.linkedId] 指回當初幫人付的那筆；不算收入。
  repayment('收到欠款'),

  /// 對帳調整：差額想不起來是什麼，直接調成一筆未分類。
  adjustment('對帳調整');

  const LedgerTxType(this.label);

  final String label;

  static LedgerTxType parse(String? s) =>
      values.firstWhere((t) => t.name == s, orElse: () => expense);
}

/// 幫別人付的部分（2026-10-02 使用者要求）：帳戶照整筆算，本月消費只算
/// 自己的（整筆 − [amount]）。
/// 一筆消費拆成多個分類時的其中一份（2026-11-03 使用者：1000 元家樂福，500 生活用品＋
/// 500 餐飲，就不是 1000 購物，方便產報表）。所有份加起來一定要剛好等於整筆金額。
///
/// 2026-11-05 使用者：拆的每一份也能寫品項名稱、標這份是不是幫人付的、對方給了沒。
/// 整筆的 [PaidFor]（金額＝幫人付那幾份加起來）仍然存在，舊的程式讀得到。
class LedgerSplit {
  const LedgerSplit({
    required this.category,
    required this.amount,
    this.name = '',
    this.forOther = false,
    this.settled = false,
    this.people = '',
    this.otherAmount,
  });

  final String category;
  final int amount;

  /// 品項名稱（選填）。
  final String name;

  /// 這一份是幫別人付的（不算進自己的消費）。
  final bool forOther;

  /// 幫誰（每一份各自填，一筆裡可以幫不同的人）。
  final String people;

  /// 幫人付的這一份，對方給了沒。
  final bool settled;

  /// 這一份裡對方要給多少（2026-11-09 使用者：一個品項一人一半怎麼辦）；null＝整份都是對方的。
  final int? otherAmount;

  /// 這一份裡對方要給的錢（沒幫人付＝0；不會超過這一份的金額）。
  int get otherPart =>
      !forOther ? 0 : (otherAmount ?? amount).clamp(0, amount).toInt();

  /// 這一份算自己的消費的錢。
  int get ownPart => amount - otherPart;

  Map<String, dynamic> toJson() => {
    'category': category,
    'amount': amount,
    if (name.isNotEmpty) 'name': name,
    if (forOther) 'forOther': true,
    if (forOther && settled) 'settled': true,
    if (forOther && people.isNotEmpty) 'people': people,
    if (forOther && otherAmount != null && otherAmount != amount)
      'otherAmount': otherAmount,
  };

  factory LedgerSplit.fromJson(Map<String, dynamic> j) => LedgerSplit(
    category: j['category'] as String? ?? '未分類',
    amount: (j['amount'] as num).toInt(),
    name: j['name'] as String? ?? '',
    forOther: j['forOther'] as bool? ?? false,
    settled: j['settled'] as bool? ?? false,
    people: j['people'] as String? ?? '',
    otherAmount: (j['otherAmount'] as num?)?.toInt(),
  );
}

class PaidFor {
  const PaidFor({
    required this.amount,
    required this.people,
    this.settled = false,
  });

  final int amount;
  final String people;
  final bool settled;

  PaidFor copyWith({bool? settled}) =>
      PaidFor(amount: amount, people: people, settled: settled ?? this.settled);

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'people': people,
    'settled': settled,
  };

  factory PaidFor.fromJson(Map<String, dynamic> j) => PaidFor(
    amount: (j['amount'] as num).toInt(),
    people: j['people'] as String? ?? '',
    settled: j['settled'] as bool? ?? false,
  );
}

/// 一筆交易。金額永遠是正數，方向由 [type] 跟帳戶決定。
class LedgerTx {
  const LedgerTx({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.toName = '',
    this.toOther = false,
    this.extAmount,
    this.category,
    this.merchant = '',
    this.item = '',
    this.note = '',
    this.linkedId,
    this.flagged = false,
    this.paidFor,
    this.splits = const [],
    this.source = 'manual',
    this.raw,
    this.dir,
    this.cpId,
    this.timeUnknown = false,
    this.timeOrder = 0,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final LedgerTxType type;
  final DateTime occurredAt;

  /// 時間不確定、只知道是哪一天（2026-11-10 使用者）：[occurredAt] 放那天中午 12:00 當代表，
  /// 畫面只顯示日期、不顯示時分。
  final bool timeUnknown;

  /// 時間不確定的同一天好幾筆，用這個數字決定先後（2026-11-10 使用者：像圖層，數字越低越後面）：
  /// 數字大的排在列表上面（比較晚）、小的在下面（比較早）；一樣大就看哪筆比較晚建立。
  /// 只有 [timeUnknown] 才有意義，預設 0。
  final int timeOrder;
  final int amount;
  final String accountId;

  /// 轉帳的轉入帳戶；其他類型是 null。
  final String? toAccountId;

  /// 轉帳轉到「沒記在 App 裡」的自己的戶頭（例如 LineBank，2026-11-10 使用者）：[toAccountId]
  /// 是 null、這裡放名稱；只扣轉出那個帳戶的錢，不算支出（平轉）。
  final String toName;

  /// 轉給別人的戶頭（2026-11-11 使用者）：還是「轉帳」，錢從這個帳戶扣掉、對方的戶頭不追蹤；
  /// [toName] 放誰的戶頭。轉帳本身就算一種支出（分類固定「轉給他人」），不用選支出分類。
  final bool toOther;

  /// 轉到「虛擬貨幣」時實際換到多少 USDT（2026-11-11 使用者：虛擬貨幣那邊用 USDT 當幣種）。
  final double? extAmount;
  final String? category;
  final String merchant;

  /// 品項名稱（2026-11-09 使用者：只有一筆的話也要能寫品項，不是只有備註）。
  /// 沒拆分的支出才有；拆分的每一份各自有 [LedgerSplit.name]。
  final String item;
  final String note;

  /// 退款、還錢指回原本那筆。
  final String? linkedId;

  /// 標記旗幟：單純標註、不影響任何計算。
  final bool flagged;
  final PaidFor? paidFor;

  /// 拆分（空＝沒拆）。有拆的話統計、報表照這裡的分類算，不看 [category]；
  /// [category] 這時放金額最大的那份當代表。
  final List<LedgerSplit> splits;
  bool get isSplit => splits.length >= 2;

  /// 拆分裡有標「幫人付」的那幾份。
  bool get splitHasOther => isSplit && splits.any((s) => s.forOther);

  /// 把「他給了／改回還沒給」同步到整筆跟每一份幫人付的（外面標已給時用）。
  LedgerTx withSettled(bool settled) => copyWith(
    paidFor: () => paidFor?.copyWith(settled: settled),
    splits: [
      for (final s in splits)
        s.forOther
            ? LedgerSplit(
                category: s.category,
                amount: s.amount,
                name: s.name,
                forOther: true,
                settled: settled,
                people: s.people,
                otherAmount: s.otherAmount,
              )
            : s,
    ],
  );

  /// `manual` 手動／`paste` 貼上匯入／`adjust` 對帳產生。
  final String source;

  /// 貼上匯入時的原始那行，查來源用。
  final String? raw;

  /// 只有對帳調整用：`out`（少了錢，算未分類支出）或 `in`（多出來的錢）。
  final String? dir;

  /// 對帳補記／調整的那筆是哪次對帳產生的。
  final String? cpId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? createdAt ?? occurredAt;

  /// 這筆算不算「花錢」：支出、少了錢的對帳調整。
  bool get isOut => type == LedgerTxType.expense || isAdjustOut;
  bool get isAdjustOut => type == LedgerTxType.adjustment && dir != 'in';

  /// 算進本月消費的金額（幫別人付的扣掉）。
  int get ownSpend => type == LedgerTxType.expense
      ? amount - (paidFor?.amount ?? 0)
      : isAdjustOut
      ? amount
      : 0;

  LedgerTx copyWith({
    LedgerTxType? type,
    DateTime? occurredAt,
    int? amount,
    String? accountId,
    String? Function()? toAccountId,
    String? toName,
    bool? toOther,
    double? Function()? extAmount,
    String? Function()? category,
    String? merchant,
    String? item,
    String? note,
    String? Function()? linkedId,
    bool? flagged,
    PaidFor? Function()? paidFor,
    List<LedgerSplit>? splits,
    bool? timeUnknown,
    int? timeOrder,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => LedgerTx(
    id: id,
    type: type ?? this.type,
    occurredAt: occurredAt ?? this.occurredAt,
    amount: amount ?? this.amount,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId == null ? this.toAccountId : toAccountId(),
    toName: toName ?? this.toName,
    toOther: toOther ?? this.toOther,
    extAmount: extAmount == null ? this.extAmount : extAmount(),
    category: category == null ? this.category : category(),
    merchant: merchant ?? this.merchant,
    item: item ?? this.item,
    note: note ?? this.note,
    linkedId: linkedId == null ? this.linkedId : linkedId(),
    flagged: flagged ?? this.flagged,
    paidFor: paidFor == null ? this.paidFor : paidFor(),
    splits: splits ?? this.splits,
    source: source,
    raw: raw,
    dir: dir,
    cpId: cpId,
    timeUnknown: timeUnknown ?? this.timeUnknown,
    timeOrder: timeOrder ?? this.timeOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'occurredAt': ledgerTime(occurredAt),
    'amount': amount,
    'accountId': accountId,
    'toAccountId': toAccountId,
    if (toName.isNotEmpty) 'toName': toName,
    if (toOther) 'toOther': true,
    if (extAmount != null) 'extAmt': extAmount,
    'category': category,
    'merchant': merchant,
    if (item.isNotEmpty) 'item': item,
    'note': note,
    'linkedId': linkedId,
    'flagged': flagged,
    'paidFor': paidFor?.toJson(),
    if (splits.isNotEmpty) 'splits': [for (final x in splits) x.toJson()],
    'source': source,
    'raw': raw,
    if (dir != null) 'dir': dir,
    if (cpId != null) 'cpId': cpId,
    if (timeUnknown) 'timeUnknown': true,
    if (timeOrder != 0) 'timeOrder': timeOrder,
    'createdAt': createdAt == null ? null : ledgerTime(createdAt!),
    'updatedAt': updatedAt == null ? null : ledgerTime(updatedAt!),
    'deletedAt': deletedAt == null ? null : ledgerTime(deletedAt!),
  };

  factory LedgerTx.fromJson(Map<String, dynamic> j) => LedgerTx(
    id: j['id'] as String,
    type: LedgerTxType.parse(j['type'] as String?),
    occurredAt: _t(j['occurredAt'])!,
    amount: (j['amount'] as num).toInt(),
    accountId: j['accountId'] as String,
    toAccountId: j['toAccountId'] as String?,
    toName: j['toName'] as String? ?? '',
    toOther: j['toOther'] as bool? ?? false,
    extAmount: (j['extAmt'] as num?)?.toDouble(),
    category: j['category'] as String?,
    merchant: j['merchant'] as String? ?? '',
    item: j['item'] as String? ?? '',
    note: j['note'] as String? ?? '',
    linkedId: j['linkedId'] as String?,
    flagged: j['flagged'] as bool? ?? false,
    paidFor: j['paidFor'] == null
        ? null
        : PaidFor.fromJson((j['paidFor'] as Map).cast<String, dynamic>()),
    splits: [
      for (final x in (j['splits'] as List? ?? const []))
        LedgerSplit.fromJson((x as Map).cast<String, dynamic>()),
    ],
    source: j['source'] as String? ?? 'manual',
    raw: j['raw'] as String?,
    dir: j['dir'] as String?,
    cpId: j['cpId'] as String?,
    timeUnknown: j['timeUnknown'] as bool? ?? false,
    timeOrder: (j['timeOrder'] as num?)?.toInt() ?? 0,
    createdAt: _t(j['createdAt']),
    updatedAt: _t(j['updatedAt']),
    deletedAt: _t(j['deletedAt']),
  );
}

/// 對帳點：使用者輸入的實際值。銀行／現金填 [balance]；信用卡填
/// [creditLimit]＋[available]（已占用＝兩者相減）。每個帳戶最早的那個
/// 對帳點就是起始日的期初值。
class LedgerCheckpoint {
  const LedgerCheckpoint({
    required this.id,
    required this.accountId,
    required this.at,
    this.balance,
    this.creditLimit,
    this.available,
    this.note = '',
    this.txId,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String accountId;
  final DateTime at;

  /// 這個對帳點是「某一筆交易記下來時，帳戶當下剩多少」（2026-11-03 使用者：
  /// 起始附加在某筆交易上，下一筆餘額對不上就是中間漏記）。有值＝附在那筆
  /// 交易上，時間就是那筆交易的時間，交易編輯、刪除時跟著動；手動「填餘額」
  /// 的對帳是 null。
  final String? txId;
  final int? balance;
  final int? creditLimit;
  final int? available;
  final String note;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? at;

  LedgerCheckpoint copyWith({
    DateTime? at,
    int? balance,
    int? creditLimit,
    int? available,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => LedgerCheckpoint(
    id: id,
    accountId: accountId,
    at: at ?? this.at,
    balance: balance ?? this.balance,
    creditLimit: creditLimit ?? this.creditLimit,
    available: available ?? this.available,
    note: note,
    txId: txId,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'at': ledgerTime(at),
    'balance': balance,
    'creditLimit': creditLimit,
    'available': available,
    'note': note,
    if (txId != null) 'txId': txId,
    'updatedAt': updatedAt == null ? null : ledgerTime(updatedAt!),
    'deletedAt': deletedAt == null ? null : ledgerTime(deletedAt!),
  };

  factory LedgerCheckpoint.fromJson(Map<String, dynamic> j) => LedgerCheckpoint(
    id: j['id'] as String,
    accountId: j['accountId'] as String,
    at: _t(j['at'])!,
    balance: (j['balance'] as num?)?.toInt(),
    creditLimit: (j['creditLimit'] as num?)?.toInt(),
    available: (j['available'] as num?)?.toInt(),
    note: j['note'] as String? ?? '',
    txId: j['txId'] as String?,
    updatedAt: _t(j['updatedAt']),
    deletedAt: _t(j['deletedAt']),
  );
}

/// 預算：[category] 是 null 代表整月總預算。id 固定是「月份|分類」，兩台
/// 裝置設同一個月同一個分類會合併成同一筆（後改的贏）。
class LedgerBudget {
  const LedgerBudget({
    required this.month,
    required this.category,
    required this.amount,
    this.updatedAt,
    this.deletedAt,
  });

  /// `2026-10`。
  final String month;
  final String? category;
  final int amount;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  String get id => budgetId(month, category);
  DateTime get syncedAt => updatedAt ?? DateTime(2000);

  static String budgetId(String month, String? category) =>
      '$month|${category ?? ''}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'month': month,
    'category': category,
    'amount': amount,
    'updatedAt': updatedAt == null ? null : ledgerTime(updatedAt!),
    'deletedAt': deletedAt == null ? null : ledgerTime(deletedAt!),
  };

  factory LedgerBudget.fromJson(Map<String, dynamic> j) => LedgerBudget(
    month: j['month'] as String,
    category: j['category'] as String?,
    amount: (j['amount'] as num).toInt(),
    updatedAt: _t(j['updatedAt']),
    deletedAt: _t(j['deletedAt']),
  );
}

/// 每月扣款的種類（2026-11-06 使用者：每月扣款裡可以區分訂閱跟借款）。
/// 存檔的代號還是 `debt`，舊資料不用轉。
enum LedgerChargeKind {
  subscription('subscription', '訂閱'),
  debt('debt', '借款');

  const LedgerChargeKind(this.json, this.label);

  final String json;
  final String label;

  static LedgerChargeKind parse(String? s) =>
      values.firstWhere((k) => k.json == s, orElse: () => subscription);
}

/// 借款的種類（2026-11-06 使用者）：信用卡沒有「第一期」的概念，小額借款、信貸才有。
enum LedgerDebtType {
  creditCard('credit_card', '信用卡'),
  smallLoan('small_loan', '小額借款'),
  personalLoan('personal_loan', '信貸');

  const LedgerDebtType(this.json, this.label);

  final String json;
  final String label;

  /// 舊資料沒有這欄：當時都有第一期，算小額借款。
  static LedgerDebtType parse(String? s) =>
      values.firstWhere((k) => k.json == s, orElse: () => smallLoan);
}

/// 每月自動扣款的訂閱（2026-11-05 使用者：記錄每月幾號會被扣多少錢、是什麼服務，
/// **單純紀錄用**，不會自動記進交易、不影響任何計算）。
///
/// [day] 是每月幾號（1–31）；遇到沒有那天的月份（31 號碰到 2 月）算那個月最後一天。
/// [active] 關掉＝已取消或暫停，不算進每月合計，但紀錄還留著。
class LedgerSubscription {
  const LedgerSubscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    this.kind = LedgerChargeKind.subscription,
    this.debtType = LedgerDebtType.smallLoan,
    this.periods,
    this.loanTotal,
    this.fee,
    this.startMonth,
    this.payUrl = '',
    this.payAccount = '',
    this.note = '',
    this.active = true,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int amount;
  final int day;

  /// 訂閱或借款。
  final LedgerChargeKind kind;

  /// 借款才有意義：信用卡、小額借款或信貸。
  final LedgerDebtType debtType;

  /// 畫面上的類型：訂閱，或借款的信用卡／小額借款／信貸。
  String get typeLabel =>
      kind == LedgerChargeKind.debt ? debtType.label : kind.label;

  /// 借款才有（2026-11-06 使用者：要有期數的概念，還有實際貸款總額）：總期數。
  final int? periods;

  /// 借款才有：實際貸款總額（借了多少，不含利息；每月扣款 × 期數 通常會比它多）。
  final int? loanTotal;

  /// 小額借款、信貸才有（2026-11-06 使用者）：辦理手續費，內扣——實際拿到的錢＝貸款總額 − 手續費，
  /// 但還款照貸款總額的本金算，所以要算進實際年利率。
  final int? fee;

  /// 小額借款、信貸才有：第一期是哪個月扣款，`yyyy-MM`。有了它才算得出已繳幾期、還剩幾期。
  final String? startMonth;

  /// 對方的繳款登入網址（2026-11-06 使用者：方便去繳款，可點、可複製）。
  final String payUrl;

  /// 固定的繳款戶頭（可複製）。
  final String payAccount;
  final String note;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? createdAt ?? DateTime(2000);

  LedgerSubscription copyWith({
    String? name,
    int? amount,
    int? day,
    LedgerChargeKind? kind,
    LedgerDebtType? debtType,
    int? Function()? periods,
    int? Function()? loanTotal,
    int? Function()? fee,
    String? Function()? startMonth,
    String? payUrl,
    String? payAccount,
    String? note,
    bool? active,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => LedgerSubscription(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    day: day ?? this.day,
    kind: kind ?? this.kind,
    debtType: debtType ?? this.debtType,
    periods: periods == null ? this.periods : periods(),
    loanTotal: loanTotal == null ? this.loanTotal : loanTotal(),
    fee: fee == null ? this.fee : fee(),
    payUrl: payUrl ?? this.payUrl,
    payAccount: payAccount ?? this.payAccount,
    startMonth: startMonth == null ? this.startMonth : startMonth(),
    note: note ?? this.note,
    active: active ?? this.active,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'day': day,
    'kind': kind.json,
    if (kind == LedgerChargeKind.debt) 'debtType': debtType.json,
    if (periods != null) 'periods': periods,
    if (loanTotal != null) 'loanTotal': loanTotal,
    if (fee != null) 'fee': fee,
    if (payUrl.isNotEmpty) 'payUrl': payUrl,
    if (payAccount.isNotEmpty) 'payAccount': payAccount,
    if (startMonth != null) 'startMonth': startMonth,
    'note': note,
    'active': active,
    'createdAt': createdAt == null ? null : ledgerTime(createdAt!),
    'updatedAt': updatedAt == null ? null : ledgerTime(updatedAt!),
    'deletedAt': deletedAt == null ? null : ledgerTime(deletedAt!),
  };

  factory LedgerSubscription.fromJson(Map<String, dynamic> j) =>
      LedgerSubscription(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        day: ((j['day'] as num?)?.toInt() ?? 1).clamp(1, 31),
        kind: LedgerChargeKind.parse(j['kind'] as String?),
        debtType: LedgerDebtType.parse(j['debtType'] as String?),
        periods: (j['periods'] as num?)?.toInt(),
        loanTotal: (j['loanTotal'] as num?)?.toInt(),
        fee: (j['fee'] as num?)?.toInt(),
        payUrl: j['payUrl'] as String? ?? '',
        payAccount: j['payAccount'] as String? ?? '',
        startMonth: j['startMonth'] as String?,
        note: j['note'] as String? ?? '',
        active: j['active'] as bool? ?? true,
        createdAt: _t(j['createdAt']),
        updatedAt: _t(j['updatedAt']),
        deletedAt: _t(j['deletedAt']),
      );
}

/// 記帳的操作紀錄（2026-11-03 使用者：每個動作都存一份 log，只會變大、永遠不刪）。
///
/// 只增不改不刪：沒有墓碑、不裁剪，上限只能是畫面顯示上的。多裝置同步時兩邊的
/// 紀錄直接聯集（照 id）。[detail] 放這次動作的細節（改了哪些欄位、舊值→新值）。
class LedgerLogEntry {
  const LedgerLogEntry({
    required this.id,
    required this.at,
    required this.action,
    required this.summary,
    this.detail = '',
    this.refId,
    this.device = '',
  });

  final String id;
  final DateTime at;

  /// 動作名稱：新增、編輯、刪除、標記、他給了、對帳、匯入、預算、帳戶⋯。
  final String action;
  final String summary;
  final String detail;

  /// 動到哪一筆（交易、帳戶、對帳點的 id），沒有就是 null。
  final String? refId;

  /// 哪台裝置做的（空＝舊資料）。
  final String device;

  DateTime get syncedAt => at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': ledgerTime(at),
    'action': action,
    'summary': summary,
    'detail': detail,
    'refId': refId,
    'device': device,
  };

  factory LedgerLogEntry.fromJson(Map<String, dynamic> j) => LedgerLogEntry(
    id: j['id'] as String,
    at: _t(j['at'])!,
    action: j['action'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    refId: j['refId'] as String?,
    device: j['device'] as String? ?? '',
  );
}
