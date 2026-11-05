import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_menu.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'ledger_data.dart';
import 'ledger_ui.dart';

/// 記帳（Lume 自己用的，2026-11-03 使用者從
/// `design-history/記帳功能設計/2026-11-03_記帳（帳戶＋對帳）五種設計.html`
/// 挑了版本 1「分頁式記帳 App（主流）」）。下方膠囊四個分頁：首頁／明細／
/// 統計／帳戶（各自一個網址，分頁列在 `app_bottom_nav.dart`），右下角 ＋
/// 記一筆。算法照 `docs/記帳功能構想.md`。
enum LedgerTab {
  home('/ledger', '記帳'),
  list('/ledger/list', '明細'),
  stats('/ledger/stats', '統計'),
  accounts('/ledger/accounts', '帳戶');

  const LedgerTab(this.path, this.title);

  final String path;
  final String title;
}

/// 看哪個月（四個分頁共用，切分頁不會跳回這個月）。
final ledgerMonthProvider = StateProvider<DateTime>(
  (_) => DateTime(DateTime.now().year, DateTime.now().month),
);

/// 明細的篩選：只看 🚩、只看某個帳戶。
final ledgerFilterProvider =
    StateProvider<({bool flagged, String? accountId, String? category})>(
      (_) => (flagged: false, accountId: null, category: null),
    );

/// 明細頂部的搜尋字（2026-11-03 使用者）：有字的時候搜全部月份、每個欄位都搜。
final ledgerSearchProvider = StateProvider<String>((_) => '');

/// 明細查看的時間範圍（2026-11-03 使用者：要能選全部，才能看菸酒之類總共花多少）：
/// 單一個月（用 [ledgerMonthProvider]）、整年、全部時間。
enum LedgerRange { month, year, all }

final ledgerRangeProvider = StateProvider<LedgerRange>(
  (_) => LedgerRange.month,
);

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key, required this.tab});

  final LedgerTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(ledgerBookProvider).valueOrNull;
    final inset = FloatingNavInset.of(context);
    return Scaffold(
      drawer: const AppSideDrawer(),
      floatingActionButton: book == null || !book.isSetUp
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: FloatingActionButton(
                onPressed: () => txFormFlow(context, ref),
                tooltip: '記一筆',
                backgroundColor: ledgerAccent,
                foregroundColor: const Color(0xFF08130E),
                child: const Icon(Icons.add_rounded),
              ),
            ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: tab.title,
                  titleIcon: Icons.receipt_long_outlined,
                  titleIconColor: ledgerAccent,
                  showBack: false,
                  // 貼上文字匯入放在每個分頁右上角（原本藏在「帳戶」最下面的
                  // 工具裡，使用者找不到）。
                  actions: [
                    IconButton(
                      onPressed: () => importFlow(context, ref),
                      icon: const Icon(Icons.content_paste_rounded, size: 22),
                      color: AppColors.ink2,
                      tooltip: '貼上文字匯入',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: book == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          padding: EdgeInsets.only(bottom: 96 + inset),
                          children: !book.isSetUp
                              ? _notSetUp(context, ref)
                              : switch (tab) {
                                  LedgerTab.home => _home(context, ref, book),
                                  LedgerTab.list => _list(context, ref, book),
                                  LedgerTab.stats => _stats(context, ref, book),
                                  LedgerTab.accounts => _accounts(
                                    context,
                                    ref,
                                    book,
                                  ),
                                },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _notSetUp(BuildContext context, WidgetRef ref) => [
    InlineEmptyCard(
      title: '還沒開始記帳',
      message:
          '先建要用的帳戶（中信活存、中信信用卡、現金，可以再多加戶頭）就能開始。'
          '餘額都可以先不填。'
          '不用補以前的紀錄。',
      actions: [EmptyAction('開始記帳', () => setupFlow(context, ref))],
    ),
  ];

  // ── 共用小區塊 ───────────────────────────────────────────

  Widget _monthBar(WidgetRef ref) {
    final m = ref.watch(ledgerMonthProvider);
    void go(int d) => ref.read(ledgerMonthProvider.notifier).state = DateTime(
      m.year,
      m.month + d,
    );
    return Row(
      children: [
        IconButton(
          onPressed: () => go(-1),
          icon: const Icon(Icons.chevron_left_rounded),
          color: AppColors.ink2,
          tooltip: '上個月',
        ),
        Expanded(
          child: Text(
            '${m.year} 年 ${m.month} 月',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        IconButton(
          onPressed: () => go(1),
          icon: const Icon(Icons.chevron_right_rounded),
          color: AppColors.ink2,
          tooltip: '下個月',
        ),
      ],
    );
  }

  Widget _spendCard(
    BuildContext context,
    WidgetRef ref,
    LedgerBook book,
    DateTime m,
  ) {
    final st = book.monthStats(m.year, m.month);
    final bud = book.budgetOf(m.year, m.month);
    final left = bud.total - st.spend;
    final now = DateTime.now();
    final isCur = now.year == m.year && now.month == m.month;
    final daysLeft = DateTime(m.year, m.month + 1, 0).day - now.day + 1;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '💰 控制開銷・${m.month} 月・已記錄 ${book.txs.where(LedgerBook.inMonth(m.year, m.month)).length} 筆',
                style: AppText.note,
              ),
              const Spacer(),
              InkWell(
                onTap: () => budgetFlow(context, ref, m.year, m.month),
                child: Text(
                  bud.total == 0 ? '設定預算 ✎' : '編輯預算 ✎',
                  style: AppText.note.copyWith(color: ledgerAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bud.total == 0 ? '本月消費' : '剩餘可花', style: AppText.note),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        lMoney(bud.total == 0 ? st.spend : left),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: left < 0 && bud.total > 0
                              ? ledgerBad
                              : AppColors.ink,
                          fontFeatures: lTabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (bud.total > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('本月消費', style: AppText.note),
                    Text(
                      lMoney(st.spend),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        fontFeatures: lTabular,
                      ),
                    ),
                    Text(
                      '預算 ${lMoney(bud.total)}${bud.carriedFrom == null ? '' : '（沿用）'}',
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                  ],
                ),
            ],
          ),
          if (bud.total > 0) ...[
            const SizedBox(height: 10),
            LedgerBar(
              st.spend / bud.total,
              color: left < 0 ? ledgerBad : ledgerAccent,
            ),
          ],
          // 本月消費平均到「今天為止」每天花多少（2026-11-04 使用者）；過去的月份
          // 平均整個月，還沒到的月份不顯示。
          if (isCur ||
              DateTime(
                m.year,
                m.month,
              ).isBefore(DateTime(now.year, now.month))) ...[
            const SizedBox(height: 7),
            Text(
              '平均每天花 ${lMoney((st.spend / (isCur ? now.day : DateTime(m.year, m.month + 1, 0).day)).round())}'
              '（${isCur ? '到今天' : '整個月'}共 ${isCur ? now.day : DateTime(m.year, m.month + 1, 0).day} 天）',
              style: AppText.note.copyWith(color: AppColors.ink2),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            '${isCur && left > 0 && bud.total > 0 ? '還有 $daysLeft 天，平均每天可花 ${lMoney(left ~/ daysLeft)}・' : ''}'
            '繳卡費、提款請用「轉帳」記（不算消費）；幫別人付的只算自己那份',
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  Widget _completeness(BuildContext context, WidgetRef ref, LedgerBook book) {
    final states = book.states;
    final bad = states.where((s) => s.miss != 0).length;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('🧾 記帳完整度', style: AppText.note),
              const SizedBox(width: 6),
              if (bad > 0)
                LedgerPill('$bad 個帳戶對不上', color: AppColors.mid)
              else if (states.any((s) => s.checked))
                const LedgerPill('全部對上', color: AppColors.ok),
              const Spacer(),
              InkWell(
                onTap: () => reconAllFlow(context, ref),
                child: Text(
                  '一次對帳 ›',
                  style: AppText.note.copyWith(color: ledgerAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final a in book.accounts)
            AccountStatusRow(
              account: a,
              state: book.stateOf(a),
              onTap: () => accountFlow(context, ref, a),
            ),
          const SizedBox(height: 4),
          Text(
            states.isEmpty
                ? '餘額都沒填也能記帳；想抓漏記再到帳戶填一次現在的餘額。'
                : '這裡只看「有沒有漏記」，跟上面「剩餘可花」是兩回事。',
            style: AppText.note.copyWith(color: AppColors.ink3, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _mini(BuildContext context, WidgetRef ref, LedgerBook book) {
    Widget box(String top, String value, String sub, Color c, VoidCallback f) =>
        Expanded(
          child: GlassCard(
            onTap: f,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(top, style: AppText.note.copyWith(fontSize: 10.5)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c,
                    fontFeatures: lTabular,
                  ),
                ),
                Text(
                  sub,
                  style: AppText.note.copyWith(
                    fontSize: 10.5,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        box(
          '🚩 標記旗幟',
          '${book.flagged.length} 筆',
          '點開只看這些',
          AppColors.ink,
          () => flagsFlow(context, ref),
        ),
        const SizedBox(width: Gap.md),
        box(
          '👥 幫誰付過',
          '${book.paidForOthers.length} 筆',
          '點開只看這些',
          AppColors.ink,
          () => paidForFlow(context, ref),
        ),
      ],
    );
  }

  // ── 首頁 ─────────────────────────────────────────────────

  List<Widget> _home(BuildContext context, WidgetRef ref, LedgerBook book) {
    final m = ref.watch(ledgerMonthProvider);
    return [
      _monthBar(ref),
      if (isBeforeAccurate(m.year, m.month)) const OldDataBanner(),
      _spendCard(context, ref, book, m),
      const SizedBox(height: Gap.md),
      _completeness(context, ref, book),
      const SizedBox(height: Gap.md),
      _mini(context, ref, book),
      // 最近記帳只顯示五筆（2026-11-03 使用者）；要看更多去底部的「明細」。
      ledgerSection(
        '最近記帳',
        action: '全部明細 ›',
        onAction: () => context.go(LedgerTab.list.path),
      ),
      if (book.txs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('還沒有紀錄，按右下角 ＋ 新增第一筆', style: AppText.bodyDim),
        )
      else
        for (final t in book.txs.take(5))
          TxTile(
            book: book,
            tx: t,
            showDate: true,
            onTap: () => txDetailFlow(context, ref, t.id),
          ),
    ];
  }

  // ── 明細 ─────────────────────────────────────────────────

  List<Widget> _list(BuildContext context, WidgetRef ref, LedgerBook book) {
    final m = ref.watch(ledgerMonthProvider);
    final f = ref.watch(ledgerFilterProvider);
    void set(({bool flagged, String? accountId, String? category}) v) =>
        ref.read(ledgerFilterProvider.notifier).state = v;
    final q = ref.watch(ledgerSearchProvider).trim();
    final range = ref.watch(ledgerRangeProvider);
    final searching = q.isNotEmpty;
    // 搜尋、或選了「整年／全部時間」時不是只看一個月。
    final wide = searching || range != LedgerRange.month;
    final inM = searching || range == LedgerRange.all
        ? book.txs
        : range == LedgerRange.year
        ? book.txs.where((t) => t.occurredAt.year == m.year).toList()
        : book.txs.where(LedgerBook.inMonth(m.year, m.month)).toList();
    final shown = inM
        .where(
          (t) =>
              (!searching || book.matches(t, q)) &&
              (!f.flagged || t.flagged) &&
              (f.category == null ||
                  book.categoriesOf(t).contains(f.category)) &&
              (f.accountId == null ||
                  t.accountId == f.accountId ||
                  t.toAccountId == f.accountId),
        )
        .toList();
    final st = book.statsWhere(shown.contains);
    final any = f.flagged || f.accountId != null || f.category != null;
    return [
      // 選月份那一行（左右切換）放在搜尋框上面（2026-11-03 使用者）。
      if (!wide) _monthBar(ref),
      const _SearchBox(),
      // 查看時間在左、篩選在右，同一行（2026-11-04 使用者）；篩選是毛玻璃下拉選單。
      Row(
        children: [
          Flexible(
            child: _RangeButton(book: book, searching: searching),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _FilterButton(book: book, inM: inM),
          ),
        ],
      ),
      // 2026 年 11 月以前的資料不準確（只是記錄下來）：看那些月份，或搜尋結果裡有
      // 那些月份的紀錄時，明細上方標註。
      if (wide
          ? shown.any(
              (t) => isBeforeAccurate(t.occurredAt.year, t.occurredAt.month),
            )
          : isBeforeAccurate(m.year, m.month))
        const OldDataBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          '${shown.length} 筆・${f.category == null ? '消費' : '${f.category}'} ${lMoney(f.category == null ? st.spend : (st.byCategory[f.category] ?? 0))}'
          '${f.category == null ? '・收入 ${lMoney(st.income)}' : ''}'
          '${searching
              ? '（搜尋「$q」，全部時間）'
              : range == LedgerRange.all
              ? '（全部時間）'
              : range == LedgerRange.year
              ? '（${m.year} 年）'
              : any
              ? '（篩選中）'
              : ''}',
          style: AppText.note.copyWith(color: AppColors.ink3),
        ),
      ),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Gap.md),
          child: InlineEmptyCard(
            title: any || searching ? '沒有符合的紀錄' : '這個月還沒有紀錄',
            message: any || searching
                ? '換個關鍵字或篩選看看'
                : '按右下角 ＋ 記一筆，或按右上角的貼上圖示匯入刷卡紀錄',
            actions: [
              if (any)
                EmptyAction(
                  '看全部',
                  () => set((flagged: false, accountId: null, category: null)),
                ),
            ],
          ),
        )
      else
        ...groupedTxList(
          book,
          shown,
          (t) => txDetailFlow(context, ref, t.id),
          partCategory: f.category,
        ),
    ];
  }

  // ── 統計 ─────────────────────────────────────────────────

  List<Widget> _stats(BuildContext context, WidgetRef ref, LedgerBook book) {
    final m = ref.watch(ledgerMonthProvider);
    final st = book.monthStats(m.year, m.month);
    final bud = book.budgetOf(m.year, m.month);
    final left = bud.total - st.spend;
    final cats = st.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = cats.fold(0, (s, e) => s + e.value);
    final rows =
        {
          ...st.byCategory.keys.where((c) => (st.byCategory[c] ?? 0) != 0),
          ...bud.byCategory.keys,
        }.toList()..sort(
          (a, b) => (st.byCategory[b] ?? 0).compareTo(st.byCategory[a] ?? 0),
        );
    Widget kpi(String v, String label, {Color? color, VoidCallback? onTap}) =>
        Expanded(
          child: GlassCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    v,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color ?? AppColors.ink,
                      fontFeatures: lTabular,
                    ),
                  ),
                ),
                Text(label, style: AppText.note.copyWith(fontSize: 10)),
              ],
            ),
          ),
        );
    return [
      _monthBar(ref),
      Row(
        children: [
          kpi(lMoney(st.spend), '本月消費'),
          const SizedBox(width: 6),
          kpi(lMoney(st.income), '本月收入', color: AppColors.ok),
          const SizedBox(width: 6),
          kpi(
            bud.total == 0 ? '設定' : lMoney(left),
            '剩餘可花 ✎',
            color: bud.total > 0 && left < 0 ? ledgerBad : null,
            onTap: () => budgetFlow(context, ref, m.year, m.month),
          ),
        ],
      ),
      const SizedBox(height: Gap.md),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('📊 分類佔比', style: AppText.note),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 170,
                height: 170,
                child: CustomPaint(
                  painter: _DonutPainter([
                    for (final e in cats) (e.value, catLook(e.key).$2),
                  ]),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('本月消費', style: AppText.note),
                        Text(
                          lMoney(st.spend),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (cats.isEmpty)
              Center(child: Text('這個月還沒有消費', style: AppText.bodyDim))
            else
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final e in cats)
                    InkWell(
                      onTap: () =>
                          categoryFlow(context, ref, e.key, m.year, m.month),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: catLook(e.key).$2,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${e.key} ${(e.value / total * 100).round()}%',
                            style: AppText.note,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      ledgerSection(
        '分類與預算',
        action: '編輯預算 ✎',
        onAction: () => budgetFlow(context, ref, m.year, m.month),
      ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('這個月還沒有消費', style: AppText.bodyDim),
        )
      else
        GlassCard(
          child: Column(
            children: [
              for (final c in rows)
                _catRow(
                  context,
                  ref,
                  c,
                  st.byCategory[c] ?? 0,
                  bud.byCategory[c],
                  st.spend,
                  m,
                ),
            ],
          ),
        ),
    ];
  }

  Widget _catRow(
    BuildContext context,
    WidgetRef ref,
    String cat,
    int v,
    int? budget,
    int spend,
    DateTime m,
  ) {
    final over = budget != null && v > budget;
    final (emoji, color) = catLook(cat);
    return InkWell(
      onTap: () => categoryFlow(context, ref, cat, m.year, m.month),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$emoji $cat',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      if (over)
                        LedgerPill(
                          '超支 ${lMoney(v - budget)}',
                          color: ledgerBad,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lMoney(v)}${budget == null ? '' : ' / ${lMoney(budget)}'}',
                  style: AppText.note.copyWith(fontFeatures: lTabular),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LedgerBar(
              budget != null
                  ? v / budget
                  : spend <= 0
                  ? 0
                  : v / spend,
              color: over ? ledgerBad : color,
            ),
          ],
        ),
      ),
    );
  }

  // ── 帳戶 ─────────────────────────────────────────────────

  List<Widget> _accounts(BuildContext context, WidgetRef ref, LedgerBook book) {
    Widget tool(IconData icon, String title, String sub, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: ledgerTileBg,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              onTap: onTap,
              leading: Icon(icon, color: AppColors.ink2),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(sub, style: AppText.note.copyWith(fontSize: 11)),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink3,
              ),
            ),
          ),
        );
    final m = ref.watch(ledgerMonthProvider);
    return [
      ledgerSection(
        '我的帳戶',
        action: '一次對完 ›',
        onAction: () => reconAllFlow(context, ref),
      ),
      for (final a in book.accounts)
        if (book.stateOf(a) case final s?)
          _accountCard(context, ref, s)
        else
          _noBalanceCard(context, ref, a),
      OutlinedButton.icon(
        onPressed: () => addAccountFlow(context, ref),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('新增帳戶'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.glassEdge),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
      ledgerSection('工具'),
      tool(
        Icons.content_paste_rounded,
        '貼上文字匯入',
        '銀行｜日期時間｜分類｜商家｜金額，一行一筆',
        () => importFlow(context, ref),
      ),
      tool(
        Icons.flag_outlined,
        '標記旗幟的',
        '只看被標記的那幾筆',
        () => flagsFlow(context, ref),
      ),
      tool(
        Icons.track_changes_rounded,
        '預算',
        '${m.month} 月的整月總額＋各分類',
        () => budgetFlow(context, ref, m.year, m.month),
      ),
    ];
  }

  /// 還沒填餘額的帳戶：只記交易，按「填餘額」才開始算。
  Widget _noBalanceCard(BuildContext context, WidgetRef ref, LedgerAccount a) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: GlassCard(
          onTap: () => accountFlow(context, ref, a),
          child: Row(
            children: [
              LedgerIcon(a.type.emoji, accountColor(a.type)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '${a.type.label}・沒填餘額，只記交易',
                      style: AppText.note.copyWith(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => reconFlow(context, ref, a),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.glassEdge),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(a.isCard ? '填額度' : '填餘額'),
              ),
            ],
          ),
        ),
      );

  Widget _accountCard(BuildContext context, WidgetRef ref, AccountState s) {
    final a = s.account;
    final color = accountColor(a.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: GlassCard(
        onTap: () => accountFlow(context, ref, a),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                LedgerIcon(a.type.emoji, color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        '${a.type.label}${s.checked ? '・上次對帳 ${lMd(s.last.at)} ${lHm(s.last.at)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.note.copyWith(
                          fontSize: 10.5,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      a.isCard ? '可刷額' : 'App 推算餘額',
                      style: AppText.note.copyWith(fontSize: 10.5),
                    ),
                    Text(
                      lMoney(a.isCard ? s.available : s.now),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        fontFeatures: lTabular,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                !s.checked
                    ? const LedgerPill('還沒對帳')
                    : s.miss == 0
                    ? const LedgerPill('✓ 對上了', color: AppColors.ok)
                    : LedgerPill(
                        '⚠ 差 ${lMoney(s.miss.abs())}・${s.miss > 0 ? '可能漏記' : '多出來'}',
                        color: AppColors.mid,
                      ),
                const Spacer(),
                FilledButton(
                  onPressed: () => reconFlow(context, ref, a),
                  style: FilledButton.styleFrom(
                    backgroundColor: ledgerAccent,
                    foregroundColor: const Color(0xFF08130E),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('對帳'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 分類佔比的甜甜圈。
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts);

  final List<(int, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 24.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final total = parts.fold(0, (s, p) => s + p.$1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        paint..color = const Color(0xFF1E1E2E),
      );
      return;
    }
    var start = -math.pi / 2;
    for (final (v, c) in parts) {
      final sweep = v / total * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, paint..color = c);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// 明細頂部的搜尋框：輸入後馬上搜，右邊有清除。
class _SearchBox extends ConsumerStatefulWidget {
  const _SearchBox();

  @override
  ConsumerState<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<_SearchBox> {
  late final _c = TextEditingController(text: ref.read(ledgerSearchProvider));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: _c,
      onChanged: (v) {
        ref.read(ledgerSearchProvider.notifier).state = v;
        setState(() {}); // 清除鈕跟著有沒有字出現或消失
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '商家、備註、分類、帳戶、金額、日期⋯（多詞以空白間格）',
        hintStyle: const TextStyle(fontSize: 12.5),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜尋',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _c.clear();
                  ref.read(ledgerSearchProvider.notifier).state = '';
                  setState(() {});
                },
              ),
        isDense: true,
        filled: true,
        fillColor: AppColors.glassFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassEdge),
        ),
      ),
    ),
  );
}

/// 「查看時間」按鈕（明細頂部）：點開選全部時間、今年、本月、上個月，或有紀錄的某個月。
class _RangeButton extends ConsumerWidget {
  const _RangeButton({required this.book, required this.searching});

  final LedgerBook book;
  final bool searching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(ledgerRangeProvider);
    final m = ref.watch(ledgerMonthProvider);
    final label = searching
        ? '全部時間（搜尋中）'
        : switch (range) {
            LedgerRange.all => '全部時間',
            LedgerRange.year => '${m.year} 年',
            LedgerRange.month => '${m.year} 年 ${m.month} 月',
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: searching ? null : () => _open(context, ref),
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(
            '查看時間：$label  ▾',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.glassEdge),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    // 有紀錄的月份（新的在前）跟每個月幾筆。
    final counts = <DateTime, int>{};
    for (final t in book.txs) {
      final k = DateTime(t.occurredAt.year, t.occurredAt.month);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final months = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    void pick(LedgerRange r, [DateTime? month]) {
      ref.read(ledgerRangeProvider.notifier).state = r;
      if (month != null) {
        ref.read(ledgerMonthProvider.notifier).state = month;
      }
      Navigator.pop(context);
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '查看時間',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text('全部時間（${book.txs.length} 筆）'),
                    onPressed: () => pick(LedgerRange.all),
                  ),
                  ActionChip(
                    label: Text('今年（${now.year}）'),
                    onPressed: () =>
                        pick(LedgerRange.year, DateTime(now.year, now.month)),
                  ),
                  ActionChip(
                    label: const Text('本月'),
                    onPressed: () =>
                        pick(LedgerRange.month, DateTime(now.year, now.month)),
                  ),
                  ActionChip(
                    label: const Text('上個月'),
                    onPressed: () => pick(
                      LedgerRange.month,
                      DateTime(now.year, now.month - 1),
                    ),
                  ),
                ],
              ),
              if (months.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('有紀錄的月份', style: TextStyle(color: AppColors.ink2)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(c).size.height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in months)
                          ActionChip(
                            label: Text(
                              '${k.year}/${k.month.toString().padLeft(2, '0')}（${counts[k]}）',
                            ),
                            onPressed: () => pick(LedgerRange.month, k),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 明細的篩選：一顆按鈕，點開是 iOS 風格的毛玻璃下拉選單，裡面分段列出「全部／注意」、
/// 各個帳戶、目前範圍裡有出現的分類；可以同時選好幾個（例如注意＋現金＋菸酒）。
class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.book, required this.inM});

  final LedgerBook book;

  /// 目前時間範圍裡的交易（只列有出現的分類、算注意幾筆）。
  final List<LedgerTx> inM;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(ledgerFilterProvider);
    void set(({bool flagged, String? accountId, String? category}) v) =>
        ref.read(ledgerFilterProvider.notifier).state = v;
    final cats = {for (final t in inM) ...book.categoriesOf(t)}.toList()
      ..sort(
        (a, b) => ledgerExpenseCats.keys
            .toList()
            .indexOf(a)
            .compareTo(ledgerExpenseCats.keys.toList().indexOf(b)),
      );
    final accName = f.accountId == null
        ? null
        : book.account(f.accountId)?.name;
    final parts = [
      if (f.flagged) '注意',
      ?accName,
      if (f.category != null) f.category!,
    ];
    final any = parts.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Builder(
          builder: (btn) => OutlinedButton.icon(
            onPressed: () async {
              final picked = await showGlassMenu<String>(
                btn,
                width: 230,
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                selectedValues: {
                  if (!any) 'all',
                  if (f.flagged) 'flag',
                  if (f.accountId != null) 'acct:${f.accountId}',
                  if (f.category != null) 'cat:${f.category}',
                },
                items: [
                  const GlassMenuItem(
                    value: 'h:filter',
                    label: '篩選',
                    header: true,
                  ),
                  const GlassMenuItem(
                    value: 'all',
                    label: '全部',
                    icon: Icons.all_inclusive_rounded,
                  ),
                  GlassMenuItem(
                    value: 'flag',
                    label: '注意 ${inM.where((t) => t.flagged).length}',
                    icon: Icons.flag_outlined,
                  ),
                  const GlassMenuItem(
                    value: 'h:acct',
                    label: '帳戶',
                    header: true,
                  ),
                  for (final a in book.accounts)
                    GlassMenuItem(
                      value: 'acct:${a.id}',
                      label: '${a.type.emoji} ${a.name}',
                    ),
                  if (cats.isNotEmpty)
                    const GlassMenuItem(
                      value: 'h:cat',
                      label: '分類',
                      header: true,
                    ),
                  for (final c in cats)
                    GlassMenuItem(
                      value: 'cat:$c',
                      label: '${catLook(c).$1} $c',
                    ),
                ],
              );
              if (picked == null) return;
              if (picked == 'all') {
                set((flagged: false, accountId: null, category: null));
              } else if (picked == 'flag') {
                set((
                  flagged: !f.flagged,
                  accountId: f.accountId,
                  category: f.category,
                ));
              } else if (picked.startsWith('acct:')) {
                final id = picked.substring(5);
                set((
                  flagged: f.flagged,
                  accountId: f.accountId == id ? null : id,
                  category: f.category,
                ));
              } else if (picked.startsWith('cat:')) {
                final c = picked.substring(4);
                set((
                  flagged: f.flagged,
                  accountId: f.accountId,
                  category: f.category == c ? null : c,
                ));
              }
            },
            icon: const Icon(Icons.filter_list_rounded, size: 18),
            label: Text(
              '篩選：${any ? parts.join('・') : '全部'}  ▾',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.glassEdge),
              backgroundColor: AppColors.glassFill,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
