import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../domain/models/tally.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';

/// 簡單記帳（2026-10-19 使用者要求）：跟朋友算錢，一個帳本一個人，只有 ＋／−。
/// 介面刻意陽春；紀錄要專業——每筆留新增／修改時間，所有異動（含匯出圖片）
/// 都進異動紀錄，一筆都不刪。結果匯出成一張圖，直接傳給對方。
const tallyAccent = Color(0xFFFFC857);
const _plusColor = AppColors.ok;
const _minusColor = Color(0xFFFFB066);

String _two(int v) => v.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}';
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String _full(DateTime d) => '${_ymd(d)} ${_hm(d)}:${_two(d.second)}';

/// 結餘的說法。
String tallyStatus(int balance) => '結餘 ${tallySigned(balance)}';

Color _statusColor(int b) => b >= 0 ? AppColors.ok : _minusColor;

Widget _page(
  BuildContext context, {
  required Widget top,
  required List<Widget> children,
  bool drawer = false,
  Widget? bottom,
}) => Scaffold(
  drawer: drawer ? const AppSideDrawer() : null,
  body: AmbientBackground(
    child: SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                top,
                const SizedBox(height: Gap.md),
                Expanded(
                  child: ListView(
                    children: [
                      ...children,
                      SizedBox(
                        height:
                            Gap.lg +
                            FloatingNavInset.of(context) +
                            (bottom == null ? 0 : 92),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 手機為主：主要動作固定在最下面，拇指直接按得到。
          if (bottom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: FloatingNavInset.of(context),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.screenSide,
                      12,
                      Gap.screenSide,
                      14,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x660C0C13),
                      border: Border(
                        top: BorderSide(color: AppColors.glassEdge),
                      ),
                    ),
                    child: bottom,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);

Widget _iconAction(IconData icon, String tip, VoidCallback onTap) => IconButton(
  onPressed: onTap,
  icon: Icon(icon, size: 22),
  color: AppColors.ink2,
  tooltip: tip,
  padding: EdgeInsets.zero,
  visualDensity: VisualDensity.compact,
  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
);

/// 中間的毛玻璃卡片對話框（點外面取消）。
Future<T?> _card<T>(BuildContext context, Widget Function(BuildContext) b) =>
    showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.glassEdge),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xD9262433), Color(0xE6161520)],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  child: b(ctx),
                ),
              ),
            ),
          ),
        ),
      ),
    );

InputDecoration _input(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 16),
  filled: true,
  fillColor: Colors.white.withValues(alpha: 0.07),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: tallyAccent, width: 1.2),
  ),
);

Widget _title(String t) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Text(
    t,
    style: const TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    ),
  ),
);

/// 底部固定列裡的毛玻璃大按鈕（帶顏色的玻璃，不用實心色塊）。
class _GlassAction extends StatelessWidget {
  const _GlassAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: color.withValues(alpha: 0.5)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════ 一個帳本 ═══════════════════════

/// 簡單記帳的入口（2026-10-19 使用者要求：沒有帳本概念，打開就是一本帳）。
/// 這個瀏覽器裡沒有帳就自動建一本（標題固定「簡單記帳」，不能改）。
/// [solo] 是分享給別人的獨立網址 `#/tally-solo`：沒有返回鍵、功能
/// 選單、設定，也看不到任何異動紀錄的痕跡，不會跳到 App 其他功能；資料存在
/// 朋友自己的瀏覽器，記完按匯出 PDF 傳回來。App 內的 `#/tally` 則是從功能
/// 選單進來，多一個異動紀錄入口。
class TallyEntryPage extends ConsumerStatefulWidget {
  const TallyEntryPage({super.key, this.solo = false});

  final bool solo;

  @override
  ConsumerState<TallyEntryPage> createState() => _TallyEntryPageState();
}

class _TallyEntryPageState extends ConsumerState<TallyEntryPage> {
  String? _id;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final repo = ref.read(tallyRepositoryProvider);
    final books = await repo.books();
    final book = books.lastOrNull ?? await repo.addBook('記帳');
    if (mounted) setState(() => _id = book.id);
  }

  @override
  Widget build(BuildContext context) => _id == null
      ? const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        )
      : TallyBookPage(bookId: _id!, solo: widget.solo);
}

class TallyBookPage extends ConsumerStatefulWidget {
  const TallyBookPage({super.key, required this.bookId, this.solo = false});

  final String bookId;

  /// 獨立分享頁：沒有返回、選單、設定、異動紀錄、更多，也看不到任何
  /// 新增／修改時間的痕跡（使用者不想讓朋友知道有紀錄異動）。
  final bool solo;

  @override
  ConsumerState<TallyBookPage> createState() => _TallyBookPageState();
}

class _TallyBookPageState extends ConsumerState<TallyBookPage> {
  TallyBook? _book;
  List<TallyItem> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(tallyRepositoryProvider);
    final b = (await repo.books()).where((x) => x.id == widget.bookId);
    final items = await repo.items(widget.bookId);
    if (mounted) {
      setState(() {
        _book = b.firstOrNull;
        _items = items;
        _loaded = true;
      });
    }
  }

  int get _balance => _items.fold(0, (s, i) => s + i.signed);

  Future<void> _edit({bool plus = true, TallyItem? old}) async {
    final r = await showTallyItemForm(
      context,
      plus: plus,
      old: old,
      solo: widget.solo,
    );
    if (r == null) return;
    final repo = ref.read(tallyRepositoryProvider);
    if (old == null) {
      await repo.addItem(
        bookId: widget.bookId,
        plus: r.plus,
        amount: r.amount,
        note: r.note,
        at: r.at,
      );
    } else {
      await repo.editItem(
        old,
        plus: r.plus,
        amount: r.amount,
        note: r.note,
        at: r.at,
      );
    }
    _load();
  }

  Future<void> _openItem(TallyItem it) async {
    final events =
        (await ref.read(tallyRepositoryProvider).events(widget.bookId))
            .where((e) => e.itemId == it.id)
            .toList();
    if (!mounted) return;
    final c = await _card<String>(
      context,
      (ctx) => _ItemDetail(item: it, events: events, solo: widget.solo),
    );
    if (!mounted) return;
    if (c == 'edit') {
      await _edit(old: it);
    } else if (c == 'delete') {
      final ok = await showAppConfirmDialog(
        context,
        title: '刪除這一筆？',
        message: widget.solo
            ? '${tallyItemLabel(it)}\n刪掉後結餘會重算'
            : '${tallyItemLabel(it)}\n刪掉後結餘會重算；異動紀錄裡會留下這筆的完整內容',
        confirmLabel: '刪除',
      );
      if (!ok) return;
      await ref.read(tallyRepositoryProvider).deleteItem(it);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _book;
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (b == null) {
      return _page(
        context,
        top: const AppTopBar(title: '簡單記帳', showSettings: false),
        children: const [InlineEmptyCard(title: '找不到這個帳本（可能已經刪掉了）')],
      );
    }
    final bal = _balance;
    final plusSum = _items.where((i) => i.plus).fold(0, (s, i) => s + i.amount);
    final minusSum = _items
        .where((i) => !i.plus)
        .fold(0, (s, i) => s + i.amount);
    // 每一筆之後的累計結餘（舊到新算），畫面上新的在上面。
    final running = <String, int>{};
    var acc = 0;
    for (final i in _items) {
      acc += i.signed;
      running[i.id] = acc;
    }
    return _page(
      context,
      top: AppTopBar(
        title: '簡單記帳',
        titleIcon: widget.solo ? null : Icons.receipt_long_rounded,
        titleIconColor: tallyAccent,
        showBack: false,
        showSettings: false,
        // 整個簡單記帳都是獨立功能（2026-10-19 使用者要求）：沒有功能選單、
        // 沒有設定、沒有返回，只能從功能選單點進來。
        standalone: true,
        actions: [
          _iconAction(Icons.ios_share_rounded, '匯出 PDF', () async {
            await showTallyExport(context, ref, b, _items);
          }),
          if (!widget.solo) ...[
            _iconAction(Icons.history_rounded, '異動紀錄', () {
              context.push('/tally/log');
            }),
          ],
        ],
      ),
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '目前結餘',
                style: const TextStyle(fontSize: 15, color: AppColors.ink2),
              ),
              const SizedBox(height: 4),
              Text(
                tallySigned(bal),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: _statusColor(bal),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Stat(
                    label: '收入',
                    value: tallyMoney(plusSum),
                    color: _plusColor,
                  ),
                  _Stat(
                    label: '支出',
                    value: tallyMoney(minusSum),
                    color: _minusColor,
                  ),
                  _Stat(
                    label: '筆數',
                    value: '${_items.length}',
                    color: AppColors.ink,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        if (_items.isEmpty)
          const InlineEmptyCard(
            title: '還沒有記錄',
            message: '有收入按「＋ 收入」，花了錢按「− 支出」',
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '明細・新的在上面・點一筆看詳細',
              style: TextStyle(fontSize: 13.5, color: AppColors.ink2),
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (n, i) in _items.reversed.indexed) ...[
                  if (n > 0)
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.glassEdge,
                    ),
                  _ItemRow(
                    item: i,
                    after: running[i.id]!,
                    onTap: () => _openItem(i),
                    solo: widget.solo,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
      bottom: Row(
        children: [
          Expanded(
            child: _GlassAction(
              icon: Icons.add_rounded,
              label: '收入',
              color: _plusColor,
              onTap: () => _edit(plus: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlassAction(
              icon: Icons.remove_rounded,
              label: '支出',
              color: _minusColor,
              onTap: () => _edit(plus: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.after,
    required this.onTap,
    required this.solo,
  });

  final bool solo;

  final TallyItem item;
  final int after;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = item.plus ? _plusColor : _minusColor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          children: [
            // 日期小方塊：大字日、小字月。
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${item.at.day}',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: c,
                    ),
                  ),
                  Text(
                    '${item.at.month}月',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.note.isEmpty
                        ? (item.plus ? '收入' : '支出')
                        : item.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.edited && !solo
                        ? '✎ 改過・${item.updatedAt.month}/${item.updatedAt.day} ${_hm(item.updatedAt)}'
                        : '${item.plus ? '收入' : '支出'}・${item.at.year}',
                    style: const TextStyle(
                      fontSize: 12.5,
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
                  '${item.plus ? '+' : '−'}${tallyMoney(item.amount)}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '結餘 ${tallySigned(after)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 點一筆：完整資料（含新增、最後修改時間）跟這筆的異動歷史。
class _ItemDetail extends StatelessWidget {
  const _ItemDetail({
    required this.item,
    required this.events,
    required this.solo,
  });

  final bool solo;

  final TallyItem item;
  final List<TallyEvent> events;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              k,
              style: const TextStyle(fontSize: 14.5, color: AppColors.ink3),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('${item.plus ? '＋' : '−'} ${tallyMoney(item.amount)}'),
        row('種類', item.plus ? '＋ 收入' : '− 支出'),
        row('備註', item.note.isEmpty ? '（沒寫）' : item.note),
        row('日期', _ymd(item.at)),
        if (!solo) ...[
          row('新增於', _full(item.createdAt)),
          row('最後修改', item.edited ? _full(item.updatedAt) : '沒改過'),
        ],
        if (!solo && events.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            '這筆的異動',
            style: TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActionTag(e.action),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_full(e.at)}\n${e.text}${e.device.isEmpty ? '' : '\n${e.device}'}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.bad,
                  side: BorderSide(color: AppColors.bad.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text('刪除'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                style: FilledButton.styleFrom(
                  backgroundColor: tallyAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('修改'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 新增／修改一筆的表單。回傳 null 是取消。
Future<({bool plus, int amount, String note, DateTime at})?> showTallyItemForm(
  BuildContext context, {
  bool plus = true,
  TallyItem? old,
  bool solo = false,
}) {
  var p = old?.plus ?? plus;
  var at = old?.at ?? DateTime.now();
  final amountC = TextEditingController(
    text: old == null ? '' : '${old.amount}',
  );
  final noteC = TextEditingController(text: old?.note ?? '');
  return _card(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void save() {
          final a = int.tryParse(amountC.text.trim()) ?? 0;
          if (a <= 0) {
            showAppNotice(ctx, '金額要大於 0', isError: true);
            return;
          }
          Navigator.pop(ctx, (
            plus: p,
            amount: a,
            note: noteC.text.trim(),
            at: at,
          ));
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(old == null ? '記一筆' : '修改這一筆'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('＋ 收入')),
                ButtonSegment(value: false, label: Text('− 支出')),
              ],
              selected: {p},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setS(() => p = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: (p ? _plusColor : _minusColor)
                    .withValues(alpha: 0.2),
                selectedForegroundColor: p ? _plusColor : _minusColor,
                foregroundColor: AppColors.ink2,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountC,
              autofocus: old == null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              decoration: _input('金額').copyWith(prefixText: 'NT\$ '),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteC,
              style: const TextStyle(color: AppColors.ink),
              decoration: _input('備註（選填）例如：晚餐、車錢'),
              onSubmitted: (_) => save(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: at,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) {
                  setS(
                    () => at = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      at.hour,
                      at.minute,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('日期：${_ymd(at)}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink2,
                side: const BorderSide(color: AppColors.glassEdge),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
            if (old != null && !solo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '新增於 ${_full(old.createdAt)}'
                  '${old.edited ? '・上次修改 ${_full(old.updatedAt)}' : ''}',
                  style: AppText.note,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: save,
              style: FilledButton.styleFrom(
                backgroundColor: tallyAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                '儲存',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    ),
  );
}

// ═══════════════════════ 匯出 PDF ═══════════════════════

/// 每一頁放幾筆（第一頁有結餘標題，放得少一點）。
const _firstPageRows = 9;
const _otherPageRows = 14;

/// 把每一筆分頁：第一頁 9 筆，之後每頁 14 筆。
List<List<TallyItem>> tallyPages(List<TallyItem> items) {
  final pages = <List<TallyItem>>[];
  var n = 0;
  while (true) {
    final take = pages.isEmpty ? _firstPageRows : _otherPageRows;
    final end = (n + take).clamp(0, items.length);
    pages.add(items.sublist(n, end));
    n = end;
    if (n >= items.length) break;
  }
  return pages;
}

/// 先預覽每一頁，按「存成 PDF」才存（手機叫分享選單、電腦直接下載）。
/// 每一筆都會印出來，筆數多就自動分頁。成功、失敗都記進異動紀錄。
Future<void> showTallyExport(
  BuildContext context,
  WidgetRef ref,
  TallyBook book,
  List<TallyItem> items,
) {
  final now = DateTime.now();
  final bal = items.fold<int>(0, (s, i) => s + i.signed);
  final filename =
      '簡單記帳_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.pdf';
  final pages = tallyPages(items);
  final keys = [for (final _ in pages) GlobalKey()];
  // 每筆之後的累計結餘（舊到新）。
  final running = <String, int>{};
  var acc = 0;
  for (final i in items) {
    acc += i.signed;
    running[i.id] = acc;
  }
  var busy = false;
  return _card<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('匯出 PDF'),
          Text(
            '共 ${items.length} 筆・${pages.length} 頁',
            style: const TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (n, p) in pages.indexed) ...[
                    if (n > 0) const SizedBox(height: 12),
                    RepaintBoundary(
                      key: keys[n],
                      child: TallyReceipt(
                        items: p,
                        running: running,
                        balance: bal,
                        at: now,
                        page: n + 1,
                        pageCount: pages.length,
                        total: items.length,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    setS(() => busy = true);
                    final repo = ref.read(tallyRepositoryProvider);
                    try {
                      final doc = pw.Document();
                      for (final k in keys) {
                        final boundary =
                            k.currentContext!.findRenderObject()!
                                as RenderRepaintBoundary;
                        final img = await boundary.toImage(pixelRatio: 3);
                        final data = await img.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        final image = pw.MemoryImage(
                          data!.buffer.asUint8List(),
                        );
                        doc.addPage(
                          pw.Page(
                            pageFormat: PdfPageFormat.a4,
                            margin: pw.EdgeInsets.zero,
                            build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
                          ),
                        );
                      }
                      final bytes = await doc.save();
                      final ok = await shareOrSaveFile(
                        filename,
                        bytes,
                        'application/pdf',
                      );
                      await repo.logExport(
                        book.id,
                        filename: filename,
                        itemCount: items.length,
                        balance: bal,
                        ok: ok,
                        pages: pages.length,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showAppNotice(
                          context,
                          ok ? '📄 已存成 PDF' : '這個裝置還不能存檔',
                          isError: !ok,
                        );
                      }
                    } catch (e) {
                      await repo.logExport(
                        book.id,
                        filename: filename,
                        itemCount: items.length,
                        balance: bal,
                        ok: false,
                        pages: pages.length,
                        error: '$e',
                      );
                      if (ctx.mounted) {
                        setS(() => busy = false);
                        showAppNotice(ctx, '存 PDF 失敗：$e', isError: true);
                      }
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: Text(busy ? '處理中…' : '存成 PDF'),
            style: FilledButton.styleFrom(
              backgroundColor: tallyAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    ),
  );
}

/// PDF 的其中一頁（A4 比例的白底頁）：第一頁最上面是結餘，每頁列出那一頁的
/// 每一筆（日期、內容、金額、當時結餘），最後一行頁碼。
class TallyReceipt extends StatelessWidget {
  const TallyReceipt({
    super.key,
    required this.items,
    required this.running,
    required this.balance,
    required this.at,
    required this.page,
    required this.pageCount,
    required this.total,
  });

  final List<TallyItem> items;
  final Map<String, int> running;
  final int balance;
  final DateTime at;
  final int page;
  final int pageCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1E1E28), dim = Color(0xFF7A7A88);
    const plus = Color(0xFF2B8A3E), minus = Color(0xFFD9480F);
    return AspectRatio(
      aspectRatio: 210 / 297,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        color: const Color(0xFFFFFDF6),
        child: DefaultTextStyle(
          style: const TextStyle(color: ink, fontSize: 13.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page == 1) ...[
                const Text(
                  '簡單記帳',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  '目前結餘',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: dim, fontSize: 12),
                ),
                Text(
                  tallyMoney(balance),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: balance >= 0 ? plus : minus,
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '簡單記帳（續）',
                    style: TextStyle(color: dim, fontSize: 12),
                  ),
                ),
              const Divider(height: 1, color: Color(0xFFE5E1D5)),
              const SizedBox(height: 4),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '沒有記錄',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: dim),
                  ),
                ),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 66,
                        child: Text(
                          _ymd(i.at),
                          style: const TextStyle(color: dim, fontSize: 11.5),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          i.note.isEmpty ? (i.plus ? '收入' : '支出') : i.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          '${i.plus ? '+' : '−'}${tallyMoney(i.amount)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: i.plus ? plus : minus,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 66,
                        child: Text(
                          tallySigned(running[i.id] ?? 0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: dim, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              const Divider(height: 1, color: Color(0xFFE5E1D5)),
              const SizedBox(height: 6),
              Text(
                '共 $total 筆・截至 ${_ymd(at)} ${_hm(at)}・第 $page／$pageCount 頁',
                textAlign: TextAlign.center,
                style: const TextStyle(color: dim, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════ 異動紀錄 ═══════════════════════

/// 所有異動（新增／修改／刪除／改名／匯出圖片），一筆都不刪。網址帶
/// `?book=` 就只看那個帳本。點一筆看完整內容（改之前／之後逐欄比對）。
class TallyLogPage extends ConsumerStatefulWidget {
  const TallyLogPage({super.key});

  @override
  ConsumerState<TallyLogPage> createState() => _TallyLogPageState();
}

class _TallyLogPageState extends ConsumerState<TallyLogPage> {
  List<TallyEvent>? _events;
  TallyAction? _action;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final es = await ref.read(tallyRepositoryProvider).events();
    if (mounted) setState(() => _events = es);
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: ChoiceChip(
      label: Text(label),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      selected: on,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: tallyAccent.withValues(alpha: 0.22),
      labelStyle: TextStyle(
        fontSize: 14,
        color: on ? tallyAccent : AppColors.ink2,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = _events;
    final shown = (all ?? const <TallyEvent>[])
        .where((e) => _action == null || e.action == _action)
        .toList();
    final days = <String, List<TallyEvent>>{};
    for (final e in shown) {
      (days[_ymd(e.at)] ??= []).add(e);
    }
    final children = <Widget>[
      for (final MapEntry(key: d, value: es) in days.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            '$d・${es.length} 筆',
            style: const TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final (n, e) in es.indexed) ...[
                if (n > 0)
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.glassEdge,
                  ),
                _EventRow(event: e),
              ],
            ],
          ),
        ),
      ],
    ];
    return _page(
      context,
      top: AppTopBar(
        title: '異動紀錄',
        showSettings: false,
        actions: [
          _iconAction(Icons.download_rounded, '匯出 JSON', () {
            final data = const JsonEncoder.withIndent(
              '  ',
            ).convert([for (final e in shown) e.toJson()]);
            final n = DateTime.now();
            saveTextFile(
              '簡單記帳異動紀錄_${n.year}${_two(n.month)}${_two(n.day)}.json',
              data,
            );
          }),
        ],
      ),
      children: [
        if (all == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else ...[
          Wrap(
            children: [
              _chip(
                '全部動作',
                _action == null,
                () => setState(() => _action = null),
              ),
              for (final a in TallyAction.values.where((a) => a != TallyAction.exportImage))
                if (all.any((e) => e.action == a))
                  _chip(
                    a.label,
                    _action == a,
                    () => setState(() => _action = a),
                  ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '共 ${shown.length} 筆・紀錄一筆都不刪・點一筆看完整內容',
              style: const TextStyle(fontSize: 13, color: AppColors.ink3),
            ),
          ),
          if (shown.isEmpty)
            const InlineEmptyCard(title: '沒有異動紀錄')
          else
            ...children,
        ],
      ],
    );
  }
}

Color _actionColor(TallyAction a) => switch (a) {
  TallyAction.itemCreate || TallyAction.bookCreate => AppColors.ok,
  TallyAction.itemUpdate || TallyAction.bookRename => AppColors.mid,
  TallyAction.itemDelete || TallyAction.bookDelete => AppColors.bad,
  TallyAction.exportImage || TallyAction.exportPdf => AppColors.accent,
};

/// 動作種類的小標籤（新增綠、修改黃、刪除紅、匯出藍）。
class _ActionTag extends StatelessWidget {
  const _ActionTag(this.action);

  final TallyAction action;

  @override
  Widget build(BuildContext context) {
    final c = _actionColor(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        action.label,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final TallyEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final balChanged =
        e.balanceBefore != null &&
        e.balanceAfter != null &&
        e.balanceBefore != e.balanceAfter;
    return InkWell(
      onTap: () => _card<void>(context, (ctx) => _EventDetail(event: e)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ActionTag(e.action),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.bookName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${_hm(e.at)}:${_two(e.at.second)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink3,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.text,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.ink,
                    ),
                  ),
                  if (balChanged || e.device.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (balChanged)
                          '結餘 ${tallySigned(e.balanceBefore!)} → ${tallySigned(e.balanceAfter!)}',
                        if (e.device.isNotEmpty) e.device,
                      ].join('・'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// 一筆異動的完整內容：基本資料＋改之前／之後逐欄比對＋附加資料。
class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event});

  final TallyEvent event;

  static const _fieldNames = {
    'plus': '種類',
    'amount': '金額',
    'note': '備註',
    'at': '日期',
    'name': '名稱',
    'createdAt': '新增於',
    'updatedAt': '修改於',
    'deletedAt': '刪除於',
    'bookId': '帳本編號',
    'id': '編號',
  };

  String _v(String k, Object? v) {
    if (v == null) return '—';
    if (k == 'plus') return v == true ? '＋' : '−';
    if (k == 'amount') return tallyMoney((v as num).toInt());
    if (v is String && (k == 'at' || k.endsWith('At'))) {
      final d = DateTime.tryParse(v);
      if (d != null) return _full(d);
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final e = event;
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              k,
              style: const TextStyle(fontSize: 14, color: AppColors.ink3),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
    final keys = <String>{...?e.before?.keys, ...?e.after?.keys};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(e.action.label),
        kv('時間', _full(e.at)),
        kv('帳本', e.bookName),
        kv('內容', e.text),
        if (e.device.isNotEmpty) kv('裝置', e.device),
        if (e.balanceBefore != null)
          kv(
            '結餘',
            e.balanceBefore == e.balanceAfter
                ? tallySigned(e.balanceBefore!)
                : '${tallySigned(e.balanceBefore!)} → ${tallySigned(e.balanceAfter!)}',
          ),
        kv('紀錄編號', e.id),
        if (e.itemId != null) kv('那一筆', e.itemId!),
        if (keys.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            '改之前 → 改之後',
            style: TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
          const SizedBox(height: 4),
          for (final k in keys)
            if (k != 'id' && k != 'bookId')
              () {
                final b = _v(k, e.before?[k]), a = _v(k, e.after?[k]);
                final changed = e.before != null && b != a;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          _fieldNames[k] ?? k,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.ink3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.before == null
                              ? a
                              : e.after == null
                              ? b
                              : changed
                              ? '$b → $a'
                              : a,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: changed ? AppColors.mid : AppColors.ink,
                            fontWeight: changed
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }(),
        ],
        if (e.extra != null) ...[
          const SizedBox(height: 10),
          const Text(
            '附加資料',
            style: TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
          for (final MapEntry(:key, :value) in e.extra!.entries)
            kv(
              const {
                    'filename': '檔名',
                    'itemCount': '圖上筆數',
                    'ok': '成功',
                    'error': '錯誤',
                  }[key] ??
                  key,
              value is bool ? (value ? '是' : '否') : '$value',
            ),
        ],
      ],
    );
  }
}
