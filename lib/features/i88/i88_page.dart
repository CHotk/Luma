import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/i88.dart';
import '../../shared/digits_input.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/date_time_wheel.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

/// i88（2026-11-03 使用者：單純新增輸多少、贏多少，目的是看每月有沒有達標；
/// 簡單用月曆卡記錄，跟交易分開，金額用台幣）。上面本月輸贏＋每月目標進度，
/// 中間月曆（每天寫當天淨輸贏），下面是選到那天的紀錄，右下角 ＋ 新增。
///
/// 贏綠、輸紅（跟交易&自律一樣，使用者指定，跟台股相反）。

class _I88Data {
  const _I88Data(this.entries, this.target);

  final List<I88Entry> entries;
  final int? target;

  int net(bool Function(I88Entry) test) =>
      entries.where(test).fold(0, (s, e) => s + e.amount);
}

final _dataProvider = FutureProvider.autoDispose<_I88Data>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.read(i88RepositoryProvider);
  return _I88Data(await repo.loadEntries(), await repo.loadTarget());
});

final _monthProvider = StateProvider<DateTime>(
  (_) => DateTime(DateTime.now().year, DateTime.now().month),
);
final _dayProvider = StateProvider<DateTime>((_) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

/// 月曆下面的篩選標籤（2026-11-05 使用者：跟交易&自律一樣，點了月曆上亮出符合的日子）：
/// `win` 贏的日子、`lose` 輸的日子、`any` 有記錄的日子；null 是沒選。再點一次取消。
final _hintProvider = StateProvider<String?>((_) => null);

bool _hintMatch(String hint, int? net) => switch (hint) {
  'win' => net != null && net > 0,
  'lose' => net != null && net < 0,
  _ => net != null,
};

const _win = AppColors.ok;
const _lose = Color(0xFFFF7A70);

String _group(int n) => n.abs().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// 「+$1,200」「−$300」，0 是「$0」。
String _signed(int v) => v == 0 ? '\$0' : '${v > 0 ? '+' : '−'}\$${_group(v)}';
String _plain(int v) => '${v < 0 ? '−' : ''}\$${_group(v)}';
Color _color(int v) => v > 0
    ? _win
    : v < 0
    ? _lose
    : AppColors.ink3;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _wd = ['一', '二', '三', '四', '五', '六', '日'];

class I88Page extends ConsumerWidget {
  const I88Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dataProvider).valueOrNull;
    return Scaffold(
      drawer: const AppSideDrawer(),
      floatingActionButton: data == null
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(context, ref, null),
              tooltip: '記一筆輸贏',
              child: const Icon(Icons.add_rounded),
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
                const AppTopBar(
                  title: 'i88',
                  titleIcon: Icons.casino_outlined,
                  titleIconColor: Color(0xFFE08F5F),
                  showBack: false,
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: data == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 96),
                          children: _body(context, ref, data),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, _I88Data d) {
    final m = ref.watch(_monthProvider);
    final day = ref.watch(_dayProvider);
    final hint = ref.watch(_hintProvider);
    bool inMonth(I88Entry e) => e.at.year == m.year && e.at.month == m.month;
    final monthNet = d.net(inMonth);
    final wins = d.entries
        .where((e) => inMonth(e) && e.amount > 0)
        .fold(0, (s, e) => s + e.amount);
    final losses = d.entries
        .where((e) => inMonth(e) && e.amount < 0)
        .fold(0, (s, e) => s - e.amount);
    final target = d.target;
    final days = DateTime(m.year, m.month + 1, 0).day;
    final first = DateTime(m.year, m.month, 1).weekday; // 1=一
    final dayNet = <int, int>{};
    for (final e in d.entries.where(inMonth)) {
      dayNet[e.at.day] = (dayNet[e.at.day] ?? 0) + e.amount;
    }
    final dayList = d.entries.where((e) => _sameDay(e.at, day)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final now = DateTime.now();
    final isCur = now.year == m.year && now.month == m.month;

    void go(int delta) {
      ref.read(_monthProvider.notifier).state = DateTime(
        m.year,
        m.month + delta,
      );
      ref.read(_dayProvider.notifier).state = DateTime(
        m.year,
        m.month + delta,
        1,
      );
    }

    return [
      Row(
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
      ),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('本月輸贏', style: AppText.note),
                const Spacer(),
                InkWell(
                  onTap: () => _editTarget(context, ref, target),
                  child: Text(
                    target == null ? '設定每月目標 ✎' : '目標 ${_plain(target)} ✎',
                    style: AppText.note.copyWith(
                      color: const Color(0xFFE08F5F),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _signed(monthNet),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: _color(monthNet),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '贏 ${_plain(wins)}・輸 ${_plain(losses)}',
              style: AppText.note.copyWith(color: AppColors.ink3),
            ),
            if (target != null && target > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(
                  value: (monthNet / target).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  backgroundColor: const Color(0xFF1E1E2E),
                  color: monthNet >= target ? _win : const Color(0xFFE08F5F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                monthNet >= target
                    ? '🎉 達標了，多 ${_plain(monthNet - target)}'
                    : '還差 ${_plain(target - monthNet)}'
                          '${isCur ? '（還有 ${days - now.day + 1} 天）' : ''}',
                style: AppText.note.copyWith(
                  color: monthNet >= target ? _win : AppColors.ink2,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: Gap.md),
      GlassCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                for (final w in _wd)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: AppText.note.copyWith(
                          fontSize: 10,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.8,
              children: [
                for (var i = 1; i < first; i++) const SizedBox.shrink(),
                for (var n = 1; n <= days; n++)
                  _cell(
                    ref,
                    DateTime(m.year, m.month, n),
                    dayNet[n],
                    day,
                    hint: hint,
                  ),
              ],
            ),
            if (dayNet.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (key, label, color, count) in [
                    (
                      'win',
                      '贏的日子',
                      _win,
                      dayNet.values.where((v) => v > 0).length,
                    ),
                    (
                      'lose',
                      '輸的日子',
                      _lose,
                      dayNet.values.where((v) => v < 0).length,
                    ),
                    ('any', '有記錄的日子', const Color(0xFFE08F5F), dayNet.length),
                  ])
                    if (count > 0)
                      _hintChip(ref, key, '$label $count', color, hint == key),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '點標籤，月曆上亮出符合的日子',
                style: AppText.note.copyWith(color: AppColors.ink3),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(
          children: [
            Text(
              '${day.month}/${day.day}（${_wd[day.weekday - 1]}）'
              '${_sameDay(day, now) ? '・今天' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => _edit(context, ref, null, day: day),
              child: Text(
                '＋ 記在這天',
                style: AppText.note.copyWith(color: const Color(0xFFE08F5F)),
              ),
            ),
          ],
        ),
      ),
      if (dayList.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('這天還沒有紀錄', style: AppText.bodyDim),
        ),
      for (final e in dayList) _tile(context, ref, e),
    ];
  }

  Widget _hintChip(
    WidgetRef ref,
    String key,
    String label,
    Color color,
    bool selected,
  ) => InkWell(
    borderRadius: BorderRadius.circular(99),
    onTap: () => ref.read(_hintProvider.notifier).state = selected ? null : key,
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 11, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: selected ? color.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: selected ? color : const Color(0xFF2A2A3D),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cell(
    WidgetRef ref,
    DateTime date,
    int? net,
    DateTime selected, {
    String? hint,
  }) {
    final sel = _sameDay(date, selected);
    final today = _sameDay(date, DateTime.now());
    final c = net == null ? null : _color(net);
    // 選了標籤：符合的日子用標籤的顏色框起來、底色加亮，其他天變淡。
    final lit = hint != null && _hintMatch(hint, net);
    final dim = hint != null && !lit;
    final litColor = hint == 'win'
        ? _win
        : hint == 'lose'
        ? _lose
        : const Color(0xFFE08F5F);
    return Opacity(
      opacity: dim ? 0.25 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ref.read(_dayProvider.notifier).state = date,
        child: _cellBody(date, net, c, sel, today, lit, litColor),
      ),
    );
  }

  Widget _cellBody(
    DateTime date,
    int? net,
    Color? c,
    bool sel,
    bool today,
    bool lit,
    Color litColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: c == null
            ? Colors.white.withValues(alpha: 0.035)
            : c.withValues(alpha: lit ? 0.4 : 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel
              ? const Color(0xFFE08F5F)
              : lit
              ? litColor
              : today
              ? AppColors.ink3
              : Colors.transparent,
          width: lit ? 1.8 : 1.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${date.day}', style: AppText.note.copyWith(fontSize: 10.5)),
          const Spacer(),
          if (net != null)
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  net.abs() >= 10000
                      ? '${net > 0 ? '+' : '−'}${(net.abs() / 1000).toStringAsFixed(0)}k'
                      : _signed(net).replaceAll('\$', ''),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, I88Entry e) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: const Color(0xFF161622),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(context, ref, e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Text(e.isWin ? '🟢' : '🔴', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.isWin ? '贏' : '輸',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    // 只記到天，不顯示時分（2026-11-09 使用者）。
                    Text(
                      e.note.isEmpty ? '${e.at.month}/${e.at.day}' : e.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
              Text(
                _signed(e.amount),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _color(e.amount),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ── 新增／編輯 ───────────────────────────────────────────

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    I88Entry? edit, {
    DateTime? day,
  }) async {
    final r = await showModalBottomSheet<_Result>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: _Form(edit: edit, day: day ?? ref.read(_dayProvider)),
      ),
    );
    if (r == null) return;
    final repo = ref.read(i88RepositoryProvider);
    if (r.delete) {
      if (!context.mounted) return;
      final ok = await showAppConfirmDialog(
        context,
        title: '刪除這筆？',
        message: '${_signed(edit!.amount)}，刪除後不算進本月。',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await repo.delete(edit.id);
    } else if (edit == null) {
      await repo.add(at: r.at, amount: r.amount, note: r.note);
    } else {
      await repo.update(
        edit.copyWith(at: r.at, amount: r.amount, note: r.note),
      );
    }
    ref.read(dataRevisionProvider.notifier).state++;
    // 記在別的月份時，跳到那個月、那一天，才看得到剛記的。
    if (!r.delete) {
      ref.read(_monthProvider.notifier).state = DateTime(r.at.year, r.at.month);
      ref.read(_dayProvider.notifier).state = DateTime(
        r.at.year,
        r.at.month,
        r.at.day,
      );
    }
    if (context.mounted) {
      showAppNotice(
        context,
        r.delete
            ? '已刪除'
            : edit == null
            ? '已記：${_signed(r.amount)}'
            : '已更新',
      );
    }
  }

  Future<void> _editTarget(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final c = TextEditingController(text: current?.toString() ?? '');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('每月目標'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [const DigitsInputFormatter()],
          decoration: const InputDecoration(
            prefixText: '\$ ',
            hintText: '例如 30000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    await ref.read(i88RepositoryProvider).setTarget(v);
    ref.read(dataRevisionProvider.notifier).state++;
  }
}

class _Result {
  _Result({this.delete = false, DateTime? at, this.amount = 0, this.note = ''})
    : at = at ?? DateTime(2000);

  final bool delete;
  final DateTime at;
  final int amount;
  final String note;
}

class _Form extends StatefulWidget {
  const _Form({required this.edit, required this.day});

  final I88Entry? edit;
  final DateTime day;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late bool _isWin = widget.edit?.isWin ?? true;
  late final _amount = TextEditingController(
    text: widget.edit == null ? '' : '${widget.edit!.amount.abs()}',
  );
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late DateTime _at =
      widget.edit?.at ??
      (_sameDay(widget.day, DateTime.now())
          ? DateTime.now()
          : DateTime(widget.day.year, widget.day.month, widget.day.day, 12));

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = int.tryParse(_amount.text) ?? 0;
    final e = widget.edit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e == null ? '記一筆輸贏' : '編輯',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.ink2,
                tooltip: '關閉',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('贏')),
              ButtonSegment(value: false, label: Text('輸')),
            ],
            selected: {_isWin},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _isWin = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: e == null,
            keyboardType: TextInputType.number,
            inputFormatters: [const DigitsInputFormatter()],
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _isWin ? _win : _lose,
            ),
            decoration: InputDecoration(
              prefixText: _isWin ? '+ \$ ' : '− \$ ',
              hintText: '0',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              // 紀錄只到天，不用時跟分（2026-11-09 使用者）；原本的時分照舊留著只用來排同一天的先後。
              final v = await showDateTimeWheel(context, _at, dateOnly: true);
              if (v != null && mounted) {
                setState(
                  () => _at = DateTime(
                    v.year,
                    v.month,
                    v.day,
                    _at.hour,
                    _at.minute,
                  ),
                );
              }
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text('${_at.year}/${_at.month}/${_at.day}'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: '備註（選填）'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (e != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, _Result(delete: true)),
                    style: OutlinedButton.styleFrom(foregroundColor: _lose),
                    child: const Text('刪除'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: v <= 0
                      ? null
                      : () => Navigator.pop(
                          context,
                          _Result(
                            at: _at,
                            amount: _isWin ? v : -v,
                            note: _note.text.trim(),
                          ),
                        ),
                  child: Text(e == null ? '記下來' : '儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
