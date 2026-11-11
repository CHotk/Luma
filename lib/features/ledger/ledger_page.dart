import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';
import '../../shared/half_width_input.dart';
import '../../shared/widgets/date_time_wheel.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_menu.dart';
import '../../shared/widgets/inline_empty_card.dart';
import '../../domain/ledger_subscriptions.dart';
import 'ledger_data.dart';
import 'ledger_subs_page.dart';
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

/// 明細的篩選：只看 🚩、只看某個帳戶、只看某個分類、只看某種類型（支出／收入／轉帳，2026-11-10 使用者）。
typedef LedgerFilter = ({
  bool flagged,
  bool unconfirmed,
  String? accountId,
  String? category,
  LedgerTxType? type,
});

const ledgerNoFilter = (
  flagged: false,
  unconfirmed: false,
  accountId: null,
  category: null,
  type: null,
);

final ledgerFilterProvider = StateProvider<LedgerFilter>((_) => ledgerNoFilter);

/// 明細的金額篩選（2026-11-11 使用者：三個階段＋自訂）。min／max 都是 null＝不篩；金額看絕對值。
typedef LedgerAmountFilter = ({int? min, int? max});

const ledgerNoAmount = (min: null, max: null);

final ledgerAmountProvider = StateProvider<LedgerAmountFilter>(
  (_) => ledgerNoAmount,
);

/// 金額的三個階段。
const ledgerAmountTiers = <({String label, int? min, int? max})>[
  (label: '小額　＜ \$500', min: null, max: 499),
  (label: '中額　\$500～3,000', min: 500, max: 3000),
  (label: '大額　＞ \$3,000', min: 3001, max: null),
];

/// 明細查看的時間範圍（2026-11-03 使用者：要能選全部，才能看菸酒之類總共花多少）：
/// 單一個月（用 [ledgerMonthProvider]）、整年、全部時間。
enum LedgerRange { month, year, all }

final ledgerRangeProvider = StateProvider<LedgerRange>(
  (_) => LedgerRange.month,
);

/// 統計的時間範圍（2026-11-10 使用者：統計也要能選「全部」或「指定月份～指定月份」）。
/// null＝只看單一個月（跟著上面的月份列，原本的樣子）。跟明細的 [ledgerRangeProvider] 各自一份。
class LedgerStatsRange {
  const LedgerStatsRange.all() : all = true, from = null, to = null;
  const LedgerStatsRange.between(DateTime this.from, DateTime this.to)
    : all = false;

  final bool all;

  /// 範圍的第一個月、最後一個月（都含，都是那個月 1 號）。
  final DateTime? from;
  final DateTime? to;

  bool Function(LedgerTx) get test {
    if (all) return (_) => true;
    final a = DateTime(from!.year, from!.month);
    final b = DateTime(to!.year, to!.month + 1); // 最後一個月的下個月 1 號（不含）
    return (t) => !t.occurredAt.isBefore(a) && t.occurredAt.isBefore(b);
  }
}

final ledgerStatsRangeProvider = StateProvider<LedgerStatsRange?>((_) => null);

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
              // 毛玻璃（模糊＋半透明＋細亮邊），但底色壓深：背後有每筆記帳卡片，
              // 淺色玻璃會太花（2026-11-05 使用者）。
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC16241E), Color(0xE60A110E)],
                      ),
                      border: Border.all(
                        color: ledgerAccent.withValues(alpha: 0.45),
                      ),
                    ),
                    child: FloatingActionButton(
                      onPressed: () => txFormFlow(context, ref),
                      tooltip: '記一筆',
                      backgroundColor: Colors.transparent,
                      foregroundColor: ledgerAccent,
                      elevation: 0,
                      focusElevation: 0,
                      hoverElevation: 0,
                      highlightElevation: 0,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.add_rounded, size: 28),
                    ),
                  ),
                ),
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
                // 明細：選月份那一行釘在這裡、不跟著捲（打字搜尋或選整年／全部時間時不是看單月，
                // 用空位頂著，列表的位置不變才不會重建、搜尋框焦點才不會掉）。
                tab == LedgerTab.list && book != null && book.isSetUp
                    ? _pinnedMonth(ref)
                    : const SizedBox.shrink(),
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
          '先建要用的帳戶（中信帳戶、中信信用卡、現金，可以再多加戶頭）就能開始。'
          '餘額都可以先不填。'
          '不用補以前的紀錄。',
      actions: [EmptyAction('開始記帳', () => setupFlow(context, ref))],
    ),
  ];

  // ── 共用小區塊 ───────────────────────────────────────────

  Widget _pinnedMonth(WidgetRef ref) {
    final wide = ref.watch(ledgerRangeProvider) != LedgerRange.month;
    return wide ? const SizedBox.shrink() : _monthBar(ref, tall: true);
  }

  /// [tall]＝明細頂部釘住不跟著捲的那條：高一點（2026-11-10 使用者）。
  Widget _monthBar(WidgetRef ref, {bool tall = false}) {
    final m = ref.watch(ledgerMonthProvider);
    void go(int d) => ref.read(ledgerMonthProvider.notifier).state = DateTime(
      m.year,
      m.month + d,
    );
    final row = Row(
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
            style: TextStyle(
              fontSize: tall ? 16.5 : 15,
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
    return tall ? SizedBox(height: 60, child: row) : row;
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
              // 筆數變兩位數時窄螢幕會擠爆（2026-11-11 測試抓到），字太長就省略。
              Expanded(
                child: Text(
                  '💰 控制開銷・${m.month} 月・已記錄 ${book.txs.where(LedgerBook.inMonth(m.year, m.month)).length} 筆',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.note,
                ),
              ),
              const SizedBox(width: 6),
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
          // 總支出：消費＋幫別人付＋還款＋轉給他人（2026-11-11 使用者）。
          if (st.out != st.spend) ...[
            const SizedBox(height: 7),
            Text(
              '總支出 ${lMoney(st.out)}（含${ledgerOutDetail(st)}）',
              key: const ValueKey('homeOut'),
              style: AppText.note.copyWith(color: AppColors.ink2),
            ),
          ],
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
      const SizedBox(height: Gap.md),
      const _SubsEntry(),
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
        // 照「添加順序」（新增的在最上面），不是照交易時間（2026-11-11 使用者）：
        // 補記以前的帳也看得到剛剛記的。
        for (final t
            in ([...book.txs]..sort(
                  (a, b) => (b.createdAt ?? b.occurredAt).compareTo(
                    a.createdAt ?? a.occurredAt,
                  ),
                ))
                .take(5))
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
    void set(LedgerFilter v) =>
        ref.read(ledgerFilterProvider.notifier).state = v;
    final range = ref.watch(ledgerRangeProvider);
    final amount = ref.watch(ledgerAmountProvider);
    // 選了「整年／全部時間」時不是只看一個月。搜尋是另外一頁（見 [_FilterCapsule._openSearch]）。
    final wide = range != LedgerRange.month;
    final inM = range == LedgerRange.all
        ? book.txs
        : range == LedgerRange.year
        ? book.txs.where((t) => t.occurredAt.year == m.year).toList()
        : book.txs.where(LedgerBook.inMonth(m.year, m.month)).toList();
    final shown = inM
        .where(
          (t) =>
              (amount.min == null || t.amount.abs() >= amount.min!) &&
              (amount.max == null || t.amount.abs() <= amount.max!) &&
              (!f.flagged || t.flagged) &&
              (!f.unconfirmed || !t.confirmed) &&
              (f.type == null || t.type == f.type) &&
              (f.category == null ||
                  book.categoriesOf(t).contains(f.category)) &&
              (f.accountId == null ||
                  t.accountId == f.accountId ||
                  t.toAccountId == f.accountId),
        )
        .toList();
    final st = book.statsWhere(shown.contains);
    final amountOn = amount.min != null || amount.max != null;
    final any =
        f.flagged ||
        f.unconfirmed ||
        f.accountId != null ||
        f.category != null ||
        f.type != null ||
        amountOn;
    return [
      // 選月份那一行（左右切換）在搜尋框上面（2026-11-03 使用者），現在釘在頁面頂端、
      // 往下捲也看得到（2026-11-10 使用者），見 build 裡的 [_pinnedMonth]，不在這個會捲的列表裡。
      // 時間｜金額｜篩選｜搜尋 合成一條膠囊（2026-11-11 使用者）；有篩選的那格換顏色。
      _FilterCapsule(book: book, inM: inM),
      // 2026 年 11 月以前的資料不準確（只是記錄下來）：看那些月份，或搜尋結果裡有
      // 那些月份的紀錄時，明細上方標註。
      // 搜尋時不標（2026-11-05 使用者：搜得到的都是有資料的，不用特別提示）。
      if ((wide
          ? shown.any(
              (t) => isBeforeAccurate(t.occurredAt.year, t.occurredAt.month),
            )
          : isBeforeAccurate(m.year, m.month)))
        const OldDataBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          '${shown.length} 筆・${f.category == null ? '消費' : '${f.category}'} ${lMoney(f.category == null ? st.spend : (st.byCategory[f.category] ?? st.extra[f.category] ?? 0))}'
          '${f.category == null && st.out != st.spend ? '・總支出 ${lMoney(st.out)}' : ''}'
          '${f.category == null ? '・收入 ${lMoney(st.income)}' : ''}'
          '${range == LedgerRange.all
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
            title: any ? '沒有符合的紀錄' : '這個月還沒有紀錄',
            message: any ? '換個篩選看看' : '按右下角 ＋ 記一筆，或按右上角的貼上圖示匯入刷卡紀錄',
            actions: [
              if (any)
                EmptyAction('看全部', () {
                  set(ledgerNoFilter);
                  ref.read(ledgerAmountProvider.notifier).state =
                      ledgerNoAmount;
                }),
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

  /// 範圍裡有幾個月（算月平均）：指定月份～月份＝差幾個月＋1；全部＝第一筆到最後一筆之間。
  int _rangeMonths(LedgerBook book, LedgerStatsRange range) {
    DateTime a, b;
    if (range.all) {
      if (book.txs.isEmpty) return 1;
      a = book.txs.last.occurredAt;
      b = book.txs.first.occurredAt;
    } else {
      a = range.from!;
      b = range.to!;
    }
    return math.max(1, (b.year - a.year) * 12 + b.month - a.month + 1);
  }

  /// 統計頂部的「統計範圍」按鈕：單月／全部／指定月份～月份。
  Widget _statsRangeButton(
    BuildContext context,
    WidgetRef ref,
    LedgerBook book,
    LedgerStatsRange? range,
    DateTime m,
  ) {
    final label = range == null
        ? '${m.year} 年 ${m.month} 月'
        : range.all
        ? '全部時間'
        : '${range.from!.year}/${range.from!.month} ～ ${range.to!.year}/${range.to!.month}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('statsRange'),
          onPressed: () => _openStatsRange(context, ref, book, range, m),
          icon: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(
            '統計範圍：$label  ▾',
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

  Future<void> _openStatsRange(
    BuildContext context,
    WidgetRef ref,
    LedgerBook book,
    LedgerStatsRange? range,
    DateTime m,
  ) async {
    final now = DateTime.now();
    var from =
        range?.from ??
        (book.txs.isEmpty
            ? DateTime(now.year, now.month)
            : DateTime(
                book.txs.last.occurredAt.year,
                book.txs.last.occurredAt.month,
              ));
    var to = range?.to ?? DateTime(now.year, now.month);
    void set(LedgerStatsRange? r) {
      ref.read(ledgerStatsRangeProvider.notifier).state = r;
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
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) {
          Future<void> pickMonth(bool isFrom) async {
            final v = await showDateTimeWheel(
              c,
              isFrom ? from : to,
              monthOnly: true,
            );
            if (v == null) return;
            setSt(() {
              final d = DateTime(v.year, v.month);
              if (isFrom) {
                from = d;
                if (to.isBefore(d)) to = d;
              } else {
                to = d;
                if (from.isAfter(d)) from = d;
              }
            });
          }

          Widget monthBtn(String key, DateTime d, bool isFrom) => Expanded(
            child: OutlinedButton(
              key: ValueKey(key),
              onPressed: () => pickMonth(isFrom),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.glassEdge),
              ),
              child: Text('${d.year} 年 ${d.month} 月'),
            ),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '統計範圍',
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
                        key: const ValueKey('statsRangeMonth'),
                        label: Text('單月（${m.year} 年 ${m.month} 月）'),
                        onPressed: () => set(null),
                      ),
                      ActionChip(
                        key: const ValueKey('statsRangeAll'),
                        label: Text('全部時間（${book.txs.length} 筆）'),
                        onPressed: () => set(const LedgerStatsRange.all()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('指定月份 ～ 指定月份', style: AppText.note),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      monthBtn('statsFrom', from, true),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('～'),
                      ),
                      monthBtn('statsTo', to, false),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('statsRangeApply'),
                      onPressed: () => set(LedgerStatsRange.between(from, to)),
                      child: const Text('套用這段時間'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _stats(BuildContext context, WidgetRef ref, LedgerBook book) {
    final m = ref.watch(ledgerMonthProvider);
    // 統計範圍（2026-11-10 使用者）：null＝單一個月（跟著月份列）；全部、指定月份～月份沒有預算、
    // 改看「區間消費／月平均」。
    final range = ref.watch(ledgerStatsRangeProvider);
    final single = range == null;
    final st = single
        ? book.monthStats(m.year, m.month)
        : book.statsWhere(range.test);
    final bud = book.budgetOf(m.year, m.month);
    final left = bud.total - st.spend;
    final months = single ? 1 : _rangeMonths(book, range);
    final cats = st.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = cats.fold(0, (s, e) => s + e.value);
    final rows =
        {
          ...st.byCategory.keys.where((c) => (st.byCategory[c] ?? 0) != 0),
          if (single) ...bud.byCategory.keys,
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
      if (single) _monthBar(ref),
      _statsRangeButton(context, ref, book, range, m),
      Row(
        children: [
          kpi(lMoney(st.spend), single ? '本月消費' : '區間消費'),
          const SizedBox(width: 6),
          kpi(lMoney(st.income), single ? '本月收入' : '區間收入', color: AppColors.ok),
          const SizedBox(width: 6),
          if (single)
            kpi(
              bud.total == 0 ? '設定' : lMoney(left),
              '剩餘可花 ✎',
              color: bud.total > 0 && left < 0 ? ledgerBad : null,
              onTap: () => budgetFlow(context, ref, m.year, m.month),
            )
          else
            kpi(lMoney((st.spend / months).round()), '月平均（$months 個月）'),
        ],
      ),
      // 總支出（2026-11-11 使用者）：消費只算自己；總支出連幫別人付、還款、轉給他人都算。
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '${single ? '本月' : '區間'}總支出 ${lMoney(st.out)}'
          '${st.out != st.spend ? '＝消費 ${lMoney(st.spend)}＋${ledgerOutDetail(st)}' : ''}',
          key: const ValueKey('statsOut'),
          style: AppText.note.copyWith(color: AppColors.ink2),
        ),
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
                        Text(single ? '本月消費' : '區間消費', style: AppText.note),
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
              Center(
                child: Text(
                  single ? '這個月還沒有消費' : '這段時間沒有消費',
                  style: AppText.bodyDim,
                ),
              )
            else
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final e in cats)
                    InkWell(
                      onTap: single
                          ? () => categoryFlow(
                              context,
                              ref,
                              e.key,
                              m.year,
                              m.month,
                            )
                          : null,
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
      if (single)
        ledgerSection(
          '分類與預算',
          action: '編輯預算 ✎',
          onAction: () => budgetFlow(context, ref, m.year, m.month),
        )
      else
        ledgerSection('分類'),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(single ? '這個月還沒有消費' : '這段時間沒有消費', style: AppText.bodyDim),
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
                  single ? bud.byCategory[c] : null,
                  st.spend,
                  m,
                  canOpen: single,
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
    DateTime m, {
    bool canOpen = true,
  }) {
    final over = budget != null && v > budget;
    final (emoji, color) = catLook(cat);
    return InkWell(
      onTap: canOpen
          ? () => categoryFlow(context, ref, cat, m.year, m.month)
          : null,
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

/// 首頁的「每月扣款」入口（2026-11-05 使用者；2026-11-06 改名）：寫每月合計跟幾項，點了進去。
class _SubsEntry extends ConsumerWidget {
  const _SubsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(ledgerSubsProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final active = subs.where((s) => isCharging(s, now)).toList();
    return GlassCard(
      onTap: () => context.push('/ledger/subs'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Text('🔁', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '每月扣款',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  active.isEmpty
                      ? '記錄每月會被扣的錢（訂閱、借款）'
                      : '${active.length} 項扣款中・每月 ${lMoney(subsMonthlyTotal(subs, now: now))}',
                  style: AppText.note.copyWith(
                    fontSize: 10.5,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.ink3,
          ),
        ],
      ),
    );
  }
}

/// 明細頂部：時間｜金額｜篩選｜🔍 合成一整條毛玻璃膠囊（2026-11-11 使用者）。
/// 篩選有開（不是預設）的那一格會換顏色，一眼看得出現在看的是篩選過的結果。
class _FilterCapsule extends ConsumerWidget {
  const _FilterCapsule({required this.book, required this.inM});

  final LedgerBook book;

  /// 目前時間範圍裡的交易（篩選選單只列有出現的分類）。
  final List<LedgerTx> inM;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(ledgerRangeProvider);
    final amount = ref.watch(ledgerAmountProvider);
    final f = ref.watch(ledgerFilterProvider);
    final filterOn =
        f.flagged ||
        f.unconfirmed ||
        f.accountId != null ||
        f.category != null ||
        f.type != null;
    Widget divider() => Container(
      width: 1,
      height: 20,
      color: Colors.white.withValues(alpha: .14),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: .14),
                  Colors.white.withValues(alpha: .05),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .20)),
            ),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  _CapSeg(
                    key: const ValueKey('rangeBtn'),
                    icon: Icons.calendar_month_rounded,
                    label: '時間',
                    active: range != LedgerRange.month,
                    onTap: (_) => _openRange(context, ref),
                    clearKey: const ValueKey('rangeClear'),
                    onClear: () {
                      final now = DateTime.now();
                      ref.read(ledgerRangeProvider.notifier).state =
                          LedgerRange.month;
                      ref.read(ledgerMonthProvider.notifier).state = DateTime(
                        now.year,
                        now.month,
                      );
                    },
                  ),
                  divider(),
                  _CapSeg(
                    key: const ValueKey('amountBtn'),
                    icon: Icons.payments_outlined,
                    label: '金額',
                    active: amount.min != null || amount.max != null,
                    onTap: (btn) => _openAmount(context, ref, btn),
                    clearKey: const ValueKey('amountClear'),
                    onClear: () =>
                        ref.read(ledgerAmountProvider.notifier).state =
                            ledgerNoAmount,
                  ),
                  divider(),
                  _CapSeg(
                    key: const ValueKey('filterBtn'),
                    icon: Icons.filter_list_rounded,
                    label: '篩選',
                    active: filterOn,
                    onTap: (btn) => _openFilter(context, ref, btn),
                    clearKey: const ValueKey('filterClear'),
                    onClear: () =>
                        ref.read(ledgerFilterProvider.notifier).state =
                            ledgerNoFilter,
                  ),
                  divider(),
                  _CapSeg(
                    key: const ValueKey('searchBtn'),
                    icon: Icons.search_rounded,
                    label: null,
                    width: 54,
                    active: false,
                    onTap: (_) => _openSearch(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 時間 ──
  Future<void> _openRange(BuildContext context, WidgetRef ref) async {
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
                '時間',
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

  // ── 金額 ──
  Future<void> _openAmount(
    BuildContext context,
    WidgetRef ref,
    BuildContext btn,
  ) async {
    final cur = ref.read(ledgerAmountProvider);
    final tierIdx = ledgerAmountTiers.indexWhere(
      (t) => t.min == cur.min && t.max == cur.max,
    );
    final on = cur.min != null || cur.max != null;
    final picked = await showGlassMenu<String>(
      btn,
      width: 210,
      selectedValues: {
        if (!on) 'all',
        if (tierIdx >= 0) 'tier:$tierIdx',
        if (on && tierIdx < 0) 'custom',
      },
      items: [
        const GlassMenuItem(
          value: 'all',
          label: '全部金額',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final (i, t) in ledgerAmountTiers.indexed)
          GlassMenuItem(value: 'tier:$i', label: t.label),
        const GlassMenuItem(
          value: 'custom',
          label: '自訂…',
          icon: Icons.tune_rounded,
        ),
      ],
    );
    if (picked == null || !context.mounted) return;
    final notifier = ref.read(ledgerAmountProvider.notifier);
    if (picked == 'all') {
      notifier.state = ledgerNoAmount;
    } else if (picked.startsWith('tier:')) {
      final t = ledgerAmountTiers[int.parse(picked.substring(5))];
      notifier.state = (min: t.min, max: t.max);
    } else {
      final v = await _customAmount(context, cur);
      if (v != null) notifier.state = v;
    }
  }

  /// 自訂金額範圍：最低、最高都可以空著（只設一邊）。
  Future<LedgerAmountFilter?> _customAmount(
    BuildContext context,
    LedgerAmountFilter cur,
  ) {
    final lo = TextEditingController(text: cur.min?.toString() ?? '');
    final hi = TextEditingController(text: cur.max?.toString() ?? '');
    InputDecoration dec(String hint) => InputDecoration(
      hintText: hint,
      prefixText: '\$ ',
      isDense: true,
      filled: true,
      fillColor: AppColors.glassFill,
    );
    return showDialog<LedgerAmountFilter>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A27),
        title: const Text('自訂金額', style: TextStyle(color: AppColors.ink)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('amountMin'),
                controller: lo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: dec('最低'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('～'),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('amountMax'),
                controller: hi,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: dec('最高'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('amountOk'),
            onPressed: () {
              var a = int.tryParse(lo.text);
              var b = int.tryParse(hi.text);
              if (a != null && b != null && a > b) (a, b) = (b, a);
              Navigator.pop(c, (min: a, max: b));
            },
            child: const Text('套用'),
          ),
        ],
      ),
    );
  }

  // ── 篩選（類型／注意／帳戶／分類） ──
  Future<void> _openFilter(
    BuildContext context,
    WidgetRef ref,
    BuildContext btn,
  ) async {
    final f = ref.read(ledgerFilterProvider);
    void set(LedgerFilter v) =>
        ref.read(ledgerFilterProvider.notifier).state = v;
    // 分類：選了類型就只列那種類型有出現的分類（收入就只列收入的分類）。
    final cats =
        {
          for (final t in inM)
            if (f.type == null || t.type == f.type) ...book.categoriesOf(t),
        }.toList()..sort(
          (a, b) => ledgerExpenseCats.keys
              .toList()
              .indexOf(a)
              .compareTo(ledgerExpenseCats.keys.toList().indexOf(b)),
        );
    final any =
        f.flagged ||
        f.unconfirmed ||
        f.accountId != null ||
        f.category != null ||
        f.type != null;
    final picked = await showGlassMenu<String>(
      btn,
      width: 230,
      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      selectedValues: {
        if (!any) 'all',
        if (f.type != null) 'type:${f.type!.name}',
        if (f.flagged) 'flag',
        if (f.unconfirmed) 'unconf',
        if (f.accountId != null) 'acct:${f.accountId}',
        if (f.category != null) 'cat:${f.category}',
      },
      items: [
        const GlassMenuItem(
          value: 'all',
          label: '全部',
          icon: Icons.all_inclusive_rounded,
        ),
        const GlassMenuItem(
          value: 'type:expense',
          label: '支出',
          icon: Icons.arrow_upward_rounded,
        ),
        const GlassMenuItem(
          value: 'type:income',
          label: '收入',
          icon: Icons.arrow_downward_rounded,
        ),
        const GlassMenuItem(
          value: 'type:transfer',
          label: '轉帳',
          icon: Icons.swap_horiz_rounded,
        ),
        GlassMenuItem(
          value: 'flag',
          label: '注意 ${inM.where((t) => t.flagged).length}',
          icon: Icons.flag_outlined,
        ),
        // 還沒確認過的（2026-11-11 使用者）。
        GlassMenuItem(
          value: 'unconf',
          label: '未確認 ${inM.where((t) => !t.confirmed).length}',
          icon: Icons.radio_button_unchecked_rounded,
        ),
        const GlassMenuItem(value: 'h:acct', label: '帳戶', header: true),
        for (final a in book.accounts)
          GlassMenuItem(
            value: 'acct:${a.id}',
            label: '${a.type.emoji} ${a.name}',
          ),
        if (cats.isNotEmpty)
          const GlassMenuItem(value: 'h:cat', label: '分類', header: true),
        for (final c in cats)
          GlassMenuItem(value: 'cat:$c', label: '${catLook(c).$1} $c'),
      ],
    );
    if (picked == null) return;
    if (picked == 'all') {
      set(ledgerNoFilter);
    } else if (picked == 'flag') {
      set((
        flagged: !f.flagged,
        unconfirmed: f.unconfirmed,
        accountId: f.accountId,
        category: f.category,
        type: f.type,
      ));
    } else if (picked == 'unconf') {
      set((
        flagged: f.flagged,
        unconfirmed: !f.unconfirmed,
        accountId: f.accountId,
        category: f.category,
        type: f.type,
      ));
    } else if (picked.startsWith('type:')) {
      final ty = LedgerTxType.parse(picked.substring(5));
      set((
        flagged: f.flagged,
        unconfirmed: f.unconfirmed,
        accountId: f.accountId,
        // 換了類型，原本選的分類可能不屬於這種類型，清掉免得變成空的。
        category: null,
        type: f.type == ty ? null : ty,
      ));
    } else if (picked.startsWith('acct:')) {
      final id = picked.substring(5);
      set((
        flagged: f.flagged,
        unconfirmed: f.unconfirmed,
        accountId: f.accountId == id ? null : id,
        category: f.category,
        type: f.type,
      ));
    } else if (picked.startsWith('cat:')) {
      final c = picked.substring(4);
      set((
        flagged: f.flagged,
        unconfirmed: f.unconfirmed,
        accountId: f.accountId,
        category: f.category == c ? null : c,
        type: f.type,
      ));
    }
  }

  // ── 搜尋：像電商網站，打開是另外懸浮的一整頁空白，搜到什麼在下面列，不跟明細混在一起 ──
  void _openSearch(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '搜尋',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const _SearchOverlay(),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .04),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
}

/// 膠囊裡的一格。[active]＝這個篩選有開：換成帶顏色的小膠囊底。
class _CapSeg extends StatelessWidget {
  const _CapSeg({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.width,
    this.onClear,
    this.clearKey,
  });

  /// 篩選中右邊的 ✕：取消這一項。
  final VoidCallback? onClear;
  final Key? clearKey;

  final IconData icon;
  final String? label;
  final bool active;
  final double? width;
  final void Function(BuildContext anchor) onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? ledgerAccent : AppColors.ink2;
    final seg = Builder(
      builder: (anchor) => InkWell(
        onTap: () => onTap(anchor),
        // 篩選中（2026-11-11 使用者：之前是在格子中間再框一個小膠囊，位置對不上）：
        // 整格從分隔線到分隔線鋪滿淡淡的顏色、字變色、圖示右上角一個小點。
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: double.infinity,
          color: active
              ? ledgerAccent.withValues(alpha: .16)
              : Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 18, color: color),
                  if (active)
                    Positioned(
                      right: -3,
                      top: -2,
                      child: Container(
                        key: const ValueKey('capActiveDot'),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: ledgerAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (label != null) ...[
                const SizedBox(width: 5),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: active ? ledgerAccent : AppColors.ink,
                  ),
                ),
                // 篩選中：箭頭換成 ✕，按 ✕ 直接取消這一項（2026-11-11 使用者）。
                if (active && onClear != null)
                  GestureDetector(
                    key: clearKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 2, 8),
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: ledgerAccent.withValues(alpha: .28),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: ledgerAccent,
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: color,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return width != null
        ? SizedBox(width: width, child: seg)
        : Expanded(child: seg);
  }
}

/// 搜尋頁（全螢幕、另外懸浮）：上面一條搜尋框、下面是搜到的結果；搜每個欄位、不管月份。
class _SearchOverlay extends ConsumerStatefulWidget {
  const _SearchOverlay();

  @override
  ConsumerState<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<_SearchOverlay> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(ledgerBookProvider).valueOrNull;
    final q = _q.trim();
    final hits = book == null || q.isEmpty
        ? const <LedgerTx>[]
        : book.txs.where((t) => book.matches(t, q)).toList();
    final st = book?.statsWhere(hits.contains);
    return Scaffold(
      backgroundColor: const Color(0xFF12121C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 14, 6),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('searchBack'),
                    tooltip: '關閉搜尋',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.ink2,
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('searchField'),
                      controller: _c,
                      autofocus: true,
                      inputFormatters: halfWidthFormatters,
                      onChanged: (v) => setState(() => _q = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜尋（多詞以空白間格）',
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _c.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜尋',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _c.clear();
                                  setState(() => _q = '');
                                },
                              ),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.glassFill,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: AppColors.glassEdge,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: AppColors.glassEdge,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: book == null || q.isEmpty
                  ? Center(
                      child: Text(
                        '打字就會搜全部時間、每個欄位',
                        style: AppText.note.copyWith(color: AppColors.ink3),
                      ),
                    )
                  : hits.isEmpty
                  ? Center(
                      child: Text(
                        '找不到「$q」',
                        style: AppText.note.copyWith(color: AppColors.ink3),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.screenSide,
                        0,
                        Gap.screenSide,
                        24,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                          child: Text(
                            '${hits.length} 筆・消費 ${lMoney(st!.spend)}・收入 ${lMoney(st.income)}（搜尋「$q」，全部時間）',
                            style: AppText.note.copyWith(color: AppColors.ink3),
                          ),
                        ),
                        ...groupedTxList(
                          book,
                          hits,
                          (t) => txDetailFlow(context, ref, t.id),
                          query: q,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
