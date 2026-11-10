import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import 'ledger_sheets.dart';
import 'ledger_ui.dart';

/// 記帳的資料跟每個動作的流程：表單回傳之後在這裡存、通知、開下一張
/// （例如對帳 → 結果 → 補記 → 回到結果 → 下一個帳戶）。

/// 看 [dataRevisionProvider]：任何改動後 bump，各分頁一起重算；雲端同步
/// 帶回資料也會 bump。
final ledgerBookProvider = FutureProvider.autoDispose<LedgerBook>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.read(ledgerRepositoryProvider).loadBook();
});

void _bump(WidgetRef ref) => ref.read(dataRevisionProvider.notifier).state++;

Future<LedgerBook> _fresh(WidgetRef ref) =>
    ref.read(ledgerRepositoryProvider).loadBook();

/// 第一次打開：建帳戶（餘額選填，2026-11-03 使用者拿掉起始日）。
Future<void> setupFlow(BuildContext context, WidgetRef ref) async {
  final r = await showSetupSheet(context);
  if (r == null) return;
  final repo = ref.read(ledgerRepositoryProvider);
  for (final a in r) {
    await repo.addAccount(
      name: a.name,
      type: a.type,
      opening: a.opening,
      creditLimit: a.limit,
    );
  }
  _bump(ref);
  if (context.mounted) {
    showAppNotice(context, '開始記帳了', detail: '${r.length} 個帳戶，按右下角 ＋ 記第一筆');
  }
}

Future<void> addAccountFlow(BuildContext context, WidgetRef ref) async {
  final r = await showAccountFormSheet(context);
  if (r == null) return;
  await ref
      .read(ledgerRepositoryProvider)
      .addAccount(
        name: r.name,
        type: r.type,
        opening: r.opening,
        creditLimit: r.limit,
      );
  _bump(ref);
  if (context.mounted) showAppNotice(context, '已新增帳戶：${r.name}');
}

/// 記一筆（或編輯）。[wizardNext] 有值＝這是一次對帳流程中的補記，存完回到
/// 對帳結果。
Future<void> txFormFlow(
  BuildContext context,
  WidgetRef ref, {
  LedgerTx? edit,
  TxPrefill prefill = const TxPrefill(),
  bool inWizard = false,
}) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  if (!book.isSetUp) return setupFlow(context, ref);
  // 貼文字偵測到已經記過同一筆：表單關掉，直接改成編輯那一筆。
  LedgerTx? switchTo;
  final r0 = await showTxFormSheet(
    context,
    book,
    edit: edit,
    prefill: prefill,
    onSwitchEdit: edit == null ? (t) => switchTo = t : null,
  );
  if (switchTo != null) {
    if (!context.mounted) return;
    showAppNotice(
      context,
      '已經有同一筆，直接改成編輯它',
      detail: '「${LedgerBook.describe(switchTo!)}」（同帳戶、同一分鐘、同金額）',
    );
    return txFormFlow(context, ref, edit: switchTo, inWizard: inWizard);
  }
  if (r0 == null || !context.mounted) return;
  var r = r0;
  // 金額剛好 110 或 1100、分類又不是菸酒：問要不要改成菸酒（設定可關）。編輯時沒動金額跟分類就不再問。
  final t0 = r.tx;
  if (ref.read(ledgerSinAskProvider) &&
      t0.type == LedgerTxType.expense &&
      !t0.isSplit &&
      t0.category != '菸酒' &&
      (t0.amount == 110 || t0.amount == 1100) &&
      !(edit != null &&
          edit.amount == t0.amount &&
          edit.category == t0.category)) {
    final yes = await showAppConfirmDialog(
      context,
      title: '要改成菸酒嗎？',
      message:
          '這筆是 NT\$${t0.amount}，目前分類是「${t0.category ?? ledgerUncategorized}」。要改成「菸酒」嗎？',
      confirmLabel: '改成菸酒',
      cancelLabel: '不用',
      destructive: false,
    );
    if (!context.mounted) return;
    if (yes) {
      r = (
        tx: t0.copyWith(category: () => '菸酒'),
        settleLinked: r.settleLinked,
        after: r.after,
        afterTo: r.afterTo,
      );
    }
  }
  // 防重複（2026-11-03 使用者）：同帳戶、同一分鐘、同金額、同商店（2026-11-10）的已經有了，就提示
  // 跟哪一筆相同、不新增。
  final dup = book.sameMinute(
    r.tx.accountId,
    r.tx.occurredAt,
    r.tx.amount,
    exceptId: edit?.id,
    merchant: r.tx.merchant,
  );
  if (dup != null) {
    if (context.mounted) {
      showAppNotice(
        context,
        '跟「${LedgerBook.describe(dup)}」相同，${edit == null ? '沒有新增' : '沒有儲存'}',
        detail: '同帳戶、同一分鐘、同金額、同商店；真的是兩筆就把時間改一分鐘',
        isError: true,
      );
    }
    return;
  }
  final repo = ref.read(ledgerRepositoryProvider);
  if (edit == null) {
    await repo.addTransaction(r.tx);
  } else {
    await repo.updateTransaction(r.tx);
  }
  // 這筆之後帳戶剩多少（選填）：附一個對帳點在這筆上；清空就拿掉。轉帳（含繳卡費）
  // 兩邊帳戶可以各填一個（2026-11-03 使用者）。
  final kept = <String>{};
  Future<void> attach(String? accountId, int? value) async {
    final acc = book.account(accountId);
    if (acc == null) return;
    // 總額度不用填：抓漏記只比可刷餘額，總額度會抵掉。
    final limit = acc.creditLimit ?? book.stateOf(acc)?.limit;
    await repo.setTxCheckpoint(
      txId: r.tx.id,
      accountId: acc.id,
      at: r.tx.occurredAt,
      value: value,
      creditLimit: limit,
      isCard: acc.isCard,
    );
    if (value != null) kept.add(acc.id);
  }

  await attach(r.tx.accountId, r.after);
  if (r.tx.type == LedgerTxType.transfer) {
    await attach(r.tx.toAccountId, r.afterTo);
  }
  // 編輯時換了帳戶：舊帳戶的餘額點拿掉。
  if (edit != null) await repo.clearTxCheckpoints(r.tx.id, keep: kept);
  if (r.settleLinked) {
    final o = book.tx(r.tx.linkedId);
    if (o?.paidFor != null) {
      await repo.updateTransaction(o!.withSettled(true));
    }
  }
  _bump(ref);
  if (!context.mounted) return;
  final cp = prefill.cpId;
  if (cp != null) {
    final after = await _fresh(ref);
    final acc = after.account(r.tx.accountId);
    final s = acc == null ? null : after.stateOf(acc);
    if (!context.mounted) return;
    showAppNotice(
      context,
      s?.miss == 0 ? '✓ 差額補上了，帳對了' : '已補記',
      detail: s == null || s.miss == 0 ? null : '還差 ${lMoney(s.miss.abs())}',
    );
    if (inWizard && acc != null) {
      await reconResultFlow(context, ref, acc, wizard: true);
    }
    return;
  }
  // 填了餘額的話，看這筆跟上一個餘額比有沒有缺（漏記）。
  final gap = r.after == null && r.afterTo == null
      ? null
      : (await _fresh(ref)).gapOfTx(r.tx.id);
  // 當天已經有相同金額的其他筆（不看帳戶）：只提醒、不擋下（2026-11-03 使用者）。
  final same = book.sameDayAmount(
    r.tx.occurredAt,
    r.tx.amount,
    exceptId: r.tx.id,
  );
  if (!context.mounted) return;
  final sameNote = same.isEmpty
      ? null
      : '提醒：當天已經有 ${same.length} 筆一樣是 ${lMoney(r.tx.amount)}：'
            '${same.take(2).map(LedgerBook.describe).join('、')}'
            '${same.length > 2 ? '⋯' : ''}，確認不是重複記的';
  showAppNotice(
    context,
    gap != null
        ? '⚠ 這筆掛上「${gap.miss > 0 ? '漏記' : '多出'} ${lMoney(gap.miss.abs())}」'
        : sameNote != null
        ? '⚠ 已記，但當天有相同金額的一筆'
        : edit != null
        ? '已更新'
        : r.tx.type == LedgerTxType.repayment
        ? '🤝 已記還款（不算收入）'
        : '已記一筆',
    detail: [
      if (gap != null) '跟上一個餘額對不上，補上漏掉的那筆標籤就會消失',
      ?sameNote,
      if (gap == null && sameNote == null && edit == null)
        '${r.tx.merchant.isEmpty ? r.tx.type.label : r.tx.merchant} ${lMoney(r.tx.amount)}',
    ].join('\n').ifEmptyNull,
  );
}

/// 點一筆交易：看明細，按了哪個動作就去做。
Future<void> txDetailFlow(
  BuildContext context,
  WidgetRef ref,
  String txId,
) async {
  final book = await _fresh(ref);
  final t = book.tx(txId);
  if (t == null || !context.mounted) return;
  final a = await showTxDetailSheet(context, book, t);
  if (a == null || !context.mounted) return;
  final repo = ref.read(ledgerRepositoryProvider);
  switch (a.kind) {
    case 'open':
      await txDetailFlow(context, ref, a.id!);
    case 'flag':
      await repo.updateTransaction(t.copyWith(flagged: !t.flagged));
      _bump(ref);
      if (context.mounted) {
        showAppNotice(context, t.flagged ? '已取消標記' : '🚩 已標記旗幟');
      }
    case 'edit':
      await txFormFlow(context, ref, edit: t);
    case 'refund':
      await txFormFlow(
        context,
        ref,
        prefill: TxPrefill(type: LedgerTxType.refund, linkedId: t.id),
      );
    case 'repay':
      await txFormFlow(
        context,
        ref,
        prefill: TxPrefill(type: LedgerTxType.repayment, linkedId: t.id),
      );
    case 'settle':
      await settleFlow(context, ref, t, true);
    case 'unsettle':
      await settleFlow(context, ref, t, false);
    case 'hintMove':
    case 'hintAccount':
    case 'hintRefund':
      // 缺的數字剛好對得上某一筆：id＝「那筆的 id｜餘額點的 id」。
      final parts = (a.id ?? '').split('|');
      final other = book.tx(parts.first);
      final cp = book.checkpoints.where((c) => c.id == parts.last).firstOrNull;
      if (other == null || cp == null) return;
      if (a.kind == 'hintRefund') {
        await txFormFlow(
          context,
          ref,
          prefill: TxPrefill(
            type: LedgerTxType.refund,
            linkedId: other.id,
            at: book.fixTimeFor(cp),
          ),
        );
        return;
      }
      await repo.updateTransaction(
        a.kind == 'hintMove'
            ? other.copyWith(occurredAt: book.fixTimeFor(cp))
            : other.copyWith(accountId: cp.accountId),
      );
      _bump(ref);
      if (context.mounted) {
        final gap = (await _fresh(ref)).gapOfTx(t.id);
        if (!context.mounted) return;
        showAppNotice(
          context,
          gap == null
              ? '✓ 改好了，這筆的漏記標籤消失了'
              : '已改，這筆還有 ${lMoney(gap.miss.abs())} 對不上',
        );
      }
    case 'fixAddCp':
    case 'fixAdjustCp':
      // 這筆記餘額時對不上：補記漏掉的那筆，或直接調成未分類。
      final acc = book.account(t.accountId);
      if (acc == null) return;
      if (a.kind == 'fixAddCp') {
        await fixAddFlow(context, ref, acc, cpId: a.id);
      } else {
        await fixAdjustFlow(context, ref, acc, cpId: a.id);
      }
    case 'delete':
      final ok = await showAppConfirmDialog(
        context,
        title: '刪除這筆？',
        message:
            '${t.merchant.isEmpty ? t.type.label : t.merchant} ${lMoney(t.amount)}，'
            '刪除後不算進消費跟對帳。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.deleteTransaction(t.id);
      _bump(ref);
      if (context.mounted) showAppNotice(context, '已刪除');
  }
}

Future<void> settleFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerTx t,
  bool settled,
) async {
  final pf = t.paidFor;
  if (pf == null) return;
  final repo = ref.read(ledgerRepositoryProvider);
  // 「他給了」：只標記，或順便記錢進哪個戶頭（要對帳的戶頭才需要）。
  String? depositTo, depositName;
  if (settled) {
    final book = await _fresh(ref);
    if (!context.mounted) return;
    final a = await showSettleSheet(context, book, t);
    if (a == null) return;
    if (a.kind == 'deposit') {
      depositTo = a.id;
      depositName = book.accountName(depositTo);
    }
    final left = pf.amount - book.repaidOf(t.id);
    if (depositTo != null && left > 0) {
      await repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.repayment,
          occurredAt: DateTime.now(),
          amount: left,
          accountId: depositTo,
          linkedId: t.id,
          merchant: '${pf.people} 給錢',
        ),
      );
    }
  }
  await repo.updateTransaction(t.withSettled(settled));
  _bump(ref);
  if (context.mounted) {
    showAppNotice(
      context,
      settled ? '👥 ${pf.people} 給了 ✓' : '已改回還沒給',
      detail: depositName == null ? null : '記進 $depositName（不算收入）',
    );
  }
}

// ── 對帳 ─────────────────────────────────────────────────

/// 對一個帳戶。[wizard]＝一次對帳（三個帳戶依序對完）。
Future<void> reconFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerAccount account, {
  bool wizard = false,
}) async {
  final book = await _fresh(ref);
  final acc = book.account(account.id);
  if (acc == null || !context.mounted) return;
  // null＝還沒填過餘額，這次是第一次填（從現在開始算）。
  final before = book.stateOf(acc);
  final i = book.accounts.indexWhere((a) => a.id == acc.id);
  final cp = await showReconSheet(
    context,
    book,
    acc,
    step: wizard ? (i + 1, book.accounts.length) : null,
  );
  if (cp == null) return;
  final repo = ref.read(ledgerRepositoryProvider);
  await repo.addCheckpoint(cp);
  if (acc.isCard &&
      cp.creditLimit != null &&
      cp.creditLimit != acc.creditLimit) {
    await repo.updateAccount(acc.copyWith(creditLimit: cp.creditLimit));
  }
  _bump(ref);
  if (before == null) {
    if (!context.mounted) return;
    showAppNotice(context, '已記下${acc.name}的餘額', detail: '從現在開始幫你算');
    final next = wizard && i + 1 < book.accounts.length
        ? book.accounts[i + 1]
        : null;
    if (next != null) await reconFlow(context, ref, next, wizard: true);
    return;
  }
  final thisMiss = LedgerBook.missOf(
    acc,
    LedgerBook.checkpointValue(acc, cp),
    before.now,
  );
  if (!context.mounted) return;
  await reconResultFlow(context, ref, acc, wizard: wizard, thisMiss: thisMiss);
}

Future<void> reconAllFlow(BuildContext context, WidgetRef ref) async {
  final book = await _fresh(ref);
  if (!context.mounted || book.accounts.isEmpty) return;
  await reconFlow(context, ref, book.accounts.first, wizard: true);
}

Future<void> reconResultFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerAccount account, {
  bool wizard = false,
  int? thisMiss,
}) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  final i = book.accounts.indexWhere((a) => a.id == account.id);
  final next = wizard && i >= 0 && i + 1 < book.accounts.length
      ? book.accounts[i + 1]
      : null;
  final a = await showReconResultSheet(
    context,
    book,
    account,
    thisMiss: thisMiss,
    next: next,
  );
  if (a == null || !context.mounted) return;
  switch (a.kind) {
    case 'next':
      await reconFlow(context, ref, next!, wizard: true);
    case 'fixAdd':
      await fixAddFlow(context, ref, account, inWizard: wizard);
    case 'fixAdjust':
      await fixAdjustFlow(context, ref, account);
      if (context.mounted) {
        await reconResultFlow(context, ref, account, wizard: wizard);
      }
    case 'leave':
      if (next != null) await reconFlow(context, ref, next, wizard: true);
  }
}

/// 要補哪個差額：預設是帳戶最後一次對帳；給 [cpId] 就是那個餘額點（記一筆時
/// 附在交易上的那種，2026-11-03），時間放在它跟上一個餘額中間。
({LedgerCheckpoint cp, int miss, DateTime at})? _fixTarget(
  LedgerBook book,
  LedgerAccount account,
  String? cpId,
) {
  if (cpId != null) {
    final c = book.checkpoints.where((x) => x.id == cpId).firstOrNull;
    final d = c == null ? null : book.checkpointDiff(account, c);
    if (c == null || d == null || d.miss == 0) return null;
    return (cp: c, miss: d.miss, at: book.fixTimeFor(c));
  }
  final s = book.stateOf(account);
  if (s == null || s.miss == 0) return null;
  return (
    cp: s.last,
    miss: s.miss,
    at: s.last.at.subtract(const Duration(minutes: 1)),
  );
}

/// 補記一筆：金額先填差額、時間設在對帳（餘額）之前。
Future<void> fixAddFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerAccount account, {
  bool inWizard = false,
  String? cpId,
}) async {
  final book = await _fresh(ref);
  final t = _fixTarget(book, account, cpId);
  if (t == null || !context.mounted) return;
  await txFormFlow(
    context,
    ref,
    inWizard: inWizard,
    prefill: TxPrefill(
      type: t.miss > 0 ? LedgerTxType.expense : LedgerTxType.income,
      amount: t.miss.abs(),
      accountId: account.id,
      category: t.miss > 0 ? ledgerUncategorized : '其他收入',
      at: t.at,
      cpId: t.cp.id,
    ),
  );
}

/// 直接調成一筆未分類（少了錢＝未分類支出；多出來＝調整進來）。
Future<void> fixAdjustFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerAccount account, {
  String? cpId,
}) async {
  final book = await _fresh(ref);
  final t = _fixTarget(book, account, cpId);
  if (t == null) return;
  await ref
      .read(ledgerRepositoryProvider)
      .addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.adjustment,
          dir: t.miss > 0 ? 'out' : 'in',
          occurredAt: t.at,
          amount: t.miss.abs(),
          accountId: account.id,
          category: ledgerUncategorized,
          merchant: '${account.name}對帳差額',
          note: t.miss > 0 ? '想不起來是什麼，直接調成未分類' : '多出來的錢，直接調整',
          source: 'adjust',
          cpId: t.cp.id,
        ),
      );
  _bump(ref);
  if (context.mounted) showAppNotice(context, '⚖️ 已調整，帳對了');
}

/// 點帳戶：明細、對帳紀錄、差額處理、改名、刪除。
Future<void> accountFlow(
  BuildContext context,
  WidgetRef ref,
  LedgerAccount account,
) async {
  final book = await _fresh(ref);
  final acc = book.account(account.id);
  if (acc == null || !context.mounted) return;
  final a = await showAccountSheet(context, book, acc);
  if (a == null || !context.mounted) return;
  final repo = ref.read(ledgerRepositoryProvider);
  switch (a.kind) {
    case 'recon':
      await reconFlow(context, ref, acc);
    case 'fixAdd':
      await fixAddFlow(context, ref, acc);
    case 'fixAdjust':
      await fixAdjustFlow(context, ref, acc);
    case 'open':
      await txDetailFlow(context, ref, a.id!);
    case 'edit':
      final r = await showAccountFormSheet(context, edit: acc);
      if (r == null) return;
      await repo.updateAccount(
        acc.copyWith(name: r.name, creditLimit: r.limit ?? acc.creditLimit),
      );
      _bump(ref);
    case 'deleteCp':
      final ok = await showAppConfirmDialog(
        context,
        title: '刪掉這次對帳？',
        message: '輸入錯了才刪；刪掉之後差額會照上一次對帳重算。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.deleteCheckpoint(a.id!);
      _bump(ref);
      if (context.mounted) showAppNotice(context, '已刪掉這次對帳');
    case 'delete':
      final ok = await showAppConfirmDialog(
        context,
        title: '刪除帳戶「${acc.name}」？',
        message: '帳戶跟它的對帳紀錄會刪掉；記過的交易還留著，帳戶名稱會顯示「已刪除」。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.deleteAccount(acc.id);
      _bump(ref);
      if (context.mounted) showAppNotice(context, '已刪除帳戶：${acc.name}');
  }
}

// ── 其他 ─────────────────────────────────────────────────

Future<void> budgetFlow(
  BuildContext context,
  WidgetRef ref,
  int year,
  int month,
) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  final r = await showBudgetSheet(context, book, year, month);
  if (r == null) return;
  await ref
      .read(ledgerRepositoryProvider)
      .setBudgets(monthKey(year, month), r.total, r.byCategory);
  _bump(ref);
  if (context.mounted) showAppNotice(context, '🎯 $month 月預算已更新');
}

Future<void> importFlow(BuildContext context, WidgetRef ref) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  if (!book.isSetUp) return setupFlow(context, ref);
  final before = {for (final s in book.states) s.account.id: s.miss};
  final r = await showImportSheet(context, book);
  if (r == null || r.txs.isEmpty) return;
  final repo = ref.read(ledgerRepositoryProvider);
  await repo.addTransactions(r.txs);
  // 第 9 欄的「這筆之後餘額」：附在那筆交易上。
  for (final t in r.txs) {
    final v = r.afters[t.id];
    final acc = book.account(t.accountId);
    if (v == null || acc == null) continue;
    final limit = acc.creditLimit ?? book.stateOf(acc)?.limit;
    await repo.setTxCheckpoint(
      txId: t.id,
      accountId: acc.id,
      at: t.occurredAt,
      value: v,
      creditLimit: limit,
      isCard: acc.isCard,
    );
  }
  _bump(ref);
  final after = await _fresh(ref);
  final fixed = [
    for (final s in after.states)
      if ((before[s.account.id] ?? 0) != 0 && s.miss == 0) s.account.name,
  ];
  final gaps = r.txs.where((t) => after.gapOfTx(t.id) != null).length;
  if (context.mounted) {
    // 重複的沒有加，要講清楚是跟哪一筆相同（2026-11-03 使用者）。
    showAppNotice(
      context,
      '📋 匯入 ${r.txs.length} 筆'
      '${r.skipped.isEmpty ? '' : '，${r.skipped.length} 筆重複沒有加'}',
      detail: [
        ...r.skipped.take(3),
        if (r.sameDay.isNotEmpty)
          '⚠ ${r.sameDay.length} 筆當天有相同金額（已匯入，請確認）：${r.sameDay.take(2).join('、')}',
        if (r.skipped.length > 3) '還有 ${r.skipped.length - 3} 筆',
        if (fixed.isNotEmpty) '${fixed.join('、')}的差額補上了 ✓',
        if (gaps > 0) '⚠ $gaps 筆餘額對不上，標了「漏記」，補上就消失',
      ].join('\n').ifEmptyNull,
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

Future<void> flagsFlow(BuildContext context, WidgetRef ref) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  final a = await showTxListSheet(
    context,
    book,
    title: '🚩 標記旗幟',
    txs: book.flagged,
    emptyText: '沒有標記的紀錄',
  );
  if (a?.kind == 'open' && context.mounted) {
    await txDetailFlow(context, ref, a!.id!);
  }
}

/// 首頁「幫誰付過」卡片：列出所有幫別人付的交易（跟標記旗幟同一種做法）。
Future<void> paidForFlow(BuildContext context, WidgetRef ref) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  final a = await showTxListSheet(
    context,
    book,
    title: '👥 幫誰付過',
    txs: book.paidForOthers,
    emptyText: '還沒有幫別人付過的紀錄',
  );
  if (a?.kind == 'open' && context.mounted) {
    await txDetailFlow(context, ref, a!.id!);
  }
}

Future<void> categoryFlow(
  BuildContext context,
  WidgetRef ref,
  String cat,
  int year,
  int month,
) async {
  final book = await _fresh(ref);
  if (!context.mounted) return;
  final inM = LedgerBook.inMonth(year, month);
  final txs = book.txs.where(inM).where((t) {
    if (t.type == LedgerTxType.expense) {
      return book.categoriesOf(t).contains(cat);
    }
    if (t.type == LedgerTxType.adjustment) {
      return cat == ledgerUncategorized && t.isAdjustOut;
    }
    if (t.type == LedgerTxType.refund) {
      return book.categoriesOf(t).contains(cat) ||
          (book.tx(t.linkedId) == null && cat == ledgerUncategorized);
    }
    return false;
  }).toList();
  final spent = book.monthStats(year, month).byCategory[cat] ?? 0;
  final budget = book.budgetOf(year, month).byCategory[cat];
  final a = await showTxListSheet(
    context,
    book,
    title: '${catLook(cat).$1} $cat・$month 月',
    txs: txs,
    header: budgetHeader(spent, budget),
    footerLabel: '調整預算',
  );
  if (a == null || !context.mounted) return;
  if (a.kind == 'open') {
    await txDetailFlow(context, ref, a.id!);
  } else if (a.kind == 'footer') {
    await budgetFlow(context, ref, year, month);
  }
}
