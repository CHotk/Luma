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
  '未分類': ('❔', 0xFF8A8A9A),
};

const ledgerIncomeCats = <String, (String, int)>{
  '薪資': ('💰', 0xFF5FE08D),
  '獎金': ('🎁', 0xFF5FE08D),
  '其他收入': ('➕', 0xFF5FE08D),
};

const ledgerUncategorized = '未分類';

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
    this.duplicate = false,
    this.beforeStart = false,
    this.unknownCategory,
  });

  final String line;
  final LedgerTx? tx;
  final String? error;
  final bool duplicate;
  final bool beforeStart;
  final String? unknownCategory;

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

  /// 連到這筆的（退款、還款、對帳補記）。
  List<LedgerTx> linkedTo(String id) =>
      txs.where((t) => t.linkedId == id).toList();

  // ── 貼上匯入 ─────────────────────────────────────────────

  /// 一行一筆：`帳戶｜日期時間｜分類｜商家｜金額［｜跟誰｜對方要給］`。
  /// 帳戶寫帳戶名稱（現金、郵局）就記在那裡，其他（中信銀行刷卡紀錄）記在第一張
  /// 信用卡；分類「提款」變成轉帳（銀行 → 第一個現金帳戶），不算支出；後兩欄選填，
  /// 填了就是「跟別人一起」。
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
    final seen = <String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
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
      final amount = int.tryParse(p[4].replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      if (amount <= 0) {
        out.add(ImportLine(line, error: '看不懂金額'));
        continue;
      }
      final withdraw = p[2] == '提款';
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
      if (!withdraw && p.length >= 7 && p[5].isNotEmpty) {
        final owe = int.tryParse(p[6].replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
        if (owe <= 0 || owe > amount) {
          out.add(ImportLine(line, error: '對方要給的金額要大於 0、不能超過整筆'));
          continue;
        }
        paidFor = PaidFor(amount: owe, people: p[5]);
      }
      final known = ledgerExpenseCats.containsKey(p[2]);
      final merchant = p[3];
      final tx = LedgerTx(
        id: ledgerId(),
        type: withdraw ? LedgerTxType.transfer : LedgerTxType.expense,
        occurredAt: at,
        amount: amount,
        accountId: from.id,
        toAccountId: withdraw ? cash!.id : null,
        category: withdraw ? null : (known ? p[2] : ledgerUncategorized),
        merchant: merchant,
        paidFor: paidFor,
        source: 'paste',
        raw: line,
      );
      // 已經記過的、或同一次貼了兩行一樣的，都當重複跳過。
      final key = '${at.toIso8601String()}|$amount|$merchant';
      final dup =
          !seen.add(key) ||
          txs.any(
            (x) =>
                x.occurredAt == at &&
                x.amount == amount &&
                x.merchant == merchant,
          );
      out.add(
        ImportLine(
          line,
          tx: tx,
          duplicate: dup,
          beforeStart: start != null && at.isBefore(start),
          unknownCategory: withdraw || known ? null : p[2],
        ),
      );
    }
    return out;
  }
}
