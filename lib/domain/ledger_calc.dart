import 'models/ledger.dart';

/// 記帳的所有計算（純函式，不碰儲存、不碰畫面）。算法照
/// `docs/記帳功能構想.md`：
///
/// - 帳戶的「值」：銀行／現金是餘額；信用卡是**已占用額度**（額度 − 可用）。
/// - 轉帳只是搬錢，不算支出；繳卡費＝活存少、信用卡占用少。
/// - 幫別人付：帳戶照整筆算，本月消費只算自己的；別人還錢不算收入。
/// - 對帳：從起始日（每個帳戶最早的對帳點）加上中間記到的交易推算，
///   跟最後一次輸入的實際值比，差額就是沒記到的錢。補記一筆（時間在對帳
///   之前）或直接調整之後，差額自己消失；存的永遠是事實，數字都是現算。

const ledgerExpenseCats = <String, (String, int)>{
  '餐飲': ('🍜', 0xFFFF9F7A),
  '交通': ('🚕', 0xFF5FD3C6),
  '購物': ('🛍️', 0xFFB79CFF),
  '娛樂': ('🎤', 0xFFF5C763),
  '居家': ('🏠', 0xFF8BD17C),
  '帳單': ('🧾', 0xFF7EA6FF),
  '醫療': ('💊', 0xFFFF7A9A),
  '雲端服務': ('☁️', 0xFF9ADBFF),
  '創業魔物童話': ('🐉', 0xFFE08FD0),
  '創業交友APP': ('💘', 0xFFFF8FB1),
  '寵物': ('🐾', 0xFFF0B27A),
  '菸酒': ('🍺', 0xFFD9A066),
  '未分類': ('❔', 0xFF8A8A9A),
};

const ledgerIncomeCats = <String, (String, int)>{
  '薪資': ('💰', 0xFF5FE08D),
  '獎金': ('🎁', 0xFF5FE08D),
  '其他收入': ('➕', 0xFF5FE08D),
};

const ledgerUncategorized = '未分類';

/// 備註最多幾個字（2026-11-03 使用者：上限 100 字）。
const ledgerNoteMax = 100;

/// 某個帳戶現在的對帳狀況。
class AccountState {
  const AccountState({
    required this.account,
    required this.start,
    required this.last,
    required this.now,
    required this.miss,
  });

  final LedgerAccount account;

  /// 起始日的期初值（最早的對帳點）。
  final LedgerCheckpoint start;

  /// 最後一次對帳（還沒對過就是 [start]）。
  final LedgerCheckpoint last;

  /// App 推算的現在值（餘額；信用卡是已占用）。
  final int now;

  /// 從起始日到最後一次對帳，還沒處理的差額。正的＝少了錢（可能漏記
  /// 支出）；負的＝多出錢（可能漏記收入或退款）；0＝對上了。
  final int miss;

  bool get checked => last.id != start.id;
  bool get isCard => account.isCard;
  int get limit => last.creditLimit ?? account.creditLimit ?? 0;

  /// 信用卡可用額度（App 推算）。
  int get available => limit - now;
}

/// 某段期間的消費統計。
class SpendStats {
  const SpendStats(this.spend, this.income, this.byCategory);

  /// 本月消費：支出（扣掉幫別人付的）＋少了錢的對帳調整 − 退款。
  final int spend;
  final int income;
  final Map<String, int> byCategory;
}

class MonthBudget {
  const MonthBudget({
    required this.total,
    required this.byCategory,
    required this.carriedFrom,
  });

  final int total;
  final Map<String, int> byCategory;

  /// 這個月沒設，沿用哪個月的（`2026-10`）；有設就是 null。
  final String? carriedFrom;
}

enum GapHintKind { wrongTime, wrongAccount, refund }

/// 缺的數字剛好對得上的一筆交易，跟可能的原因。
class GapHint {
  const GapHint(this.kind, this.tx);

  final GapHintKind kind;
  final LedgerTx tx;
}

/// 幫別人付、還沒還清的一筆。
class Owe {
  const Owe(this.tx, this.repaid);

  final LedgerTx tx;
  final int repaid;
  int get left => tx.paidFor!.amount - repaid;
}

/// 貼上匯入的一行。
class ImportLine {
  const ImportLine(
    this.line, {
    this.tx,
    this.error,
    this.duplicateOf,
    this.beforeStart = false,
    this.after,
  });

  final String line;
  final LedgerTx? tx;
  final String? error;

  /// 跟哪一筆重複（同帳戶、同分鐘、同金額）；null＝不重複。
  final String? duplicateOf;
  bool get duplicate => duplicateOf != null;
  final bool beforeStart;

  /// 選填第 9 欄：這筆之後帳戶剩多少（信用卡是可用額度），匯入時附在這筆上。
  final int? after;

  bool get willImport => tx != null && !duplicate;
}

String monthKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

/// 一整本帳（已濾掉刪除的），所有數字都從這裡現算。
class LedgerBook {
  LedgerBook({
    required List<LedgerAccount> accounts,
    required List<LedgerTx> txs,
    required List<LedgerCheckpoint> checkpoints,
    required List<LedgerBudget> budgets,
  }) : accounts = accounts.where((a) => a.deletedAt == null).toList()
         ..sort((a, b) => a.order.compareTo(b.order)),
       txs = txs.where((t) => t.deletedAt == null).toList()
         ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)),
       checkpoints = checkpoints.where((c) => c.deletedAt == null).toList()
         ..sort((a, b) => a.at.compareTo(b.at)),
       budgets = budgets.where((b) => b.deletedAt == null).toList();

  final List<LedgerAccount> accounts;

  /// 新的在前面。
  final List<LedgerTx> txs;

  /// 舊的在前面。
  final List<LedgerCheckpoint> checkpoints;
  final List<LedgerBudget> budgets;

  bool get isSetUp => accounts.isNotEmpty;

  LedgerAccount? account(String? id) =>
      accounts.where((a) => a.id == id).firstOrNull;

  LedgerTx? tx(String? id) => txs.where((t) => t.id == id).firstOrNull;

  String accountName(String? id) => account(id)?.name ?? '（已刪除的帳戶）';

  /// 起始日：所有帳戶期初值裡最早的那天。
  DateTime? get startDate {
    DateTime? d;
    for (final a in accounts) {
      final s = checkpointsOf(a.id).firstOrNull;
      if (s != null && (d == null || s.at.isBefore(d))) d = s.at;
    }
    return d;
  }

  // ── 帳戶值與對帳 ─────────────────────────────────────────

  /// 這筆交易讓帳戶的值變多少（銀行／現金是餘額；信用卡是已占用）。
  static int delta(LedgerTx t, LedgerAccount a) {
    final s = a.isCard ? -1 : 1; // 錢進來：餘額 +、信用卡占用 −
    var d = 0;
    if (t.accountId == a.id) {
      final out =
          t.type == LedgerTxType.expense ||
          t.type == LedgerTxType.transfer ||
          t.isAdjustOut;
      d += out ? -s * t.amount : s * t.amount;
    }
    if (t.type == LedgerTxType.transfer && t.toAccountId == a.id) {
      d += s * t.amount;
    }
    return d;
  }

  static int checkpointValue(LedgerAccount a, LedgerCheckpoint c) => a.isCard
      ? (c.creditLimit ?? a.creditLimit ?? 0) - (c.available ?? 0)
      : (c.balance ?? 0);

  /// 少了多少錢（正）／多出多少（負）。
  static int missOf(LedgerAccount a, int actual, int predicted) =>
      a.isCard ? actual - predicted : predicted - actual;

  List<LedgerCheckpoint> checkpointsOf(String accountId) =>
      checkpoints.where((c) => c.accountId == accountId).toList();

  /// (from, to] 之間的交易讓帳戶變多少。
  int sumBetween(LedgerAccount a, DateTime from, DateTime? to) {
    var s = 0;
    for (final t in txs) {
      if (!t.occurredAt.isAfter(from)) continue;
      if (to != null && t.occurredAt.isAfter(to)) continue;
      s += delta(t, a);
    }
    return s;
  }

  AccountState? stateOf(LedgerAccount a) {
    final list = checkpointsOf(a.id);
    if (list.isEmpty) return null;
    final start = list.first, last = list.last;
    final now = checkpointValue(a, last) + sumBetween(a, last.at, null);
    final miss = list.length < 2
        ? 0
        : missOf(
            a,
            checkpointValue(a, last),
            checkpointValue(a, start) + sumBetween(a, start.at, last.at),
          );
    return AccountState(
      account: a,
      start: start,
      last: last,
      now: now,
      miss: miss,
    );
  }

  List<AccountState> get states => [
    for (final a in accounts)
      if (stateOf(a) case final s?) s,
  ];

  /// 某一次對帳「當時」差多少（跟上一次比）；起始日那筆是 null。
  ({int predicted, int actual, int miss})? checkpointDiff(
    LedgerAccount a,
    LedgerCheckpoint c,
  ) {
    final list = checkpointsOf(a.id);
    final i = list.indexWhere((x) => x.id == c.id);
    if (i <= 0) return null;
    final p = list[i - 1];
    final pred = checkpointValue(a, p) + sumBetween(a, p.at, c.at);
    final actual = checkpointValue(a, c);
    return (predicted: pred, actual: actual, miss: missOf(a, actual, pred));
  }

  /// 附在某筆交易上的對帳點（這筆記下來時帳戶剩多少）；沒填就是 null。
  LedgerCheckpoint? checkpointOfTx(String txId) =>
      checkpoints.where((c) => c.txId == txId).firstOrNull;

  /// 這筆交易記的餘額，跟「上一個有填餘額的點 ＋ 中間記到的交易」推算出來的
  /// 差多少。正的＝少了錢（中間有支出沒記）、負的＝多出錢；0 或這筆沒填餘額、
  /// 或它是這個帳戶第一個餘額（起點）＝null。補上漏記的交易（時間落在兩個
  /// 餘額之間）之後差額歸零，標籤自己消失（2026-11-03 使用者）。
  ({LedgerCheckpoint cp, int miss})? gapOfTx(String txId) {
    final c = checkpointOfTx(txId);
    final a = c == null ? null : account(c.accountId);
    if (c == null || a == null) return null;
    final d = checkpointDiff(a, c);
    if (d == null || d.miss == 0) return null;
    return (cp: c, miss: d.miss);
  }

  /// 缺的數字剛好對得上哪一筆已經記的交易（2026-11-03 使用者：自動偵測少多少、
  /// 有沒有剛好符合這數字的消費）。三種原因：
  /// - [GapHintKind.wrongTime]：缺正數，同帳戶有一筆同金額的支出但時間落在這個
  ///   餘額之後（或上一個餘額之前）→ 時間可能記錯，沒被算進這一段；
  /// - [GapHintKind.wrongAccount]：缺正數，這一段裡有一筆同金額的支出但記在別的
  ///   帳戶 → 可能刷錯卡、記錯帳戶；
  /// - [GapHintKind.refund]：多出（缺負數），同帳戶有一筆同金額、還沒退款的支出
  ///   → 可能是退款原路退回、忘了記。
  List<GapHint> gapHints(LedgerCheckpoint c) {
    final a = account(c.accountId);
    final d = a == null ? null : checkpointDiff(a, c);
    if (a == null || d == null || d.miss == 0) return const [];
    final list = checkpointsOf(c.accountId);
    final prevAt = list[list.indexWhere((x) => x.id == c.id) - 1].at;
    final m = d.miss.abs();
    bool inside(LedgerTx t) =>
        t.occurredAt.isAfter(prevAt) && !t.occurredAt.isAfter(c.at);
    final out = <GapHint>[];
    if (d.miss > 0) {
      for (final t in txs) {
        if (t.id == c.txId || !t.isOut || t.amount != m) continue;
        if (t.accountId == c.accountId && !inside(t)) {
          out.add(GapHint(GapHintKind.wrongTime, t));
        } else if (t.accountId != c.accountId && inside(t)) {
          out.add(GapHint(GapHintKind.wrongAccount, t));
        }
      }
    } else {
      for (final t in txs) {
        if (t.accountId == c.accountId &&
            t.type == LedgerTxType.expense &&
            t.amount == m &&
            refundedOf(t.id) < t.amount) {
          out.add(GapHint(GapHintKind.refund, t));
        }
      }
    }
    return out;
  }

  /// 補記漏掉的那筆要放的時間：兩個餘額中間，盡量貼近後面那個（前一分鐘）。
  DateTime fixTimeFor(LedgerCheckpoint c) {
    final list = checkpointsOf(c.accountId);
    final i = list.indexWhere((x) => x.id == c.id);
    final oneBefore = c.at.subtract(const Duration(minutes: 1));
    if (i <= 0) return oneBefore;
    final prev = list[i - 1].at;
    if (oneBefore.isAfter(prev)) return oneBefore;
    return prev.add(
      Duration(milliseconds: c.at.difference(prev).inMilliseconds ~/ 2),
    );
  }

  // ── 消費統計 ─────────────────────────────────────────────

  SpendStats statsWhere(bool Function(LedgerTx) test) {
    final cat = <String, int>{};
    var spend = 0, income = 0;
    void add(String c, int v) {
      cat[c] = (cat[c] ?? 0) + v;
      spend += v;
    }

    for (final t in txs.where(test)) {
      switch (t.type) {
        case LedgerTxType.expense:
          add(t.category ?? ledgerUncategorized, t.ownSpend);
        case LedgerTxType.adjustment:
          if (t.isAdjustOut) add(ledgerUncategorized, t.amount);
        case LedgerTxType.refund:
          add(tx(t.linkedId)?.category ?? ledgerUncategorized, -t.amount);
        case LedgerTxType.income:
          income += t.amount;
        case LedgerTxType.transfer:
        case LedgerTxType.repayment:
          break;
      }
    }
    return SpendStats(spend, income, cat);
  }

  static bool Function(LedgerTx) inMonth(int year, int month) =>
      (t) => t.occurredAt.year == year && t.occurredAt.month == month;

  static bool Function(LedgerTx) onDay(DateTime d) =>
      (t) =>
          t.occurredAt.year == d.year &&
          t.occurredAt.month == d.month &&
          t.occurredAt.day == d.day;

  SpendStats monthStats(int year, int month) =>
      statsWhere(inMonth(year, month));

  /// 這個月的預算；沒設就沿用最近一個有設的月份。
  MonthBudget budgetOf(int year, int month) {
    var key = monthKey(year, month);
    var list = budgets.where((b) => b.month == key).toList();
    String? carried;
    if (list.isEmpty) {
      final earlier =
          budgets
              .map((b) => b.month)
              .where((m) => m.compareTo(key) < 0)
              .toSet()
              .toList()
            ..sort();
      if (earlier.isNotEmpty) {
        key = earlier.last;
        carried = key;
        list = budgets.where((b) => b.month == key).toList();
      }
    }
    return MonthBudget(
      total: list.where((b) => b.category == null).firstOrNull?.amount ?? 0,
      byCategory: {
        for (final b in list)
          if (b.category != null && b.amount > 0) b.category!: b.amount,
      },
      carriedFrom: carried,
    );
  }

  // ── 退款、幫別人付 ───────────────────────────────────────

  int refundedOf(String id) => txs
      .where((r) => r.type == LedgerTxType.refund && r.linkedId == id)
      .fold(0, (s, r) => s + r.amount);

  int repaidOf(String id) => txs
      .where((r) => r.type == LedgerTxType.repayment && r.linkedId == id)
      .fold(0, (s, r) => s + r.amount);

  /// 別人還欠你的（還沒標記還清、也還沒還完的幫付）。
  List<Owe> get owes => [
    for (final t in txs)
      if (t.paidFor != null && !t.paidFor!.settled)
        if (Owe(t, repaidOf(t.id)) case final o when o.left > 0) o,
  ];

  int get oweTotal => owes.fold(0, (s, o) => s + o.left);

  /// 可以記退款的支出（還沒退完的，新的在前）。
  List<LedgerTx> get refundable => [
    for (final t in txs)
      if (t.type == LedgerTxType.expense && refundedOf(t.id) < t.amount) t,
  ];

  List<LedgerTx> get flagged => txs.where((t) => t.flagged).toList();

  /// 搜尋（2026-11-03 使用者：輸入後每個欄位都會搜）。用空白隔開多個關鍵字，每個
  /// 都要找得到（且）；大小寫不分。搜的欄位：商家、備註、分類、類型、帳戶名稱
  /// （轉帳含轉入）、跟誰、金額（有沒有逗號都行）、日期（11/2、2026/11/02、
  /// 11月）、時間、貼上匯入的原始文字。
  bool matches(LedgerTx t, String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (terms.isEmpty) return true;
    String p(int n) => n.toString().padLeft(2, '0');
    final d = t.occurredAt;
    final amount = t.amount.toString();
    final hay = [
      t.merchant,
      t.note,
      t.category ?? '',
      t.type.label,
      accountName(t.accountId),
      if (t.toAccountId != null) accountName(t.toAccountId),
      t.paidFor?.people ?? '',
      if (t.paidFor != null) t.paidFor!.settled ? '已給 給了' : '還沒給 要給',
      if (t.flagged) '要注意 標記 旗',
      amount,
      LedgerBook.describe(t),
      '${d.month}/${d.day}',
      '${d.year}/${p(d.month)}/${p(d.day)}',
      '${d.year}-${p(d.month)}-${p(d.day)}',
      '${d.month}月${d.day}日',
      '${d.month}月',
      '${p(d.hour)}:${p(d.minute)}',
      t.raw ?? '',
    ].join('\n').toLowerCase();
    return terms.every((q) => hay.contains(q.replaceAll(',', '')));
  }

  /// 同一個帳戶、同一分鐘、同金額的那筆（2026-11-03 使用者：刷卡要防重複，
  /// 同日期到分鐘、同金額就不行）。[exceptId] 是編輯中的那筆自己。
  LedgerTx? sameMinute(
    String accountId,
    DateTime at,
    int amount, {
    String? exceptId,
  }) => txs
      .where(
        (x) =>
            x.id != exceptId &&
            x.accountId == accountId &&
            x.amount == amount &&
            _minuteOf(x.occurredAt) == _minuteOf(at),
      )
      .firstOrNull;

  /// 「11/2 19:30 鼎泰豐 $1,000」，提示重複用。
  static String describe(LedgerTx t) {
    String p(int n) => n.toString().padLeft(2, '0');
    final d = t.occurredAt;
    final money = t.amount.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final name = t.merchant.isEmpty ? (t.category ?? t.type.label) : t.merchant;
    return '${d.month}/${d.day} ${p(d.hour)}:${p(d.minute)} $name \$$money';
  }

  static String _minuteOf(DateTime t) =>
      '${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute}';

  /// 連到這筆的（退款、還款、對帳補記）。
  List<LedgerTx> linkedTo(String id) =>
      txs.where((t) => t.linkedId == id).toList();

  // ── 貼上匯入 ─────────────────────────────────────────────

  /// 一行一筆：`帳戶｜日期時間｜分類｜商家｜金額［｜跟誰｜對方要給［｜已給］］`。
  /// 帳戶寫帳戶名稱（現金、郵局）就記在那裡，其他（中信銀行刷卡紀錄）記在第一張
  /// 信用卡；分類「提款」變成轉帳（銀行 → 第一個現金帳戶），不算支出；後兩欄選填，
  /// 填了就是「跟別人一起」；第 8 欄寫「已給」＝他已經給了。
  List<ImportLine> parseImport(String text) {
    final card = accounts.where((a) => a.isCard).firstOrNull;
    final bank = accounts
        .where((a) => a.type == LedgerAccountType.bank)
        .firstOrNull;
    final cash = accounts
        .where((a) => a.type == LedgerAccountType.cash)
        .firstOrNull;
    final start = startDate;
    final out = <ImportLine>[];
    // 同一個帳戶、同一分鐘、同金額＝重複（已經記過的、或這次貼了兩行）。
    // 回傳跟哪一筆重複的說明，不重複是 null。
    final seenAt = <String, int>{};
    String? dupOf(LedgerTx t, int lineNo) {
      final k = '${t.accountId}|${_minuteOf(t.occurredAt)}|${t.amount}';
      final old = sameMinute(t.accountId, t.occurredAt, t.amount);
      if (old != null) return '已經記過的「${describe(old)}」';
      final prev = seenAt[k];
      if (prev != null) return '這次貼的第 $prev 行';
      seenAt[k] = lineNo;
      return null;
    }

    var lineNo = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      lineNo++;
      final p = line.split(RegExp('[｜|]')).map((s) => s.trim()).toList();
      if (p.length < 5) {
        out.add(ImportLine(line, error: '欄位不夠（要 5 欄：銀行｜日期時間｜分類｜商家｜金額）'));
        continue;
      }
      final m = RegExp(
        r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})\s+(\d{1,2}):(\d{2})',
      ).firstMatch(p[1]);
      if (m == null) {
        out.add(ImportLine(line, error: '看不懂日期時間'));
        continue;
      }
      final at = DateTime(
        int.parse(m[1]!),
        int.parse(m[2]!),
        int.parse(m[3]!),
        int.parse(m[4]!),
        int.parse(m[5]!),
      );
      // 金額可以是 0（折扣、折抵後免費；不另外做折扣系統，使用者 2026-11-03）。
      final amountV = int.tryParse(p[4].replaceAll(RegExp(r'[^\d]'), ''));
      final amount = amountV ?? 0;
      // 第 9 欄選填：這筆之後帳戶剩多少（信用卡填可用額度）。
      final afterV = p.length >= 9
          ? int.tryParse(p[8].replaceAll(RegExp(r'[^\d]'), ''))
          : null;
      // 第 10 欄選填：備註（想寫什麼都可以）。
      final noteV = p.length >= 10 ? p[9] : '';
      if (noteV.length > ledgerNoteMax) {
        out.add(
          ImportLine(
            line,
            error: '備註太長（${noteV.length} 字），最多 $ledgerNoteMax 字',
          ),
        );
        continue;
      }
      if (amountV == null) {
        out.add(ImportLine(line, error: '看不懂金額'));
        continue;
      }
      // 分類「轉帳」：第 4 欄是自己的帳戶名稱就是轉帳（不算支出）；不是自己的
      // 帳戶＝轉給別人，當一筆支出（2026-11-03 使用者：轉錢給別人幫我買東西）。
      if (p[2] == '轉帳') {
        if (p.length >= 10 && p[9].length > ledgerNoteMax) {
          out.add(
            ImportLine(
              line,
              error: '備註太長（${p[9].length} 字），最多 $ledgerNoteMax 字',
            ),
          );
          continue;
        }
        final named = accounts.where((a) => a.name == p[0]).firstOrNull;
        final from = named ?? bank;
        final target = accounts.where((a) => a.name == p[3]).firstOrNull;
        if (from == null) {
          out.add(ImportLine(line, error: '找不到轉出的帳戶「${p[0]}」'));
          continue;
        }
        if (target != null && target.id == from.id) {
          out.add(ImportLine(line, error: '轉出跟轉入是同一個帳戶'));
          continue;
        }
        final tx = LedgerTx(
          id: ledgerId(),
          type: target == null ? LedgerTxType.expense : LedgerTxType.transfer,
          occurredAt: at,
          amount: amount,
          accountId: from.id,
          toAccountId: target?.id,
          category: target == null ? ledgerUncategorized : null,
          merchant: target == null ? '轉給 ${p[3]}' : '轉到 ${p[3]}',
          note: p.length >= 10 ? p[9] : '',
          source: 'paste',
          raw: line,
        );
        out.add(
          ImportLine(
            line,
            tx: tx,
            after: afterV,
            duplicateOf: dupOf(tx, lineNo),
            beforeStart: start != null && at.isBefore(start),
          ),
        );
        continue;
      }
      final withdraw = p[2] == '提款';
      // 分類要是 App 有的才行，不認得就擋下這一行（2026-11-03 使用者：不要悄悄放進
      // 未分類），其他行照樣匯入。
      if (!withdraw && !ledgerExpenseCats.containsKey(p[2])) {
        out.add(
          ImportLine(
            line,
            error:
                '第 $lineNo 行：分類「${p[2]}」App 沒有這個分類。可用：'
                '${ledgerExpenseCats.keys.join("、")}'
                '（另外可寫「提款」「轉帳」）',
          ),
        );
        continue;
      }
      // 第一欄是帳戶名稱就記在那個帳戶（現金、郵局⋯）；寫「現金」記第一個
      // 現金帳戶；其他（例如「中信銀行」刷卡紀錄）記在第一張信用卡。
      final named = accounts.where((a) => a.name == p[0]).firstOrNull;
      final from = withdraw
          ? (named != null && named.type == LedgerAccountType.bank
                ? named
                : bank)
          : named ?? (p[0].contains('現金') ? cash : card);
      if (from == null || (withdraw && cash == null)) {
        out.add(
          ImportLine(
            line,
            error: withdraw ? '要先有銀行跟現金帳戶' : '找不到帳戶「${p[0]}」，也沒有信用卡帳戶',
          ),
        );
        continue;
      }
      // 選填第 6、7 欄：跟誰一起、對方要給多少（2026-11-03 使用者要求）。
      PaidFor? paidFor;
      // 填了「對方要給」或「已給」卻沒填跟誰：不要悄悄當一般消費，報錯提醒。
      final hasExtra = p.skip(6).take(2).any((s) => s.isNotEmpty);
      if (!withdraw && (p.length < 6 || p[5].isEmpty) && hasExtra) {
        out.add(ImportLine(line, error: '填了對方要給／已給，第 6 欄「跟誰」也要填'));
        continue;
      }
      if (!withdraw && p.length >= 6 && p[5].isNotEmpty) {
        if (p.length < 7) {
          out.add(ImportLine(line, error: '填了跟誰，第 7 欄「對方要給多少」也要填'));
          continue;
        }
        final owe = int.tryParse(p[6].replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
        if (owe <= 0 || owe > amount) {
          out.add(ImportLine(line, error: '對方要給的金額要大於 0、不能超過整筆'));
          continue;
        }
        // 第 8 欄選填：「已給」＝他已經給了（2026-11-03 使用者）。
        final given =
            p.length >= 8 &&
            const {'已給', '給了', 'Y', 'y', '✓', 'V', 'v'}.contains(p[7]);
        paidFor = PaidFor(amount: owe, people: p[5], settled: given);
      }
      final merchant = p[3];
      final tx = LedgerTx(
        id: ledgerId(),
        type: withdraw ? LedgerTxType.transfer : LedgerTxType.expense,
        occurredAt: at,
        amount: amount,
        accountId: from.id,
        toAccountId: withdraw ? cash!.id : null,
        category: withdraw ? null : p[2],
        merchant: merchant,
        note: noteV,
        paidFor: paidFor,
        source: 'paste',
        raw: line,
      );
      // 已經記過的、或同一次貼了兩行一樣的，都當重複跳過：同一個帳戶、
      // 同一分鐘、同金額就算（不看商家）。
      final dup = dupOf(tx, lineNo);
      out.add(
        ImportLine(
          line,
          tx: tx,
          after: afterV,
          duplicateOf: dup,
          beforeStart: start != null && at.isBefore(start),
        ),
      );
    }
    return out;
  }
}
