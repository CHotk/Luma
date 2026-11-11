import 'models/ledger.dart';

/// 記帳的所有計算（純函式，不碰儲存、不碰畫面）。算法照
/// `docs/記帳功能構想.md`：
///
/// - 帳戶的「值」：銀行／現金是餘額；信用卡是**已占用額度**（額度 − 可用）。
/// - 轉帳只是搬錢，不算支出；繳卡費＝帳戶少、信用卡占用少。
/// - 幫別人付：帳戶照整筆算，本月消費只算自己的；別人還錢不算收入。
/// - 對帳：從起始日（每個帳戶最早的對帳點）加上中間記到的交易推算，
///   跟最後一次輸入的實際值比，差額就是沒記到的錢。補記一筆（時間在對帳
///   之前）或直接調整之後，差額自己消失；存的永遠是事實，數字都是現算。

const ledgerExpenseCats = <String, (String, int)>{
  '餐飲': ('🍜', 0xFFFF9F7A),
  '交通': ('🚕', 0xFF5FD3C6),
  // 沒有「購物」分類（2026-11-09 使用者不需要）；舊資料用設定裡的「購物併入生活」轉走。
  '娛樂': ('🎤', 0xFFF5C763),
  '居家': ('🏠', 0xFF8BD17C),
  '帳單': ('🧾', 0xFF7EA6FF),
  '醫療': ('💊', 0xFFFF7A9A),
  '雲端服務': ('☁️', 0xFF9ADBFF),
  '寵物': ('🐾', 0xFFF0B27A),
  '生活': ('🏡', 0xFF8FD1A8),
  '菸酒': ('🍺', 0xFFD9A066),
  // 還款（2026-11-11 使用者）：還給誰用下拉選單選，見 [ledgerRepayTargets]。
  '還款': ('💸', 0xFFFF8A65),
  // 創業兩個放最底下，最後一個一定是「未分類」（2026-11-11 使用者）。
  '創業魔物童話': ('🐉', 0xFFE08FD0),
  '創業交友APP': ('💘', 0xFFFF8FB1),
  '未分類': ('❔', 0xFF8A8A9A),
};

/// 轉帳給別人的戶頭（[LedgerTx.toOther]）算的分類：轉帳本身就是一種支出，不用選支出分類。
const ledgerToOtherCat = '轉給他人';

/// 支出分類「還款」。
const ledgerRepayCat = '還款';

/// 轉帳「轉到」沒記在 App 裡的自己的地方（平轉：只扣轉出帳戶、不算支出）。2026-11-10 LineBank，
/// 2026-11-11 使用者加富邦、虛擬貨幣。
const ledgerTransferExts = <(String, String)>[
  ('LineBank', '🏦'),
  ('富邦', '🏦'),
  ('虛擬貨幣', '💎'),
];

/// 虛擬貨幣（USDT）粗估換算台幣用的匯率（2026-11-11 使用者：填 USDT 順便顯示 ×32 的粗估台幣）。
const ledgerUsdtRoughRate = 32;

/// 轉到虛擬貨幣的那個名稱（[ledgerTransferExts] 裡的）。
const ledgerCryptoExt = '虛擬貨幣';

/// 收入分類「平轉」的來源戶頭（沒記在 App 裡的）：選項只有這兩個（2026-11-11 使用者）。
const ledgerFlatSources = <String>['LineBank', '富邦'];

/// 「還款」的對象只有這幾個，用下拉選單選（2026-11-11 使用者）。舊資料、貼上匯入帶進來的
/// 其他名稱編輯時會自動多出一個選項，不會被洗掉。
const ledgerRepayTargets = <String>['中信信貸', '台新信貸', '當鋪', 'Jet', 'JUJI'];

const ledgerIncomeCats = <String, (String, int)>{
  '薪資': ('💰', 0xFF5FE08D),
  '獎金': ('🎁', 0xFF5FE08D),
  '其他收入': ('➕', 0xFF5FE08D),
  // 自己不同帳戶之間轉來轉去（2026-11-10 使用者）：錢確實進了這個帳戶，但不算收入（見 [ledgerFlatTransfer]）。
  '平轉': ('🔁', 0xFF7EA6FF),
  // 不知道算什麼收入時選這個（2026-11-10 使用者）；照一般收入算進本月收入。
  '未分類': ('❔', 0xFF8A8A9A),
};

/// 記一筆「收入」的來源只有這幾種，用下拉選單選（2026-11-10 使用者）。舊資料、貼上匯入帶進來的
/// 其他名稱（例如公司名）編輯時會自動多出一個選項，不會被洗掉。
const ledgerIncomeSources = <String>['薪資轉帳', 'ATM存款', '轉帳', '獎金', '利息', '其他'];

/// 收入分類「平轉」：自己的帳戶之間轉來轉去、ATM 存自己的現金…；餘額會加，但不算進本月收入。
const ledgerFlatTransfer = '平轉';

const ledgerUncategorized = '未分類';

/// 貼上匯入的收入：第 3 欄寫左邊那個字就是收入、分類記成右邊那個（2026-11-10 使用者：轉帳、ATM存款、
/// 薪資轉帳）。「轉帳」本來是轉出去，所以收到的轉帳寫「轉入」。
const ledgerImportIncome = <String, String>{
  '薪資轉帳': '薪資',
  '薪資': '薪資',
  '獎金': '獎金',
  'ATM存款': '其他收入',
  'ATM存入': '其他收入',
  '現金存款': '其他收入',
  '存款': '其他收入',
  // 2026-11-10 使用者：「ATM存款」其實是判斷收入，所以也可以寫「收入存款」，兩個都保留。
  '收入存款': '其他收入',
  '帳戶存款': '其他收入',
  '收入': '其他收入',
  '存入': '其他收入',
  '轉入': '其他收入',
  '轉帳入帳': '其他收入',
  '匯入': '其他收入',
  '利息': '其他收入',
  '其他收入': '其他收入',
  '平轉': '平轉',
  '自轉': '平轉',
  '互轉': '平轉',
};

/// 貼上匯入第 3 欄是不是收入，是的話回傳收入分類（不是收入回傳 null）。
///
/// 除了 [ledgerImportIncome] 的寫法，也能「收入＋分類」一次寫好（2026-11-10 使用者）：
/// 收入未分類、收入/未分類、ATM存款/平轉、收入存款-薪資（分隔用 / - : 、 逗號都行）。
/// 「未分類」「其他」支出也有，單獨寫會當支出，所以收入的未分類一定要前面帶收入的字。
String? ledgerImportIncomeCat(String col) {
  final k = ledgerIncomeKey(col);
  final direct = ledgerImportIncome[k];
  if (direct != null) return direct;
  final parts = k.split(RegExp(r'[/\-:、,]'));
  if (parts.length == 2 &&
      ledgerIncomeCats.containsKey(parts[1]) &&
      (parts[0] == '收入' || ledgerImportIncome.containsKey(parts[0]))) {
    return parts[1];
  }
  if (parts.length == 1 &&
      k.startsWith('收入') &&
      ledgerIncomeCats.containsKey(k.substring(2))) {
    return k.substring(2);
  }
  return null;
}

/// 比對收入分類用的寫法：拿掉空白、全形英數轉半形、英文轉大寫（ＡＴＭ存款、atm 存款、ATM存款 都認得）。
String ledgerIncomeKey(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x20 || r == 0x3000 || r == 0x09) continue;
    b.writeCharCode(r >= 0xFF01 && r <= 0xFF5E ? r - 0xFEE0 : r);
  }
  return b.toString().toUpperCase();
}

/// 備註最多幾個字（2026-11-03 使用者：上限 100 字）。
const ledgerNoteMax = 100;

/// 拆分每一份的品項名稱上限（2026-11-05 使用者：50 字）。
const ledgerSplitNameMax = 50;

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
  const SpendStats(
    this.spend,
    this.income,
    this.byCategory, {
    this.extra = const {},
  });

  /// 消費：自己花掉的（支出扣掉幫別人付的）＋少了錢的對帳調整 − 退款。不含「還款」分類、
  /// 轉給他人（2026-11-11 使用者：消費當然是算自己）。
  final int spend;
  final int income;

  /// 消費的分類細項。
  final Map<String, int> byCategory;

  /// 不算消費、但算進總支出的（2026-11-11 使用者）：幫別人付（對方那份）、還款、轉給他人。
  final Map<String, int> extra;

  /// 總支出＝消費＋[extra]：錢實際離開的全部。
  int get out => spend + extra.values.fold(0, (a, b) => a + b);
}

/// 總支出裡「幫別人付」那一項的名稱。
const ledgerPaidForOut = '幫別人付';

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
    this.duplicateTx,
    this.sameDayOf,
    this.beforeStart = false,
    this.after,
  });

  final String line;
  final LedgerTx? tx;
  final String? error;

  /// 跟哪一筆重複（同帳戶、同分鐘、同金額）；null＝不重複。
  final String? duplicateOf;

  /// 重複的是已經記過的哪一筆（貼的單行偵測到時，直接改成編輯它）；這次貼的兩行重複＝null。
  final LedgerTx? duplicateTx;
  bool get duplicate => duplicateOf != null;

  /// 當天已經有相同金額的其他筆（不看帳戶；只提醒、不擋下）。
  final String? sameDayOf;
  final bool beforeStart;

  /// 選填第 9 欄：這筆之後帳戶剩多少（信用卡是可用額度），匯入時附在這筆上。
  final int? after;

  bool get willImport => tx != null && !duplicate;
}

String monthKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

/// 時間不確定的「同天排序」：1～20 排在同一天有時分的後面，超過 20 排在它們前面
/// （2026-11-10 使用者）；最大可以填 [ledgerTimeOrderMax]。
const ledgerTimeOrderBehindMax = 20;
const ledgerTimeOrderMax = 99;

/// 一整本帳（已濾掉刪除的），所有數字都從這裡現算。
class LedgerBook {
  LedgerBook({
    required List<LedgerAccount> accounts,
    required List<LedgerTx> txs,
    required List<LedgerCheckpoint> checkpoints,
    required List<LedgerBudget> budgets,
  }) : this._(
         accounts,
         txs.where((t) => t.deletedAt == null).toList(),
         checkpoints,
         budgets,
       );

  LedgerBook._(
    List<LedgerAccount> accounts,
    List<LedgerTx> live,
    List<LedgerCheckpoint> cps,
    List<LedgerBudget> budgets,
  ) : this._calc(accounts, live, cps, budgets, _calcTimes(live));

  LedgerBook._calc(
    List<LedgerAccount> accounts,
    List<LedgerTx> live,
    List<LedgerCheckpoint> cps,
    List<LedgerBudget> budgets,
    Map<String, DateTime> calc,
  ) : _calcAt = calc,
      accounts = accounts.where((a) => a.deletedAt == null).toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      txs = (live.toList()
        ..sort((a, b) {
          final c = calc[b.id]!.compareTo(calc[a.id]!);
          if (c != 0) return c;
          final o = (b.createdAt ?? b.occurredAt).compareTo(
            a.createdAt ?? a.occurredAt,
          );
          return o != 0 ? o : b.id.compareTo(a.id);
        })),
      // 附在交易上的餘額點，時間跟著那筆在時間線上的位置走（時間不確定的、或跟別筆剛好同一個
      // 時間點被分出先後的）。
      checkpoints = (cps.where((c) => c.deletedAt == null).map((c) {
        final tid = c.txId;
        final when = tid == null ? null : calc[tid];
        final t = tid == null
            ? null
            : live.where((x) => x.id == tid).firstOrNull;
        return when != null && t != null && when != t.occurredAt
            ? c.copyWith(at: when)
            : c;
      }).toList()..sort((a, b) => a.at.compareTo(b.at))),
      budgets = budgets.where((b) => b.deletedAt == null).toList();

  /// 每一筆在「時間線」上的位置（算餘額、可刷額度、對帳用，2026-11-10 使用者：時間不確定的
  /// 也要照排序數字線性計算）。有時分的就是它自己的時間；時間不確定的放在當天的兩頭：
  /// 排序超過 [ledgerTimeOrderBehindMax]（20）的在當天最後（23:58 起、數字小的先），
  /// 1～20 或沒設的在當天最前（00:00 起、數字小的先）；排序一樣的照建立先後，
  /// 所以每一筆的位置都不一樣（沒有「同一個時間點」的平手）。
  static Map<String, DateTime> _calcTimes(List<LedgerTx> live) {
    final out = <String, DateTime>{};
    final groups = <String, List<LedgerTx>>{};
    for (final t in live) {
      if (!t.timeUnknown) {
        // 有時分的：同一個時間點有好幾筆（例如轉帳跟刷卡剛好同一分鐘）照建立先後排，
        // 不然算餘額時第二筆會被當成跟上一個餘額點同時、扣不到（2026-11-10 使用者回報）。
        (groups['at|${t.occurredAt.millisecondsSinceEpoch}'] ??= []).add(t);
        continue;
      }
      final d = t.occurredAt;
      final front = t.timeOrder > ledgerTimeOrderBehindMax;
      (groups['${d.year}-${d.month}-${d.day}|$front|${t.timeOrder}'] ??= [])
          .add(t);
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        final c = (a.createdAt ?? a.occurredAt).compareTo(
          b.createdAt ?? b.occurredAt,
        );
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      for (var i = 0; i < list.length; i++) {
        final t = list[i], d = t.occurredAt;
        if (!t.timeUnknown) {
          out[t.id] = d.add(Duration(milliseconds: i > 999 ? 999 : i));
          continue;
        }
        final base = t.timeOrder > ledgerTimeOrderBehindMax
            ? DateTime(d.year, d.month, d.day, 23, 58)
            : DateTime(d.year, d.month, d.day);
        out[t.id] = base.add(
          Duration(seconds: t.timeOrder, milliseconds: i > 999 ? 999 : i),
        );
      }
    }
    return out;
  }

  final Map<String, DateTime> _calcAt;

  /// 這筆在時間線上的位置（見 [_calcTimes]）。
  DateTime calcAtOf(LedgerTx t) => _calcAt[t.id] ?? t.occurredAt;

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

  /// 中信的信用卡（名稱有「中信」的信用卡）。
  bool isCtbcCard(LedgerAccount? a) =>
      a != null && a.isCard && a.name.contains('中信');

  String accountName(String? id) => account(id)?.name ?? '（已刪除的帳戶）';

  /// 沒記在 App 裡的地方（LineBank／富邦）照轉入轉出推算有多少台幣：轉進去的轉帳加、
  /// 收入「平轉」從那邊轉回來的減。[skipId] 是正在編輯的那筆（算「這筆之後」時先拿掉）。
  /// 照時間先後算沒記在 App 裡的那邊（[name]）。[twd]＝這筆讓它變多少（台幣或 USDT）；
  /// 轉帳有填「這筆之後」（[LedgerTx.fromAfter]／[LedgerTx.toAfter]）就直接用那個數字當新的起點。
  double _extRun(
    String name,
    String? skipId,
    double Function(LedgerTx t, int dir) delta, {
    String? stopAt,
  }) {
    final list =
        [
          for (final t in txs)
            if (t.id != skipId) t,
        ]..sort((a, b) {
          final c = a.occurredAt.compareTo(b.occurredAt);
          return c != 0
              ? c
              : (a.createdAt ?? a.occurredAt).compareTo(
                  b.createdAt ?? b.occurredAt,
                );
        });
    var sum = 0.0;
    for (final t in list) {
      if (t.id == stopAt) break;
      if (t.type == LedgerTxType.transfer &&
          !t.toOther &&
          t.toAccountId == null &&
          t.toName == name) {
        sum = t.toAfter ?? sum + delta(t, 1);
      } else if (t.type == LedgerTxType.income &&
          t.category == ledgerFlatTransfer &&
          t.toName == name) {
        sum += delta(t, -1);
      }
      // 從那邊轉出去（轉帳的「從哪個帳戶」選了它）。
      if (t.type == LedgerTxType.transfer && t.fromName == name) {
        sum = t.fromAfter ?? sum + delta(t, -1);
      }
    }
    return sum;
  }

  /// 沒記在 App 裡的地方（LineBank／富邦）照轉入轉出推算有多少台幣：轉進去的轉帳加、
  /// 收入「平轉」從那邊轉回來的減、從那邊轉出去的減；有填「這筆之後」就從那裡重新算。
  /// [skipId] 是正在編輯的那筆（算「這筆之後」時先拿掉）。
  int extBalance(String name, {String? skipId}) =>
      _extRun(name, skipId, (t, dir) => dir * t.amount.toDouble()).round();

  /// 虛擬貨幣累計多少 USDT（沒填 USDT 的舊資料用 ÷32 粗估）；有填「這筆之後」就從那裡重新算。
  double usdtBalance({String? skipId}) => _extRun(
    ledgerCryptoExt,
    skipId,
    (t, dir) => dir * (t.extAmount ?? t.amount / ledgerUsdtRoughRate),
  );

  /// 虛擬貨幣那邊填了「這筆之後」時，跟推算差多少 USDT（正＝多出來、負＝少了；沒填或沒差＝null）。
  /// 幣價會浮動，差額可以在表單確認是盈虧（[LedgerTx.extPnlOk]）。
  double? usdtDiffOf(LedgerTx t) {
    if (t.type != LedgerTxType.transfer) return null;
    final isTo =
        !t.toOther && t.toAccountId == null && t.toName == ledgerCryptoExt;
    final isFrom = t.fromName == ledgerCryptoExt;
    final after = isTo ? t.toAfter : (isFrom ? t.fromAfter : null);
    if (after == null) return null;
    final before = _extRun(
      ledgerCryptoExt,
      null,
      (x, dir) => dir * (x.extAmount ?? x.amount / ledgerUsdtRoughRate),
      stopAt: t.id,
    );
    final mine = t.extAmount ?? t.amount / ledgerUsdtRoughRate;
    final d = after - (before + (isTo ? mine : -mine));
    return d.abs() < 0.005 ? null : d;
  }

  /// 轉帳「從哪」那邊的名稱：沒記在 App 裡的（LineBank／富邦／虛擬貨幣）用 [LedgerTx.fromName]。
  String fromLabel(LedgerTx t) =>
      t.fromName.isNotEmpty ? t.fromName : accountName(t.accountId);

  String toLabel(LedgerTx t) => t.toAccountId == null && t.toName.isNotEmpty
      ? t.toName
      : accountName(t.toAccountId);

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
      final at = calcAtOf(t);
      if (!at.isAfter(from)) continue;
      if (to != null && at.isAfter(to)) continue;
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

  /// 附在某筆交易上的所有對帳點（轉帳可以兩邊帳戶各填一個，2026-11-03 使用者）。
  List<LedgerCheckpoint> checkpointsOfTx(String txId) =>
      checkpoints.where((c) => c.txId == txId).toList();

  /// 附在某筆交易上的對帳點（這筆記下來時帳戶剩多少）；沒填就是 null。有兩個時
  /// 給 [accountId] 指定要哪個帳戶的，不給就是第一個。
  LedgerCheckpoint? checkpointOfTx(String txId, {String? accountId}) =>
      checkpoints
          .where(
            (c) =>
                c.txId == txId &&
                (accountId == null || c.accountId == accountId),
          )
          .firstOrNull;

  /// 這筆交易記的餘額，跟「上一個有填餘額的點 ＋ 中間記到的交易」推算出來的
  /// 差多少。正的＝少了錢（中間有支出沒記）、負的＝多出錢；0 或這筆沒填餘額、
  /// 或它是這個帳戶第一個餘額（起點）＝null。補上漏記的交易（時間落在兩個
  /// 餘額之間）之後差額歸零，標籤自己消失（2026-11-03 使用者）。
  ({LedgerCheckpoint cp, int miss})? gapOfTx(String txId) {
    // 轉帳兩邊都填了，任何一邊對不上都算這筆有缺。
    for (final c in checkpointsOfTx(txId)) {
      final a = account(c.accountId);
      if (a == null) continue;
      final d = checkpointDiff(a, c);
      if (d == null || d.miss == 0) continue;
      return (cp: c, miss: d.miss);
    }
    return null;
  }

  /// 這筆每個有對不上的餘額（轉帳兩邊各一個，戶頭跟卡可能一個對、一個不對）。
  List<({LedgerAccount account, LedgerCheckpoint cp, int miss})> gapsOfTx(
    String txId,
  ) => [
    for (final c in checkpointsOfTx(txId))
      if (account(c.accountId) case final a?)
        if (checkpointDiff(a, c) case final d? when d.miss != 0)
          (account: a, cp: c, miss: d.miss),
  ];

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
        calcAtOf(t).isAfter(prevAt) && !calcAtOf(t).isAfter(c.at);
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

  /// 把 [value] 這麼多錢分到這筆的各個分類：沒拆就全給它的分類；有拆就照每份佔整筆
  /// 的比例分（整數四捨五入，最後一份補齊差額，加起來一定剛好是 [value]）。
  /// 幫別人付時 [value] 是自己那份，所以對方要給的部分也是照比例從各分類扣。
  Map<String, int> categoryShares(LedgerTx t, int value) {
    final base = t.category ?? ledgerUncategorized;
    if (!t.isSplit || t.amount <= 0) return {base: value};
    final out = <String, int>{};
    // 有標「幫人付」的份：自己的消費就是沒標的那幾份，直接照各自分類算，不用比例。
    if (t.splitHasOther && value == t.ownSpend) {
      for (final s in t.splits) {
        // 幫人付的那份只算自己的部分（對方要給的那段不算）。
        final own = s.ownPart;
        if (own <= 0) continue;
        out[s.category] = (out[s.category] ?? 0) + own;
      }
      return out;
    }
    var left = value;
    for (var i = 0; i < t.splits.length; i++) {
      final s = t.splits[i];
      final part = i == t.splits.length - 1
          ? left
          : (value * s.amount / t.amount).round();
      out[s.category] = (out[s.category] ?? 0) + part;
      left -= part;
    }
    return out;
  }

  /// 這筆（或它原本的支出，退款時）算哪些分類。
  List<String> categoriesOf(LedgerTx t) {
    if (t.type == LedgerTxType.transfer && t.toOther) {
      return const [ledgerToOtherCat];
    }
    final src = t.type == LedgerTxType.refund ? tx(t.linkedId) : t;
    if (src == null) return const [];
    if (src.isSplit) return [for (final s in src.splits) s.category];
    return [if (src.category != null) src.category!];
  }

  SpendStats statsWhere(bool Function(LedgerTx) test) {
    final cat = <String, int>{};
    final extra = <String, int>{};
    var spend = 0, income = 0;
    void addExtra(String k, int v) {
      if (v != 0) extra[k] = (extra[k] ?? 0) + v;
    }

    void addShares(Map<String, int> shares) {
      shares.forEach((c, v) {
        // 還款不是消費，算總支出（2026-11-11 使用者）。
        if (c == ledgerRepayCat) return addExtra(ledgerRepayCat, v);
        cat[c] = (cat[c] ?? 0) + v;
        spend += v;
      });
    }

    for (final t in txs.where(test)) {
      switch (t.type) {
        case LedgerTxType.expense:
          addShares(categoryShares(t, t.ownSpend));
          addExtra(ledgerPaidForOut, t.amount - t.ownSpend);
        case LedgerTxType.adjustment:
          if (t.isAdjustOut) addShares({ledgerUncategorized: t.amount});
        case LedgerTxType.refund:
          final o = tx(t.linkedId);
          addShares(
            o == null
                ? {ledgerUncategorized: -t.amount}
                : categoryShares(o, -t.amount),
          );
        case LedgerTxType.income:
          if (t.category != ledgerFlatTransfer) income += t.amount;
        case LedgerTxType.transfer:
          // 轉給別人的戶頭：錢離開了，算一筆支出（2026-11-11 使用者）；轉給自己的帳戶不算。
          if (t.toOther) addExtra(ledgerToOtherCat, t.amount);
        case LedgerTxType.repayment:
          break;
      }
    }
    return SpendStats(spend, income, cat, extra: extra);
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

  /// 幫別人付過的交易（有填「幫誰」的，不管對方給了沒）。
  List<LedgerTx> get paidForOthers =>
      txs.where((t) => t.paidFor != null).toList();

  /// 搜尋（2026-11-03 使用者：輸入後每個欄位都會搜）。用空白隔開多個關鍵字，每個
  /// 都要找得到（且）；大小寫不分。搜的欄位：商家、品項名稱、備註、分類、類型、帳戶名稱
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
      t.item,
      t.note,
      t.category ?? '',
      for (final s in t.splits) ...[s.category, s.name, s.people],
      t.type.label,
      fromLabel(t),
      if (t.toAccountId != null) accountName(t.toAccountId),
      t.toName,
      if (t.toOther)
        '轉給他人'
      else if (t.toName.isNotEmpty || t.fromName.isNotEmpty)
        '平轉',
      t.paidFor?.people ?? '',
      if (t.paidFor != null) t.paidFor!.settled ? '已給 給了' : '還沒給 要給',
      if (t.flagged) '旗幟 標記 旗 要注意',
      t.confirmed ? '已確認 確認過' : '未確認',
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

  /// 當天已經有相同金額的其他筆（2026-11-03 使用者：不管刷卡還是現金、不看帳戶，
  /// 只要金額相同又是同一天，就提醒一下；只提醒、不擋下。同帳戶同一分鐘同金額
  /// 才是擋下來的重複，見 [sameMinute]）。金額 0 不提醒。
  List<LedgerTx> sameDayAmount(DateTime at, int amount, {String? exceptId}) {
    if (amount <= 0) return const [];
    return txs
        .where(
          (x) =>
              x.id != exceptId &&
              x.amount == amount &&
              x.occurredAt.year == at.year &&
              x.occurredAt.month == at.month &&
              x.occurredAt.day == at.day,
        )
        .toList();
  }

  /// 同一個帳戶、同一分鐘、同金額、同商店的那筆（2026-11-03 使用者：刷卡要防重複，
  /// 同日期到分鐘、同金額就不行；2026-11-10 使用者：商店名稱也要一樣才算，同一分鐘
  /// 同金額但不同店是兩筆）。[exceptId] 是編輯中的那筆自己。
  /// [merchant] 有給才比商店：忽略空白、大小寫，其中一邊沒寫商店就當一樣（保守，寧可多提醒）。
  LedgerTx? sameMinute(
    String accountId,
    DateTime at,
    int amount, {
    String? exceptId,
    String? merchant,
  }) => txs
      .where(
        (x) =>
            x.id != exceptId &&
            x.accountId == accountId &&
            x.amount == amount &&
            _minuteOf(x.occurredAt) == _minuteOf(at) &&
            (merchant == null || sameShop(x.merchant, merchant)),
      )
      .firstOrNull;

  /// 卡費退回（2026-11-10 使用者：卡費也可能是退款或部分退款，要能記成負數）：
  /// 從信用卡轉到非信用卡的帳戶。信用卡欠的變多、錢回到銀行／現金，等於負的繳卡費。
  bool isCardReturn(LedgerTx t) =>
      t.type == LedgerTxType.transfer &&
      t.toAccountId != null &&
      account(t.accountId)?.isCard == true &&
      account(t.toAccountId)?.isCard != true;

  /// 商店名稱算不算一樣：拿掉空白、不分大小寫；其中一邊是空的就當一樣。
  static bool sameShop(String a, String b) {
    String k(String s) => ledgerIncomeKey(s);
    final x = k(a), y = k(b);
    return x.isEmpty || y.isEmpty || x == y;
  }

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

  /// 貼上匯入第 1 欄找帳戶：名稱一模一樣最優先；否則拿掉「銀行／信用卡／卡／帳戶／活存」這些字，
  /// 剩下的銀行名稱一樣就算（2026-11-10 使用者：「台新銀行」要對到台新卡）。[card] 是 true
  /// 只在信用卡裡找（刷卡支出），false 只在非信用卡裡找（收入、提款、轉帳）；找不到回傳 null。
  LedgerAccount? accountForImport(String name, {required bool card}) {
    final exact = accounts.where((a) => a.name == name).firstOrNull;
    if (exact != null) return exact;
    String stem(String s) => s
        .replaceAll(RegExp(r'\s|　'), '')
        .replaceAll(RegExp(r'信用卡|銀行|帳戶|活存|存款|戶頭|卡'), '');
    final k = stem(name);
    if (k.length < 2) return null;
    return accounts.where((a) => a.isCard == card).where((a) {
      final s = stem(a.name);
      return s.length >= 2 && (s == k || s.contains(k) || k.contains(s));
    }).firstOrNull;
  }

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
    // 當天相同金額（不看帳戶）：已經記過的、或這次貼的前面幾行；只提醒。
    final seenDay = <String, int>{};
    String? sameDayWarn(LedgerTx t, int lineNo) {
      if (t.amount <= 0) return null;
      final k =
          '${t.occurredAt.year}-${t.occurredAt.month}-${t.occurredAt.day}|${t.amount}';
      final old = sameDayAmount(t.occurredAt, t.amount);
      final prev = seenDay[k];
      seenDay.putIfAbsent(k, () => lineNo);
      if (old.isNotEmpty) return '已經記過的「${describe(old.first)}」';
      if (prev != null) return '這次貼的第 $prev 行';
      return null;
    }

    LedgerTx? dupTx;
    String? dupOf(LedgerTx t, int lineNo) {
      dupTx = null;
      final k =
          '${t.accountId}|${_minuteOf(t.occurredAt)}|${t.amount}|${ledgerIncomeKey(t.merchant)}';
      final old = sameMinute(
        t.accountId,
        t.occurredAt,
        t.amount,
        merchant: t.merchant,
      );
      if (old != null) {
        dupTx = old;
        return '已經記過的「${describe(old)}」';
      }
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
      // 第 11 欄選填：品項名稱（2026-11-09 使用者；上限跟記一筆的品項一樣 50 字）。
      final itemV = p.length >= 11 ? p[10] : '';
      if (itemV.length > ledgerSplitNameMax) {
        out.add(
          ImportLine(
            line,
            error: '品項名稱太長（${itemV.length} 字），最多 $ledgerSplitNameMax 字',
          ),
        );
        continue;
      }
      // 商家名稱必填（2026-11-03 使用者）。
      if (p[3].isEmpty) {
        out.add(ImportLine(line, error: '第 4 欄商家名稱要填'));
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
        final named = accountForImport(p[0], card: false);
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
          confirmed: isCtbcCard(from),
          // 轉給別人（算支出）才有品項名稱；自己帳戶之間轉帳沒有。
          item: target == null ? itemV : '',
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
            duplicateTx: dupTx,
            sameDayOf: sameDayWarn(tx, lineNo),
            beforeStart: start != null && at.isBefore(start),
          ),
        );
        continue;
      }
      // 收入（2026-11-10 使用者：貼上匯入要能記收入——轉帳、ATM存款、薪資轉帳）：分類寫下面這些就是
      // 收入，錢進第 1 欄的帳戶（寫「現金」進現金，其他進銀行）。「轉帳」本來是轉出去，所以收到的轉帳
      // 寫「轉入」。第 6～9 欄的幫誰／對方要給在收入沒有意思，會忽略；餘額（第 9 欄）照樣可以附。
      final inCat = ledgerImportIncomeCat(p[2]);
      if (inCat != null) {
        final named = accountForImport(p[0], card: false);
        final into = named ?? (p[0].contains('現金') ? cash : bank);
        if (into == null) {
          out.add(ImportLine(line, error: '找不到帳戶「${p[0]}」，也沒有銀行帳戶'));
          continue;
        }
        final tx = LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.income,
          occurredAt: at,
          amount: amount,
          accountId: into.id,
          category: inCat,
          merchant: p[3],
          // 收入沒有品項名稱，第 11 欄有字、備註又沒寫就當備註（2026-11-10 使用者：存款入帳）。
          note: noteV.isEmpty && itemV.isNotEmpty ? itemV : noteV,
          source: 'paste',
          raw: line,
        );
        out.add(
          ImportLine(
            line,
            tx: tx,
            after: afterV,
            duplicateOf: dupOf(tx, lineNo),
            duplicateTx: dupTx,
            sameDayOf: sameDayWarn(tx, lineNo),
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
                '（另外可寫「提款」「轉帳」，收入可寫 ${ledgerImportIncome.keys.join("、")}）',
          ),
        );
        continue;
      }
      // 第一欄是帳戶名稱就記在那個帳戶（現金、郵局⋯）；寫「現金」記第一個
      // 現金帳戶；其他（例如「中信銀行」刷卡紀錄）記在第一張信用卡。
      // 提款從銀行出；刷卡支出對到同銀行的信用卡（台新銀行 → 台新卡），對不到才用第一張卡。
      final named = accountForImport(p[0], card: !withdraw);
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
      // 填了「對方要給」或「已給」卻沒填幫誰：不要悄悄當一般消費，報錯提醒。
      final hasExtra = p.skip(6).take(2).any((s) => s.isNotEmpty);
      if (!withdraw && (p.length < 6 || p[5].isEmpty) && hasExtra) {
        out.add(ImportLine(line, error: '填了對方要給／已給，第 6 欄「幫誰」也要填'));
        continue;
      }
      if (!withdraw && p.length >= 6 && p[5].isNotEmpty) {
        if (p.length < 7) {
          out.add(ImportLine(line, error: '填了幫誰，第 7 欄「對方要給多少」也要填'));
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
        // 提款（銀行 → 現金）是轉帳，沒有品項名稱。
        item: withdraw ? '' : itemV,
        note: noteV,
        paidFor: paidFor,
        // 中信卡貼文字的預設已確認（2026-11-11 使用者：貼上出錯機率很低）。
        confirmed: isCtbcCard(from),
        source: 'paste',
        raw: line,
      );
      // 已經記過的、或同一次貼了兩行一樣的，都當重複跳過：同一個帳戶、
      // 同一分鐘、同金額、同商店就算。
      final dup = dupOf(tx, lineNo);
      out.add(
        ImportLine(
          line,
          tx: tx,
          after: afterV,
          duplicateOf: dup,
          duplicateTx: dupTx,
          sameDayOf: sameDayWarn(tx, lineNo),
          beforeStart: start != null && at.isBefore(start),
        ),
      );
    }
    return out;
  }
}
