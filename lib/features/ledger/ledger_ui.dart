import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

/// 一筆交易的時分；時間不確定的只知道哪天，顯示「時間不確定」。
String lTxHm(LedgerTx t) => t.timeUnknown
    ? (t.timeOrder == 0 ? '時間不確定' : '時間不確定（排序 ${t.timeOrder}）')
    : lHm(t.occurredAt);

String lHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 總支出裡不是消費的那幾項，例如「幫別人付 \$500＋還款 \$8,000」。
String ledgerOutDetail(SpendStats st) => [
  for (final e in st.extra.entries)
    if (e.value != 0) '${e.key} ${lMoney(e.value)}',
].join('＋');

/// USDT 數量：最多兩位小數，去掉多餘的 0。
String lUsdt(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00')
      ? s.substring(0, s.length - 3)
      : s.endsWith('0')
      ? s.substring(0, s.length - 1)
      : s;
}

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
/// [book] 有給的話：戶頭轉到現金（ATM 提款）用 🏧（2026-11-11 使用者）。
(String, Color) txLook(LedgerTx t, [LedgerBook? book]) {
  switch (t.type) {
    case LedgerTxType.expense:
      final c = ledgerExpenseCats[t.category] ?? ledgerExpenseCats['未分類']!;
      return (c.$1, Color(c.$2));
    case LedgerTxType.income:
      final c = ledgerIncomeCats[t.category] ?? ledgerIncomeCats['其他收入']!;
      return (c.$1, Color(c.$2));
    case LedgerTxType.transfer:
      if (book != null &&
          book.account(t.toAccountId)?.type == LedgerAccountType.cash &&
          book.account(t.accountId)?.type == LedgerAccountType.bank) {
        return ('🏧', const Color(0xFF7EA6FF));
      }
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
  if (cat == ledgerToOtherCat) return ('👤', const Color(0xFF7EA6FF));
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
/// 品牌小圖示（2026-11-11 使用者，自用）：圖檔、要不要轉素色、是不是卡片（橫的）。
typedef LedgerBrand = ({String asset, bool mono, bool card});

const _brandLineBank = (
  asset: 'assets/ledger/icons/linebank.png',
  mono: false,
  card: false,
);
const _brandCtbcCard = (
  asset: 'assets/ledger/icons/ctbc_linepay.png',
  mono: false,
  card: true,
);
// 中信 logo 用素色（2026-11-11 使用者）。
const _brandCtbc = (
  asset: 'assets/ledger/icons/ctbc.png',
  mono: true,
  card: false,
);

bool _isCtbcBank(LedgerAccount? a) =>
    a != null && !a.isCard && a.name.contains('中信');

/// 一筆記帳要不要用品牌圖示（null＝照原本的 emoji）。先後：ATM 提款維持 🏧 →
/// LineBank 相關 → 中信卡相關（熊大那張卡）→ 中信帳戶轉出（中信 logo 素色）。
LedgerBrand? ledgerBrandOf(LedgerBook book, LedgerTx t) {
  final from = book.account(t.accountId);
  final to = book.account(t.toAccountId);
  final transfer = t.type == LedgerTxType.transfer;
  if (transfer &&
      from?.type == LedgerAccountType.bank &&
      to?.type == LedgerAccountType.cash) {
    return null;
  }
  if (t.fromName == 'LineBank' || (!t.toOther && t.toName == 'LineBank')) {
    return _brandLineBank;
  }
  if (book.isCtbcCard(from) || book.isCtbcCard(to)) return _brandCtbcCard;
  if (transfer && _isCtbcBank(from)) return _brandCtbc;
  return null;
}

/// 帳戶的品牌圖示：中信卡＝熊大那張卡、中信的銀行帳戶＝中信 logo 素色。
LedgerBrand? ledgerAccountBrand(LedgerAccount a) => a.isCard
    ? (a.name.contains('中信') ? _brandCtbcCard : null)
    : (_isCtbcBank(a) ? _brandCtbc : null);

/// 中信 logo 用簡單版（綠色那個標誌）做成素色剪影（2026-11-11 使用者：好看一點）。
const _mono = ColorFilter.mode(Color(0xFFC9CED6), BlendMode.srcIn);

/// 台幣面額（2026-11-11 使用者：現金照金額顯示，5 元以內 1 元、10 元以內 5 元，以此類推）。
/// 金額 ≤ 下一個面額 → 顯示上一個面額；超過 2000 都是 2000。
int twdDenomFor(int amount) {
  const steps = [
    (5, 1),
    (10, 5),
    (50, 10),
    (100, 50),
    (200, 100),
    (500, 200),
    (1000, 500),
    (2000, 1000),
  ];
  final a = amount.abs();
  for (final (max, d) in steps) {
    if (a <= max) return d;
  }
  return 2000;
}

/// 現金那筆的小圖示：硬幣（1／5／10／50）是圓的、紙鈔（100 以上）是橫的長方形，
/// 顏色照真的台幣（1 元銅色、5／10 元銀色、50 元金色；100 紅、200 綠、500 咖啡、
/// 1000 藍、2000 紫），中間寫面額。
class TwdMoneyIcon extends StatelessWidget {
  const TwdMoneyIcon(this.amount, {super.key, this.size = 36});

  final int amount;
  final double size;

  static const _coin = <int, (Color, Color)>{
    1: (Color(0xFFE2A46B), Color(0xFF9C5A2A)),
    5: (Color(0xFFE9EDF2), Color(0xFF8D96A3)),
    10: (Color(0xFFF1F3F6), Color(0xFF9AA3AF)),
    50: (Color(0xFFFFE08A), Color(0xFFC99A2E)),
  };
  static const _note = <int, Color>{
    100: Color(0xFFE5484D),
    200: Color(0xFF3FAE6A),
    500: Color(0xFFB7774A),
    1000: Color(0xFF4C7BD9),
    2000: Color(0xFF8E6BD1),
  };

  @override
  Widget build(BuildContext context) {
    final d = twdDenomFor(amount);
    final box = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(size * 0.3),
    );
    final coin = _coin[d];
    final Widget face;
    if (coin != null) {
      final s = size * 0.78;
      face = Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4),
            radius: 0.95,
            colors: [coin.$1, coin.$2],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 3,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Text(
          '$d',
          style: TextStyle(
            fontSize: s * (d >= 10 ? 0.4 : 0.5),
            fontWeight: FontWeight.w900,
            height: 1,
            color: Colors.black.withValues(alpha: 0.62),
          ),
        ),
      );
    } else {
      final c = _note[d]!;
      final w = size * 0.92, h = size * 0.56;
      face = Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.08),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(c, Colors.white, .25)!, c],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 3,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: w * 0.08),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$d',
            style: TextStyle(
              fontSize: h * 0.52,
              fontWeight: FontWeight.w900,
              height: 1,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ),
      );
    }
    return Container(
      key: ValueKey('twd_$d'),
      width: size,
      height: size,
      decoration: box,
      alignment: Alignment.center,
      child: face,
    );
  }
}

class LedgerIcon extends StatelessWidget {
  const LedgerIcon(
    this.emoji,
    this.color, {
    super.key,
    this.size = 36,
    this.brand,
  });

  final String emoji;
  final Color color;
  final double size;

  /// 有的話用品牌圖代替 emoji。
  final LedgerBrand? brand;

  @override
  Widget build(BuildContext context) {
    final b = brand;
    if (b != null) {
      Widget img = Image.asset(
        b.asset,
        fit: b.card ? BoxFit.contain : BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            Text(emoji, style: TextStyle(fontSize: size * 0.47)),
      );
      if (b.mono) img = ColorFiltered(colorFilter: _mono, child: img);
      return Container(
        key: ValueKey('brand_${b.asset.split('/').last}'),
        width: size,
        height: size,
        // 卡片四邊留空，不要被外框圓角裁到（2026-11-11 使用者）；素色 logo 也縮小一點。
        padding: b.card
            ? EdgeInsets.symmetric(horizontal: size * 0.1)
            : b.mono
            ? EdgeInsets.all(size * 0.24)
            : null,
        decoration: BoxDecoration(
          color: b.card || b.mono ? Colors.white.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        clipBehavior: b.card || b.mono ? Clip.none : Clip.antiAlias,
        alignment: Alignment.center,
        child: b.card
            ? ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.06),
                child: img,
              )
            : img,
      );
    }
    return Container(
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
class TxTile extends ConsumerWidget {
  const TxTile({
    super.key,
    required this.book,
    required this.tx,
    required this.onTap,
    this.showDate = false,
    this.partCategory,
    this.query = '',
  });

  final LedgerBook book;
  final LedgerTx tx;
  final VoidCallback onTap;
  final bool showDate;

  /// 搜尋字（明細搜尋時才有）。拆分的消費在搜尋時，每一份各列一行（品項名稱、分類、
  /// 金額、幫人付），符合關鍵字的那份亮起來（2026-11-05 使用者）。
  final String query;

  /// 明細選了某個分類時，拆分的消費只顯示那個分類的子項（金額是那一份，旁邊寫
  /// 「拆分自 $整筆」），點下去還是開整筆（2026-11-03 使用者）。
  final String? partCategory;

  static List<String> _terms(String q) =>
      q.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

  /// 搜尋時拆分的一份：「└ 品項名稱（分類） $金額 👥」，符合關鍵字的亮起來。
  Widget _partLine(LedgerSplit s, List<String> terms) {
    final hay = '${s.name} ${s.category} ${s.amount}'.toLowerCase();
    final hit = terms.any(hay.contains);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '└ ${s.name.isEmpty ? s.category : '${s.name}（${s.category}）'}'
        '　${lMoney(s.amount)}'
        '${s.forOther ? '　👥${s.people.isEmpty ? '' : '${s.people} '}${s.settled ? '已給' : '幫人付'}${s.otherPart != s.amount ? ' ${lMoney(s.otherPart)}' : ''}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: hit ? FontWeight.w800 : FontWeight.w500,
          color: hit ? ledgerAccent : AppColors.ink3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 設定→記帳可以選不顯示備註。
    final showNote = ref.watch(ledgerShowNoteProvider);
    final t = tx;
    // 圖示看付款方式（2026-11-03 使用者）：現金＝鈔票、刷卡＝信用卡、銀行＝銀行；
    // 轉帳、退款、還錢、調整照原本的符號。
    final acct = book.account(t.accountId);
    final (emoji, color) =
        (t.type == LedgerTxType.expense || t.type == LedgerTxType.income) &&
            acct != null
        ? (acct.type.emoji, accountColor(acct.type))
        : txLook(t, book);
    final sub = StringBuffer();
    if (showDate) sub.write('${lMd(t.occurredAt)} ');
    sub.write(lTxHm(t));
    sub.write('・');
    if (t.type == LedgerTxType.transfer) {
      sub.write('${book.fromLabel(t)} → ${book.toLabel(t)}');
      if (t.extAmount != null) sub.write(' ${lUsdt(t.extAmount!)} USDT');
    } else {
      sub.write(book.accountName(t.accountId));
      if (t.category != null && t.type != LedgerTxType.adjustment) {
        sub.write(
          t.isSplit && query.trim().isNotEmpty
              ? '・拆分 ${t.splits.length} 份'
              : t.isSplit
              ? '・拆分 ${t.splits.map((s) => '${s.name.isNotEmpty ? '${s.name}（${s.category}）' : s.category}${lInt(s.amount)}${s.forOther ? '👥' : ''}').join('、')}'
              : '・${t.category}',
        );
      }
    }
    if (showNote && t.note.isNotEmpty) sub.write('・${t.note}');
    // 選了分類又是拆分的：只顯示那個分類的子項金額。
    final part = partCategory != null && t.isSplit
        ? t.splits
              .where((x) => x.category == partCategory)
              .fold<int>(0, (a, x) => a + x.amount)
        : null;
    final (amt, amtColor, small) = switch (t.type) {
      LedgerTxType.expense => (
        '−${lMoney(part ?? t.amount)}',
        AppColors.ink,
        part != null
            ? '拆分自 ${lMoney(t.amount)}'
            : t.paidFor == null
            ? null
            : '自己 ${lMoney(t.ownSpend)}',
      ),
      LedgerTxType.income => ('+${lMoney(t.amount)}', AppColors.ok, null),
      LedgerTxType.refund => ('+${lMoney(t.amount)}', AppColors.ok, '退款'),
      LedgerTxType.repayment => ('+${lMoney(t.amount)}', ledgerPaidFor, '不算收入'),
      LedgerTxType.transfer =>
        book.isCardReturn(t)
            ? ('+${lMoney(t.amount)}', AppColors.ok, '卡費退回')
            : (
                lMoney(t.amount),
                AppColors.ink3,
                t.toOther
                    ? '轉給他人'
                    : t.toName.isNotEmpty || t.fromName.isNotEmpty
                    ? '平轉'
                    : '不算支出',
              ),
      LedgerTxType.adjustment => (
        '${t.isAdjustOut ? '−' : '+'}${lMoney(t.amount)}',
        AppColors.mid,
        '對帳調整',
      ),
    };
    final pf = t.paidFor;
    final gaps = book.gapsOfTx(t.id);
    final cp = book.checkpointOfTx(t.id);
    // 毛玻璃（2026-11-03 使用者）：背後模糊＋半透明填色＋邊線，跟 GlassCard 同一套
    // 做法；對帳調整那種用黃色邊線。
    final shape = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          ClipRRect(
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
                            // 現金付的照金額顯示台幣硬幣／紙鈔（2026-11-11 使用者）。
                            if ((t.type == LedgerTxType.expense ||
                                    t.type == LedgerTxType.income) &&
                                acct?.type == LedgerAccountType.cash)
                              TwdMoneyIcon(t.amount)
                            else
                              LedgerIcon(
                                emoji,
                                color,
                                brand: ledgerBrandOf(book, t),
                              ),
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
                                  // 單筆的品項名稱（2026-11-09 使用者）。
                                  if (t.item.isNotEmpty)
                                    Text(
                                      t.item,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.note.copyWith(
                                        fontSize: 11.5,
                                        color: AppColors.ink2,
                                      ),
                                    ),
                                  // 標籤排在名稱下一行，名字長也不會擠爆。
                                  if (pf != null ||
                                      t.isSplit ||
                                      t.source == 'paste' ||
                                      gaps.isNotEmpty ||
                                      cp != null ||
                                      book.usdtDiffOf(t) != null)
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
                                          // 轉帳（繳卡費）兩邊都填了，哪一邊對不上就寫哪一邊。
                                          for (final g in gaps)
                                            LedgerPill(
                                              '⚠ ${t.type == LedgerTxType.transfer ? g.account.name : ''}'
                                              '${g.miss > 0 ? '漏記' : '多出'} '
                                              '${lMoney(g.miss.abs())}',
                                              color: AppColors.mid,
                                            ),
                                          if (gaps.isEmpty && cp != null)
                                            LedgerPill(
                                              cp.available != null
                                                  ? '可用 ${lMoney(cp.available!)}'
                                                  : '餘額 ${lMoney(cp.balance ?? 0)}',
                                            ),
                                          if (t.isSplit)
                                            LedgerPill(
                                              part != null
                                                  ? '拆分・$partCategory'
                                                  : '已拆 ${t.splits.length} 份',
                                              color: const Color(0xFFB79CFF),
                                            ),
                                          if (t.source == 'paste')
                                            const LedgerPill('匯入'),
                                          // 虛擬貨幣餘額跟推算有差：確認是盈虧的寫盈虧，還沒確認的提醒。
                                          if (book.usdtDiffOf(t) case final d?)
                                            LedgerPill(
                                              t.extPnlOk
                                                  ? '${d > 0 ? '盈利 +' : '虧損 −'}${lUsdt(d.abs())} USDT'
                                                  : '⚠ 虛擬貨幣差 ${d > 0 ? '+' : '−'}${lUsdt(d.abs())} USDT',
                                              color: t.extPnlOk
                                                  ? (d > 0
                                                        ? AppColors.ok
                                                        : ledgerBad)
                                                  : AppColors.mid,
                                            ),
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
                                  if (t.isSplit && query.trim().isNotEmpty)
                                    for (final s in t.splits)
                                      _partLine(s, _terms(query)),
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
          // 還沒確認的右上角一個小藍點（2026-11-11 使用者：沒確認的才要特別標，
          // 確認過的就乾淨；要確認點進明細按「標成已確認」）。
          if (!t.confirmed && ref.watch(ledgerConfirmOnProvider))
            Positioned(
              top: 7,
              right: 7,
              child: IgnorePointer(
                child: Container(
                  key: ValueKey('unconfirmed_${t.id}'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DA3FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4DA3FF).withValues(alpha: .6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
    // 還沒對過就不寫狀態，只放一顆「對帳」按鈕（2026-11-03 使用者）；對過才顯示結果。
    final (String top, Color topColor, String bottom)? status =
        s == null || !s.checked
        ? null
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
            LedgerIcon(
              a.type.emoji,
              accountColor(a.type),
              brand: ledgerAccountBrand(a),
            ),
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
                  if (s != null)
                    Text(
                      a.isCard
                          ? 'App 推算可刷額 ${lMoney(s.available)}'
                          : 'App 推算餘額 ${lMoney(s.now)}',
                      style: AppText.note.copyWith(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                      ),
                    ),
                ],
              ),
            ),
            if (status != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status.$1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: status.$2,
                    ),
                  ),
                  Text(
                    status.$3,
                    style: AppText.note.copyWith(
                      fontSize: 10,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              )
            else
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.glassEdge),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('對帳'),
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
  void Function(LedgerTx) onTap, {
  String? partCategory,
  String query = '',
}) {
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
    out.add(
      TxTile(
        book: book,
        tx: t,
        partCategory: partCategory,
        query: query,
        onTap: () => onTap(t),
      ),
    );
  }
  return out;
}

/// 這天之前的資料不準確、只是記錄下來（2026-11-03 使用者：2026 年 11 月以前的首頁
/// 卡片跟明細上方都要標註）。
final ledgerAccurateFrom = DateTime(2026, 11, 1);

bool isBeforeAccurate(int year, int month) =>
    DateTime(year, month).isBefore(ledgerAccurateFrom);

/// 「2026年11月以前資料不完整，僅紀錄」的提示條。
/// 2026-11-11 使用者：文案改這樣；顏色從黃色改成淡淡偏灰（只是提醒，不要太搶眼）。
const _oldDataTone = Color(0xFFB4B0A2);

class OldDataBanner extends StatelessWidget {
  const OldDataBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _oldDataTone.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _oldDataTone.withValues(alpha: 0.22)),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: _oldDataTone),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '2026年11月以前資料不完整，僅紀錄',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _oldDataTone,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 記帳設定裡「消費、總支出、收入怎麼算」的說明（2026-11-11 使用者）。
Future<void> showLedgerTermsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) {
    Widget h(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
    Widget p(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        t,
        style: const TextStyle(fontSize: 13, color: AppColors.ink2),
      ),
    );
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A27),
      title: const Text('消費、總支出、收入怎麼算', style: TextStyle(color: AppColors.ink)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              h('💸 消費（自己花掉的）'),
              p('・支出只算自己那份：跟別人一起付、拆分裡幫人付的那份不算。'),
              p('・對帳調整「少了錢」算進「未分類」。'),
              p('・退款會扣回去（算回原本那筆的分類）。'),
              p('・不算：「還款」分類、轉帳（含轉給他人）、繳卡費、提款。'),
              p('・預算、剩餘可花、平均每天花、分類佔比都看消費。'),
              h('📤 總支出（錢實際離開的全部）'),
              p('・總支出＝消費＋幫別人付（對方那份）＋還款＋轉給他人。'),
              p('・轉給他人：轉帳「轉到」選「他人戶頭」。'),
              p('・不算：轉到自己的帳戶（平轉：LineBank、富邦、虛擬貨幣、ATM 提款）、繳卡費（刷卡時已經算過）。'),
              h('💰 收入'),
              p('・收入分類的薪資、獎金、其他收入、未分類都算。'),
              p('・不算：收入分類「平轉」（自己的戶頭轉來轉去）、別人還你錢（收到欠款）。'),
              h('🔁 不算任何一種'),
              p('・繳卡費、ATM 提款、轉到自己的帳戶：只是錢換個地方放，帳戶餘額照樣會動。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('關閉')),
      ],
    );
  },
);
