import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/models/ledger.dart';

/// 記帳各頁共用的小東西（只給這個功能用）：金額日期格式、分類圖示、
/// 一筆交易列、帳戶對帳狀態列。

const ledgerAccent = Color(0xFF5FE0A8);
const ledgerBad = Color(0xFFFF7A70);
const ledgerPaidFor = Color(0xFF9DBBFF);
const ledgerTileBg = Color(0xFF161622);

String _group(int n) => n.abs().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// 「$12,345」，負的是「−$12,345」。
String lMoney(int v) => '${v < 0 ? '−' : ''}\$${_group(v)}';
String lInt(int v) => _group(v);

const _wd = ['一', '二', '三', '四', '五', '六', '日'];
String lMd(DateTime d) => '${d.month}/${d.day}';
String lMdw(DateTime d) => '${lMd(d)}（${_wd[d.weekday - 1]}）';
String lHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String lYmd(DateTime d) => '${d.year}/${d.month}/${d.day}';
bool lSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String lAgo(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return '剛剛';
  if (m < 60) return '$m 分鐘前';
  if (m < 60 * 24) return '${m ~/ 60} 小時前';
  return '${m ~/ (60 * 24)} 天前';
}

/// 分類（或交易類型）的圖示跟顏色。
(String, Color) txLook(LedgerTx t) {
  switch (t.type) {
    case LedgerTxType.expense:
      final c = ledgerExpenseCats[t.category] ?? ledgerExpenseCats['未分類']!;
      return (c.$1, Color(c.$2));
    case LedgerTxType.income:
      final c = ledgerIncomeCats[t.category] ?? ledgerIncomeCats['其他收入']!;
      return (c.$1, Color(c.$2));
    case LedgerTxType.transfer:
      return ('⇄', const Color(0xFF7EA6FF));
    case LedgerTxType.refund:
      return ('↩️', AppColors.ok);
    case LedgerTxType.repayment:
      return ('🤝', ledgerPaidFor);
    case LedgerTxType.adjustment:
      return ('⚖️', AppColors.mid);
  }
}

(String, Color) catLook(String cat) {
  final c =
      ledgerExpenseCats[cat] ??
      ledgerIncomeCats[cat] ??
      ledgerExpenseCats['未分類']!;
  return (c.$1, Color(c.$2));
}

Color accountColor(LedgerAccountType t) => switch (t) {
  LedgerAccountType.bank => const Color(0xFF7EA6FF),
  LedgerAccountType.creditCard => const Color(0xFFFF9F7A),
  LedgerAccountType.cash => AppColors.ok,
};

/// 圓角方塊圖示（emoji）。
class LedgerIcon extends StatelessWidget {
  const LedgerIcon(this.emoji, this.color, {super.key, this.size = 36});

  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: Text(emoji, style: TextStyle(fontSize: size * 0.47)),
  );
}

class LedgerPill extends StatelessWidget {
  const LedgerPill(this.text, {super.key, this.color = AppColors.ink2});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class LedgerBar extends StatelessWidget {
  const LedgerBar(this.ratio, {super.key, this.color = ledgerAccent});

  /// 0–1。
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: LinearProgressIndicator(
      value: ratio.isNaN ? 0 : ratio.clamp(0, 1),
      minHeight: 7,
      backgroundColor: const Color(0xFF1E1E2E),
      color: color,
    ),
  );
}

const lTabular = [FontFeature.tabularFigures()];

/// 一筆交易：圖示、名稱（🚩、幫付、匯入標籤）、時間帳戶分類、金額。
class TxTile extends StatelessWidget {
  const TxTile({
    super.key,
    required this.book,
    required this.tx,
    required this.onTap,
    this.showDate = false,
  });

  final LedgerBook book;
  final LedgerTx tx;
  final VoidCallback onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = tx;
    final (emoji, color) = txLook(t);
    final sub = StringBuffer();
    if (showDate) sub.write('${lMd(t.occurredAt)} ');
    sub.write(lHm(t.occurredAt));
    sub.write('・');
    if (t.type == LedgerTxType.transfer) {
      sub.write(
        '${book.accountName(t.accountId)} → ${book.accountName(t.toAccountId)}',
      );
    } else {
      sub.write(book.accountName(t.accountId));
      if (t.category != null && t.type != LedgerTxType.adjustment) {
        sub.write('・${t.category}');
      }
    }
    if (t.note.isNotEmpty) sub.write('・${t.note}');
    final (amt, amtColor, small) = switch (t.type) {
      LedgerTxType.expense => (
        '−${lMoney(t.amount)}',
        AppColors.ink,
        t.paidFor == null ? null : '自己 ${lMoney(t.ownSpend)}',
      ),
      LedgerTxType.income => ('+${lMoney(t.amount)}', AppColors.ok, null),
      LedgerTxType.refund => ('+${lMoney(t.amount)}', AppColors.ok, '退款'),
      LedgerTxType.repayment => ('+${lMoney(t.amount)}', ledgerPaidFor, '不算收入'),
      LedgerTxType.transfer => (lMoney(t.amount), AppColors.ink3, '不算支出'),
      LedgerTxType.adjustment => (
        '${t.isAdjustOut ? '−' : '+'}${lMoney(t.amount)}',
        AppColors.mid,
        '對帳調整',
      ),
    };
    final pf = t.paidFor;
    final gap = book.gapOfTx(t.id);
    final cp = book.checkpointOfTx(t.id);
    // 毛玻璃（2026-11-03 使用者）：背後模糊＋半透明填色＋邊線，跟 GlassCard 同一套
    // 做法；對帳調整那種用黃色邊線。
    final shape = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x1FFFFFFF), Color(0x0DFFFFFF)],
              ),
              border: Border.all(
                color: t.type == LedgerTxType.adjustment
                    ? AppColors.mid.withValues(alpha: 0.45)
                    : AppColors.glassEdge,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        LedgerIcon(emoji, color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      t.merchant.isEmpty
                                          ? t.type.label
                                          : t.merchant,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  if (t.flagged) const Text(' 🚩'),
                                ],
                              ),
                              // 標籤排在名稱下一行，名字長也不會擠爆。
                              if (pf != null ||
                                  t.source == 'paste' ||
                                  gap != null ||
                                  cp != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Wrap(
                                    spacing: 5,
                                    runSpacing: 3,
                                    children: [
                                      if (pf != null)
                                        LedgerPill(
                                          // 他給了之後標籤保留「誰要給多少」，只是變綠、
                                          // 後面多一個 ✓（2026-11-03 使用者）。
                                          '${pf.people} 要給 ${lMoney(pf.amount)}'
                                          '${pf.settled ? ' ✓已給' : ''}',
                                          color: pf.settled
                                              ? AppColors.ok
                                              : ledgerPaidFor,
                                        ),
                                      if (gap != null)
                                        LedgerPill(
                                          gap.miss > 0
                                              ? '⚠ 漏記 ${lMoney(gap.miss)}'
                                              : '⚠ 多出 ${lMoney(-gap.miss)}',
                                          color: AppColors.mid,
                                        )
                                      else if (cp != null)
                                        LedgerPill(
                                          cp.available != null
                                              ? '可用 ${lMoney(cp.available!)}'
                                              : '餘額 ${lMoney(cp.balance ?? 0)}',
                                        ),
                                      if (t.source == 'paste')
                                        const LedgerPill('匯入'),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Text(
                                sub.toString(),
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
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amt,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: amtColor,
                                fontFeatures: lTabular,
                              ),
                            ),
                            if (small != null)
                              Text(
                                small,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.ink3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一個帳戶的對帳狀態（記帳完整度卡片裡的一列）。
class AccountStatusRow extends StatelessWidget {
  const AccountStatusRow({
    super.key,
    required this.account,
    required this.state,
    required this.onTap,
  });

  final LedgerAccount account;

  /// null＝還沒填過餘額。
  final AccountState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = state, a = account;
    final (String top, Color topColor, String bottom) = s == null
        ? ('沒填餘額', AppColors.ink3, '要對帳再填')
        : !s.checked
        ? ('還沒對帳', AppColors.ink3, '點這裡對第一次')
        : s.miss == 0
        ? ('✓ 已對帳', AppColors.ok, lAgo(s.last.at))
        : (
            '⚠ 差 ${lMoney(s.miss.abs())}',
            AppColors.mid,
            s.miss > 0 ? '可能漏記支出' : '多出來的錢',
          );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    s == null
                        ? '只記交易'
                        : a.isCard
                        ? 'App 推算可刷卡餘額 ${lMoney(s.available)}'
                        : 'App 推算餘額 ${lMoney(s.now)}',
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
                  top,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: topColor,
                  ),
                ),
                Text(
                  bottom,
                  style: AppText.note.copyWith(
                    fontSize: 10,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 小標題列：左邊標題，右邊可點的文字。
Widget ledgerSection(String title, {String? action, VoidCallback? onAction}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
          const Spacer(),
          if (action != null)
            InkWell(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  action,
                  style: AppText.note.copyWith(color: ledgerAccent),
                ),
              ),
            ),
        ],
      ),
    );

/// 依日期分組的交易清單（每組標題寫那天花多少）。
List<Widget> groupedTxList(
  LedgerBook book,
  List<LedgerTx> txs,
  void Function(LedgerTx) onTap,
) {
  final out = <Widget>[];
  DateTime? cur;
  for (final t in txs) {
    final d = t.occurredAt;
    if (cur == null || !lSameDay(cur, d)) {
      // 每一天之間有分隔（2026-11-03 使用者）：日期＋一條線＋當天花多少，
      // 前一天跟這一天中間多留一點空白。
      final first = cur == null;
      cur = d;
      final s = book.statsWhere(LedgerBook.onDay(d));
      out.add(
        Padding(
          padding: EdgeInsets.fromLTRB(4, first ? 10 : 22, 4, 10),
          child: Row(
            children: [
              Text(
                '${lMdw(d)}${lSameDay(d, DateTime.now()) ? '・今天' : ''}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x33FFFFFF),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                [
                  if (s.spend != 0) '花 ${lMoney(s.spend)}',
                  if (s.income != 0) '收 ${lMoney(s.income)}',
                ].join('・'),
                style: AppText.note.copyWith(color: AppColors.ink3),
              ),
            ],
          ),
        ),
      );
    }
    out.add(TxTile(book: book, tx: t, onTap: () => onTap(t)));
  }
  return out;
}
