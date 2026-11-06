import 'dart:convert';

import '../../domain/ledger_calc.dart';
import '../../domain/ledger_log.dart';
import '../../domain/ledger_subscriptions.dart';
import '../../shared/half_width_input.dart';
import '../export/device_label.dart';
import '../../domain/models/ledger.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 記帳（2026-11-03）：帳戶、交易、對帳點、預算四份，各自整包 JSON 讀寫、
/// 各自同步（照 id 合併、比 updatedAt、刪除永遠贏）。刪除一律蓋墓碑，
/// 不然刪掉的交易下次同步會被別台裝置復活。
class LedgerRepository {
  LedgerRepository(this._store);

  static const _accountsKey = 'ledger.accounts.v1';
  static const _txKey = 'ledger.transactions.v1';
  static const _cpKey = 'ledger.checkpoints.v1';
  static const _budgetKey = 'ledger.budgets.v1';
  static const _logKey = 'ledger.log.v1';
  static const _subsKey = 'ledger.subscriptions.v1';

  final KeyValueStore _store;

  Future<List<T>> _load<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final raw = await _store.read(key);
    if (raw == null) return <T>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  Future<void> _save<T>(
    String key,
    List<T> all,
    Map<String, dynamic> Function(T) toJson,
  ) => _store.write(key, jsonEncode([for (final e in all) toJson(e)]));

  Future<List<LedgerAccount>> accountsForUpload() =>
      _load(_accountsKey, LedgerAccount.fromJson);
  Future<List<LedgerTx>> transactionsForUpload() =>
      _load(_txKey, LedgerTx.fromJson);
  Future<List<LedgerCheckpoint>> checkpointsForUpload() =>
      _load(_cpKey, LedgerCheckpoint.fromJson);
  Future<List<LedgerBudget>> budgetsForUpload() =>
      _load(_budgetKey, LedgerBudget.fromJson);

  /// 預設三個帳戶用固定 id：兩台裝置各自第一次打開都會自己建，同步時才會
  /// 合併成同一個、不會變兩份。
  static const _defaults = [
    ('default_bank', '中信活存', LedgerAccountType.bank),
    ('default_card', '中信卡', LedgerAccountType.creditCard),
    ('default_taishin', '台新卡', LedgerAccountType.creditCard),
    ('default_cash', '現金', LedgerAccountType.cash),
  ];

  /// 一次都沒有過帳戶（連刪掉的都沒有）就自動建預設的三個（2026-11-03 使用者：
  /// 記帳就是我這個人的一整本，不用先「開始記帳」建帳戶，也不用填任何餘額；
  /// 不同的卡只是「用哪張付」）。餘額、額度都是之後想對帳才填。
  Future<void> ensureDefaultAccounts() async {
    final all = await accountsForUpload();
    if (all.isNotEmpty) {
      await _addLaterDefaults(all);
      return;
    }
    final now = DateTime.now();
    await _save(_accountsKey, [
      for (final (i, d) in _defaults.indexed)
        LedgerAccount(
          id: d.$1,
          name: d.$2,
          type: d.$3,
          order: i + 1,
          createdAt: now,
          updatedAt: now,
        ),
    ], (e) => e.toJson());
  }

  /// 後來才加進預設的帳戶（2026-11-04 使用者：信用卡多一張台新）：本來就有帳戶的人
  /// 也補上一張，排在最後面。用固定 id 判斷，所以刪掉的（墓碑）不會又長回來；
  /// 自己已經手動建過同名的也不重複建。
  static const _laterDefaults = [
    ('default_taishin', '台新卡', LedgerAccountType.creditCard),
  ];

  Future<void> _addLaterDefaults(List<LedgerAccount> all) async {
    final add = [
      for (final d in _laterDefaults)
        if (!all.any(
          (a) => a.id == d.$1 || (a.deletedAt == null && a.name == d.$2),
        ))
          d,
    ];
    if (add.isEmpty) return;
    final now = DateTime.now();
    var order = all.fold(0, (m, a) => a.order > m ? a.order : m);
    await _save(_accountsKey, [
      ...all,
      for (final d in add)
        LedgerAccount(
          id: d.$1,
          name: d.$2,
          type: d.$3,
          order: ++order,
          createdAt: now,
          updatedAt: now,
        ),
    ], (e) => e.toJson());
  }

  // ── 操作紀錄（2026-11-03 使用者：每個動作都存一份 log，只增不減、永遠不刪）──

  Future<List<LedgerLogEntry>> logForUpload() =>
      _load(_logKey, LedgerLogEntry.fromJson);

  /// 給畫面用：新的在前。
  Future<List<LedgerLogEntry>> loadLog() async =>
      (await logForUpload())..sort((a, b) => b.at.compareTo(a.at));

  /// 記一筆操作。只往後加，沒有任何刪除或裁剪的路。
  Future<void> _log(
    String action,
    String summary, {
    String detail = '',
    String? refId,
  }) async {
    await _save(_logKey, [
      ...await logForUpload(),
      LedgerLogEntry(
        id: ledgerId(),
        at: DateTime.now(),
        action: action,
        summary: summary,
        detail: detail,
        refId: refId,
        device: currentDeviceLabel(),
      ),
    ], (e) => e.toJson());
  }

  /// 帳戶 id → 名稱（log 用；已刪除的帳戶也找得到）。
  Future<String Function(String?)> _acctName() async {
    final m = {for (final a in await accountsForUpload()) a.id: a.name};
    return (id) => id == null ? '無' : (m[id] ?? '（已刪除的帳戶）');
  }

  Future<LedgerBook> loadBook() async {
    await ensureDefaultAccounts();
    return LedgerBook(
      accounts: await accountsForUpload(),
      txs: await transactionsForUpload(),
      checkpoints: await checkpointsForUpload(),
      budgets: await budgetsForUpload(),
    );
  }

  // ── 帳戶 ─────────────────────────────────────────────────

  /// 新增帳戶。有給 [opening] 才在 [openingAt] 存一個期初值的對帳點（銀行／
  /// 現金是餘額；信用卡是可用額度，要有 [creditLimit]）；沒給就先不算餘額，
  /// 之後第一次「填餘額」才開始算（2026-11-03 使用者：戶頭餘額先不用強制填）。
  Future<LedgerAccount> addAccount({
    required String name,
    required LedgerAccountType type,
    int? opening,
    DateTime? openingAt,
    int? creditLimit,
  }) async {
    final now = DateTime.now();
    final all = await accountsForUpload();
    final order = all.fold(0, (m, a) => a.order > m ? a.order : m) + 1;
    final a = LedgerAccount(
      id: ledgerId(),
      name: name,
      type: type,
      creditLimit: type == LedgerAccountType.creditCard ? creditLimit : null,
      order: order,
      createdAt: now,
      updatedAt: now,
    );
    await _save(_accountsKey, [...all, a], (e) => e.toJson());
    await _log('新增帳戶', '${a.type.label}「${a.name}」', refId: a.id);
    if (opening == null || (a.isCard && (creditLimit ?? 0) <= 0)) return a;
    await addCheckpoint(
      LedgerCheckpoint(
        id: ledgerId(),
        accountId: a.id,
        at: openingAt ?? now,
        balance: a.isCard ? null : opening,
        creditLimit: a.isCard ? creditLimit : null,
        available: a.isCard ? opening : null,
        note: '第一次填的餘額',
        updatedAt: now,
      ),
    );
    return a;
  }

  Future<void> updateAccount(LedgerAccount a) async {
    final all = await accountsForUpload();
    final i = all.indexWhere((e) => e.id == a.id);
    if (i < 0) return;
    final old = all[i];
    all[i] = a.copyWith(updatedAt: DateTime.now());
    await _save(_accountsKey, all, (e) => e.toJson());
    await _log(
      '改帳戶',
      '「${old.name}」',
      detail: [
        if (old.name != a.name) '名稱：${old.name} → ${a.name}',
        if (old.creditLimit != a.creditLimit)
          '額度：${old.creditLimit} → ${a.creditLimit}',
      ].join('\n'),
      refId: a.id,
    );
  }

  /// 刪帳戶：帳戶跟它的對帳點蓋墓碑；交易留著（帳戶名稱顯示「已刪除」）。
  Future<void> deleteAccount(String id) async {
    final now = DateTime.now();
    final all = await accountsForUpload();
    final name = all.where((a) => a.id == id).firstOrNull?.name ?? id;
    await _save(_accountsKey, [
      for (final a in all)
        a.id == id ? a.copyWith(updatedAt: now, deletedAt: now) : a,
    ], (e) => e.toJson());
    final cps = await checkpointsForUpload();
    await _save(_cpKey, [
      for (final c in cps)
        c.accountId == id && c.deletedAt == null
            ? c.copyWith(updatedAt: now, deletedAt: now)
            : c,
    ], (e) => e.toJson());
    await _log('刪除帳戶', '「$name」（連同它的對帳點）', refId: id);
  }

  // ── 交易 ─────────────────────────────────────────────────

  Future<void> addTransactions(List<LedgerTx> txs) async {
    if (txs.isEmpty) return;
    final now = DateTime.now();
    await _save(_txKey, [
      ...await transactionsForUpload(),
      for (final t in txs)
        LedgerTx.fromJson({
          ...t.toJson(),
          'createdAt': ledgerTime(now),
          'updatedAt': ledgerTime(now),
        }),
    ], (e) => e.toJson());
    final name = await _acctName();
    for (final t in txs) {
      await _log(
        t.source == 'paste'
            ? '匯入'
            : t.source == 'adjust'
            ? '對帳調整'
            : '新增',
        logTx(t, name),
        detail: [
          if (t.category != null) '分類：${t.category}',
          if (t.isSplit)
            '拆分：${t.splits.map((x) => '${x.category}\$${x.amount}').join('＋')}',
          if (t.note.isNotEmpty) '備註：${t.note}',
          if (t.raw != null) '原文：${t.raw}',
        ].join('\n'),
        refId: t.id,
      );
    }
  }

  Future<void> addTransaction(LedgerTx t) => addTransactions([t]);

  Future<void> updateTransaction(LedgerTx t) async {
    final all = await transactionsForUpload();
    final i = all.indexWhere((e) => e.id == t.id);
    if (i < 0) return;
    final old = all[i];
    all[i] = t.copyWith(updatedAt: DateTime.now());
    await _save(_txKey, all, (e) => e.toJson());
    final name = await _acctName();
    final diff = logDiffTx(old, t, name);
    if (diff.isEmpty) return;
    // 只動標記、或只動「他給了」的，用比較白話的動作名稱。
    final onlyFlag = diff.length == 1 && diff.first.startsWith('標記旗幟');
    final onlySettle =
        diff.length == 1 &&
        diff.first.startsWith('跟別人一起') &&
        old.paidFor != null &&
        t.paidFor != null &&
        old.paidFor!.settled != t.paidFor!.settled;
    await _log(
      onlyFlag
          ? (t.flagged ? '標記旗幟' : '取消標記')
          : onlySettle
          ? (t.paidFor!.settled ? '他給了' : '改回還沒給')
          : '編輯',
      logTx(t, name),
      detail: diff.join('\n'),
      refId: t.id,
    );
  }

  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now();
    final all = await transactionsForUpload();
    final old = all.where((t) => t.id == id).firstOrNull;
    await _save(_txKey, [
      for (final t in all)
        t.id == id ? t.copyWith(updatedAt: now, deletedAt: now) : t,
    ], (e) => e.toJson());
    // 附在這筆上的餘額也一起刪（不然會留下一個沒有交易的對帳點）。
    await clearTxCheckpoints(id);
    if (old != null) {
      await _log('刪除', logTx(old, await _acctName()), refId: id);
    }
  }

  /// 清掉附在某筆交易上的餘額點；[keep] 裡的帳戶留著（改帳戶後清掉舊帳戶的）。
  Future<void> clearTxCheckpoints(
    String txId, {
    Set<String> keep = const {},
  }) async {
    final now = DateTime.now();
    final all = await checkpointsForUpload();
    var changed = false;
    for (var i = 0; i < all.length; i++) {
      final c = all[i];
      if (c.txId != txId || c.deletedAt != null || keep.contains(c.accountId)) {
        continue;
      }
      all[i] = c.copyWith(updatedAt: now, deletedAt: now);
      changed = true;
      await _log('清掉餘額', '附在交易上的餘額 ${c.available ?? c.balance}', refId: txId);
    }
    if (changed) await _save(_cpKey, all, (e) => e.toJson());
  }

  /// 設定／更新／清掉「這筆交易之後帳戶剩多少」（附在交易上的對帳點）。
  /// [value] 是銀行／現金的餘額，信用卡是可用額度（要有 [creditLimit]）；
  /// null＝清掉。時間跟著交易 [at]。
  Future<void> setTxCheckpoint({
    required String txId,
    required String accountId,
    required DateTime at,
    required int? value,
    required int? creditLimit,
    bool isCard = false,
  }) async {
    final now = DateTime.now();
    final all = await checkpointsForUpload();
    // 同一筆交易每個帳戶最多一個餘額點（轉帳兩邊帳戶各一個）。
    final i = all.indexWhere(
      (c) => c.txId == txId && c.accountId == accountId && c.deletedAt == null,
    );
    final oldVal = i < 0 ? null : (all[i].available ?? all[i].balance);
    if (value == null) {
      if (i >= 0) {
        all[i] = all[i].copyWith(updatedAt: now, deletedAt: now);
        await _save(_cpKey, all, (e) => e.toJson());
        await _log('清掉餘額', '附在交易上的餘額 $oldVal', refId: txId);
      }
      return;
    }
    final c = LedgerCheckpoint(
      id: i >= 0 ? all[i].id : ledgerId(),
      accountId: accountId,
      at: at,
      balance: isCard ? null : value,
      creditLimit: isCard ? creditLimit : null,
      available: isCard ? value : null,
      note: '記帳時填的餘額',
      txId: txId,
      updatedAt: now,
    );
    if (i >= 0) {
      all[i] = c;
    } else {
      all.add(c);
    }
    await _save(_cpKey, all, (e) => e.toJson());
    if (oldVal != value) {
      await _log(
        '填餘額（記一筆時）',
        isCard ? '可刷額 \$$value' : '餘額 \$$value',
        detail: oldVal == null ? '' : '$oldVal → $value',
        refId: txId,
      );
    }
  }

  // ── 對帳點 ───────────────────────────────────────────────

  Future<void> addCheckpoint(LedgerCheckpoint c) async {
    await _save(_cpKey, [
      ...await checkpointsForUpload(),
      c.copyWith(updatedAt: DateTime.now()),
    ], (e) => e.toJson());
    final name = await _acctName();
    await _log(
      '對帳／填餘額',
      '${name(c.accountId)}：${c.available != null ? '可刷額 \$${c.available}' : '餘額 \$${c.balance}'}',
      refId: c.id,
    );
  }

  Future<void> updateCheckpoint(LedgerCheckpoint c) async {
    final all = await checkpointsForUpload();
    final i = all.indexWhere((e) => e.id == c.id);
    if (i < 0) return;
    all[i] = c.copyWith(updatedAt: DateTime.now());
    await _save(_cpKey, all, (e) => e.toJson());
    await _log('改對帳點', (await _acctName())(c.accountId), refId: c.id);
  }

  /// 刪掉一次對帳（輸入錯了）；起始日那筆不能刪。
  Future<void> deleteCheckpoint(String id) async {
    final now = DateTime.now();
    final all = await checkpointsForUpload();
    final old = all.where((c) => c.id == id).firstOrNull;
    await _save(_cpKey, [
      for (final c in all)
        c.id == id ? c.copyWith(updatedAt: now, deletedAt: now) : c,
    ], (e) => e.toJson());
    if (old != null) {
      await _log('刪除對帳', (await _acctName())(old.accountId), refId: id);
    }
  }

  // ── 預算 ─────────────────────────────────────────────────

  /// 存某個月的預算：總額＋各分類（0 或沒填＝不限制）。
  ///
  /// 預算的 id 固定是「月份|分類」，所以清掉時**存 0、不蓋墓碑**——同步
  /// 合併是「刪除永遠贏」，蓋了墓碑之後同一個 id 就再也設不回來。
  Future<void> setBudgets(
    String month,
    int total,
    Map<String, int> byCategory,
  ) async {
    final now = DateTime.now();
    final all = {for (final b in await budgetsForUpload()) b.id: b};
    final changes = <String>[];
    void put(String? cat, int v) {
      final id = LedgerBudget.budgetId(month, cat);
      final old = all[id];
      final amount = v < 0 ? 0 : v;
      if (old == null && amount == 0 && cat != null) return;
      if (old != null && old.amount == amount) return;
      changes.add('${cat ?? '整月總額'}：${old?.amount ?? 0} → $amount');
      all[id] = LedgerBudget(
        month: month,
        category: cat,
        amount: amount,
        updatedAt: now,
      );
    }

    put(null, total);
    for (final c in ledgerExpenseCats.keys) {
      if (c == ledgerUncategorized) continue;
      put(c, byCategory[c] ?? 0);
    }
    await _save(_budgetKey, all.values.toList(), (e) => e.toJson());
    if (changes.isNotEmpty) {
      await _log('預算', month, detail: changes.join('\n'));
    }
  }

  // ── 每月訂閱（2026-11-05 使用者：單純紀錄每月幾號扣多少、什麼服務）──────

  Future<List<LedgerSubscription>> subscriptionsForUpload() =>
      _load(_subsKey, LedgerSubscription.fromJson);

  /// 給畫面用：沒刪掉的，訂閱中的在前（照扣款日）。
  Future<List<LedgerSubscription>> loadSubscriptions() async =>
      sortSubs(await subscriptionsForUpload());

  static String _subLine(LedgerSubscription s) =>
      '${s.name}　每月 ${s.day} 號　\$${s.amount}';

  Future<LedgerSubscription> addSubscription({
    required String name,
    required int amount,
    required int day,
    String note = '',
    bool active = true,
  }) async {
    final now = DateTime.now();
    final s = LedgerSubscription(
      id: ledgerId(),
      name: name,
      amount: amount,
      day: day,
      note: note,
      active: active,
      createdAt: now,
      updatedAt: now,
    );
    await _save(_subsKey, [
      ...await subscriptionsForUpload(),
      s,
    ], (e) => e.toJson());
    await _log(
      '新增訂閱',
      _subLine(s),
      detail: [
        if (note.isNotEmpty) '備註：$note',
        if (!active) '狀態：已停用',
      ].join('\n'),
      refId: s.id,
    );
    return s;
  }

  Future<void> updateSubscription(LedgerSubscription s) async {
    final all = await subscriptionsForUpload();
    final i = all.indexWhere((x) => x.id == s.id);
    if (i < 0) return;
    final old = all[i];
    all[i] = s.copyWith(updatedAt: DateTime.now());
    await _save(_subsKey, all, (e) => e.toJson());
    String n(String v) => v.isEmpty ? '（空）' : v;
    final diff = [
      if (old.name != s.name) '名稱：${old.name} → ${s.name}',
      if (old.amount != s.amount) '金額：\$${old.amount} → \$${s.amount}',
      if (old.day != s.day) '每月幾號：${old.day} → ${s.day}',
      if (old.note != s.note) '備註：${n(old.note)} → ${n(s.note)}',
      if (old.active != s.active) '狀態：${s.active ? '恢復訂閱' : '停用'}',
    ];
    final onlyActive = diff.length == 1 && old.active != s.active; // 只切了訂閱中／停用
    await _log(
      onlyActive ? (s.active ? '恢復訂閱' : '停用訂閱') : '編輯訂閱',
      _subLine(s),
      detail: diff.join('\n'),
      refId: s.id,
    );
  }

  Future<void> deleteSubscription(String id) async {
    final now = DateTime.now();
    final all = await subscriptionsForUpload();
    final gone = all.where((e) => e.id == id).firstOrNull;
    await _save(_subsKey, [
      for (final e in all)
        e.id == id ? e.copyWith(updatedAt: now, deletedAt: now) : e,
    ], (e) => e.toJson());
    if (gone != null) await _log('刪除訂閱', _subLine(gone), refId: id);
  }

  // ── 整理全形文字（2026-11-06 使用者：之前輸入的全形英數字一次改成半形小寫）──
  // 暫時的工具：處理完舊資料之後會拿掉設定裡的按鈕。

  /// 把所有已存的記帳文字裡的全形英數字改成半形小寫（`ＦＯＯＤＰＡＮＤＡ` → `foodpanda`）：
  /// 交易的商家、備註、幫誰、拆分的品項名稱跟幫誰，帳戶名稱，訂閱的名稱、備註。
  /// 只動有全形字的欄位（改完順便去前後空白），其他不碰。改到的紀錄更新 updatedAt，
  /// 同步時其他裝置會帶過去；整件事在操作紀錄記一筆（寫每個欄位 舊 → 新）。
  /// 回傳改了幾筆（交易＋帳戶＋訂閱）。
  Future<int> normalizeFullWidthText() async {
    String fix(String s) {
      final n = HalfWidthTextFormatter.normalize(s);
      return n == s ? s : n.trim();
    }

    final now = DateTime.now();
    final lines = <String>[];
    void note(String where, String a, String b) {
      if (a != b) lines.add('$where：$a → $b');
    }

    var txCount = 0, acctCount = 0, subCount = 0;

    final txs = await transactionsForUpload();
    final newTxs = <LedgerTx>[];
    for (final t in txs) {
      if (t.deletedAt != null) {
        newTxs.add(t);
        continue;
      }
      final merchant = fix(t.merchant);
      final memo = fix(t.note);
      final pf = t.paidFor;
      final people = pf == null ? null : fix(pf.people);
      final splits = [
        for (final s in t.splits)
          LedgerSplit(
            category: s.category,
            amount: s.amount,
            name: fix(s.name),
            forOther: s.forOther,
            settled: s.settled,
            people: fix(s.people),
          ),
      ];
      var splitChanged = false;
      for (var i = 0; i < splits.length; i++) {
        if (splits[i].name != t.splits[i].name ||
            splits[i].people != t.splits[i].people) {
          splitChanged = true;
          note('拆分品項', t.splits[i].name, splits[i].name);
          note('拆分幫誰', t.splits[i].people, splits[i].people);
        }
      }
      final changed =
          merchant != t.merchant ||
          memo != t.note ||
          (pf != null && people != pf.people) ||
          splitChanged;
      if (!changed) {
        newTxs.add(t);
        continue;
      }
      note('商家', t.merchant, merchant);
      note('備註', t.note, memo);
      if (pf != null) note('幫誰', pf.people, people!);
      txCount++;
      newTxs.add(
        t.copyWith(
          merchant: merchant,
          note: memo,
          paidFor: pf == null
              ? null
              : () => PaidFor(
                  amount: pf.amount,
                  people: people!,
                  settled: pf.settled,
                ),
          splits: splits,
          updatedAt: now,
        ),
      );
    }
    if (txCount > 0) await _save(_txKey, newTxs, (e) => e.toJson());

    final accounts = await accountsForUpload();
    final newAccounts = <LedgerAccount>[];
    for (final a in accounts) {
      final name = a.deletedAt != null ? a.name : fix(a.name);
      if (name == a.name) {
        newAccounts.add(a);
        continue;
      }
      note('帳戶名稱', a.name, name);
      acctCount++;
      newAccounts.add(a.copyWith(name: name, updatedAt: now));
    }
    if (acctCount > 0) {
      await _save(_accountsKey, newAccounts, (e) => e.toJson());
    }

    final subs = await subscriptionsForUpload();
    final newSubs = <LedgerSubscription>[];
    for (final s in subs) {
      final name = s.deletedAt != null ? s.name : fix(s.name);
      final memo = s.deletedAt != null ? s.note : fix(s.note);
      if (name == s.name && memo == s.note) {
        newSubs.add(s);
        continue;
      }
      note('訂閱名稱', s.name, name);
      note('訂閱備註', s.note, memo);
      subCount++;
      newSubs.add(s.copyWith(name: name, note: memo, updatedAt: now));
    }
    if (subCount > 0) {
      await _save(_subsKey, newSubs, (e) => e.toJson());
    }

    final total = txCount + acctCount + subCount;
    // 什麼都沒改就不吵操作紀錄。
    if (total > 0) {
      await _log(
        '整理全形文字',
        '改了 $txCount 筆交易、$acctCount 個帳戶、$subCount 個訂閱',
        detail: lines.join('\n'),
      );
    }
    return total;
  }

  Future<int> mergeSubscriptionsFromCloud(List<LedgerSubscription> incoming) =>
      _merge(
        _subsKey,
        incoming,
        LedgerSubscription.fromJson,
        (e) => e.toJson(),
        (e) => e.id,
        (e) => e.syncedAt,
        (e) => e.deletedAt,
      );

  // ── 同步：把雲端的併回本機，回傳實際異動幾筆 ─────────────

  Future<int> _merge<T>(
    String key,
    List<T> incoming,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson,
    String Function(T) idOf,
    DateTime Function(T) updatedAtOf,
    DateTime? Function(T) deletedAtOf,
  ) async {
    if (incoming.isEmpty) return 0;
    final before = await _load(key, fromJson);
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: idOf,
      priority: SeedMergePriority.local,
      deletedAtOf: deletedAtOf,
      updatedAtOf: updatedAtOf,
    );
    await _save(key, merged, toJson);
    return ytDiffCount(
      [for (final e in before) toJson(e)],
      [for (final e in merged) toJson(e)],
    );
  }

  Future<int> mergeAccountsFromCloud(List<LedgerAccount> incoming) => _merge(
    _accountsKey,
    incoming,
    LedgerAccount.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );

  Future<int> mergeTransactionsFromCloud(List<LedgerTx> incoming) => _merge(
    _txKey,
    incoming,
    LedgerTx.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );

  Future<int> mergeCheckpointsFromCloud(List<LedgerCheckpoint> incoming) =>
      _merge(
        _cpKey,
        incoming,
        LedgerCheckpoint.fromJson,
        (e) => e.toJson(),
        (e) => e.id,
        (e) => e.syncedAt,
        (e) => e.deletedAt,
      );

  /// 操作紀錄：兩邊直接聯集（照 id），不刪、不裁。
  Future<int> mergeLogFromCloud(List<LedgerLogEntry> incoming) => _merge(
    _logKey,
    incoming,
    LedgerLogEntry.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => null,
  );

  Future<int> mergeBudgetsFromCloud(List<LedgerBudget> incoming) => _merge(
    _budgetKey,
    incoming,
    LedgerBudget.fromJson,
    (e) => e.toJson(),
    (e) => e.id,
    (e) => e.syncedAt,
    (e) => e.deletedAt,
  );
}
