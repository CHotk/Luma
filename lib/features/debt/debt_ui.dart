import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../domain/debt_schedule.dart';
import '../../domain/models/debt.dart';

/// 負債管理各頁共用的小東西（只給這個功能用）：金額日期格式、債務圖示、
/// 一期繳款列、債務卡。

const debtAccent = Color(0xFF7EA6FF);
const debtBad = Color(0xFFFF7A70);

String _group(int n) => n.abs().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// 「$12,345」。
String money(double v) => '${v < 0 ? '−' : ''}\$${_group(v.round())}';

String fmtInt(double v) => _group(v.round());

const _wd = ['一', '二', '三', '四', '五', '六', '日'];

String md(DateTime d) => '${d.month}/${d.day}';
String mdw(DateTime d) => '${md(d)}（${_wd[d.weekday - 1]}）';
String ym(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}';
String ymd(DateTime d) => '${d.year}/${d.month}/${d.day}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysBetween(DateTime from, DateTime to) =>
    dayOnly(to).difference(dayOnly(from)).inDays;

/// 債務種類的圓角方塊圖示。
class DebtIcon extends StatelessWidget {
  const DebtIcon(this.type, {super.key, this.size = 36});

  final DebtType type;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: type.color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: Text(type.emoji, style: TextStyle(fontSize: size * 0.47)),
  );
}

/// 小圓角標籤（已繳、逾期、幾天後）。
class DebtPill extends StatelessWidget {
  const DebtPill(this.text, {super.key, this.color = AppColors.ink2});

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

/// 進度條。
class DebtBar extends StatelessWidget {
  const DebtBar(this.percent, {super.key, this.color = debtAccent});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: LinearProgressIndicator(
      value: (percent / 100).clamp(0, 1),
      minHeight: 7,
      backgroundColor: const Color(0xFF1E1E2E),
      color: color,
    ),
  );
}

/// 某個月的一期：左邊圓圈（點了標記已繳／取消），中間名稱扣款日，右邊
/// 金額跟狀態。點整列看明細。
class DueTile extends StatelessWidget {
  const DueTile({
    super.key,
    required this.item,
    required this.today,
    required this.onTap,
    required this.onCheck,
  });

  final DueItem item;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final d = item.debt, r = item.row;
    final paid = item.isPaid;
    final over = item.isOverdue(today);
    final days = daysBetween(today, r.date);
    final status = paid
        ? DebtPill('已繳 ${md(r.payment?.date ?? r.date)}', color: AppColors.ok)
        : over
        ? DebtPill('逾期 ${-days} 天', color: debtBad)
        : days == 0
        ? const DebtPill('今天', color: AppColors.mid)
        : DebtPill('$days 天後');
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Opacity(
        opacity: paid ? 0.6 : 1,
        child: Material(
          color: over
              ? debtBad.withValues(alpha: 0.07)
              : const Color(0xFF161622),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: over
                  ? debtBad.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
              child: Row(
                children: [
                  if (!item.isPayoff)
                    IconButton(
                      onPressed: onCheck,
                      tooltip: paid ? '取消已繳' : '標記已繳',
                      icon: Icon(
                        paid
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: paid ? AppColors.ok : AppColors.ink3,
                        size: 26,
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                  DebtIcon(d.type),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d.name}${item.isPayoff ? '（提前清償）' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${mdw(r.date)}・${d.lender}'
                          '${item.isPayoff || d.flexible
                              ? ''
                              : d.isBill
                              ? '・${r.date.month} 月帳單'
                              : '・第 ${r.k} 期'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.note.copyWith(color: AppColors.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money(item.amount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      status,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一筆債務的卡片：名稱、剩多少、進度條、已還幾期、預計還清。
class DebtCard extends StatelessWidget {
  const DebtCard({super.key, required this.stats, required this.onTap});

  final DebtStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = stats, d = s.debt;
    if (d.isBill) return _bill(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DebtIcon(d.type),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            '${d.lender}・${d.flexible ? '自由還款' : '${d.rate}%'}'
                            '・${s.closed ? '已還清' : '每月 ${money(s.monthly)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.note.copyWith(color: AppColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money(s.remaining),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          s.closed ? '🎉 已還清' : '剩餘',
                          style: AppText.note.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                DebtBar(s.percent, color: d.type.color),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '已還 ${s.percent.toStringAsFixed(0)}%・${s.paidCount}'
                      '${d.flexible ? '' : '/${s.totalCount}'} 期',
                      style: AppText.note.copyWith(fontSize: 10.5),
                    ),
                    const Spacer(),
                    if (s.overdueDays > 0)
                      DebtPill('逾期 ${s.overdueDays} 天', color: debtBad)
                    else
                      Text(
                        s.payoffDate == null
                            ? ''
                            : s.closed
                            ? '還清於 ${ym(s.payoffDate!)}'
                            : '預計 ${ym(s.payoffDate!)} 還清',
                        style: AppText.note.copyWith(fontSize: 10.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on DebtCard {
  /// 信用卡帳單：不畫進度條、不寫剩餘，寫這期大概多少跟下次扣款日。
  Widget _bill(BuildContext context) {
    final s = stats, d = s.debt, next = s.next;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DebtIcon(d.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        '${d.lender}・每月帳單・每月 ${d.dueDay} 號扣款',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.note.copyWith(color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '約 ${money(d.flexPay)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (s.overdueDays > 0)
                      DebtPill('逾期 ${s.overdueDays} 天', color: debtBad)
                    else
                      Text(
                        next == null ? '' : '下次 ${mdw(next.date)}',
                        style: AppText.note.copyWith(fontSize: 10.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 三格小數字（應繳／已繳／未繳這種）。
class DebtKpi extends StatelessWidget {
  const DebtKpi(this.value, this.label, {super.key, this.color, this.onTap});

  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color ?? AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                onTap == null ? label : '$label ✎',
                style: AppText.note.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 「佔收入 44% ✎」：超過 40% 紅、33% 以上黃。沒填收入就是「設定月收入」。
Widget incomeRatioLabel(double? ratio, VoidCallback onTap) => InkWell(
  onTap: onTap,
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: ratio == null
        ? const Text(
            '設定月收入 ✎',
            style: TextStyle(fontSize: 11, color: debtAccent),
          )
        : Text.rich(
            TextSpan(
              style: AppText.note,
              children: [
                const TextSpan(text: '佔收入 '),
                TextSpan(
                  text: '${ratio.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ratio > 40
                        ? debtBad
                        : ratio > 33
                        ? AppColors.mid
                        : AppColors.ok,
                  ),
                ),
                const TextSpan(text: ' ✎'),
              ],
            ),
          ),
  ),
);
