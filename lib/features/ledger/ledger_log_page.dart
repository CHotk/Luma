import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/ledger.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'ledger_ui.dart';

/// 記帳的操作紀錄（2026-11-03 使用者：每個動作都存一份 log，只會變大、不會被刪）。
/// 新的在前、依日期分隔；可以搜尋（每個欄位）。畫面上不提供任何刪除。
final ledgerLogProvider = FutureProvider.autoDispose<List<LedgerLogEntry>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  return ref.read(ledgerRepositoryProvider).loadLog();
});

class LedgerLogPage extends ConsumerStatefulWidget {
  const LedgerLogPage({super.key});

  @override
  ConsumerState<LedgerLogPage> createState() => _LedgerLogPageState();
}

class _LedgerLogPageState extends ConsumerState<LedgerLogPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _match(LedgerLogEntry e, String q) {
    final hay = [
      e.action,
      e.summary,
      e.detail,
      e.device,
      '${e.at.month}/${e.at.day}',
      '${e.at.year}/${e.at.month.toString().padLeft(2, '0')}/${e.at.day.toString().padLeft(2, '0')}',
    ].join('\n').toLowerCase();
    return q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ledgerLogProvider).valueOrNull;
    final q = _q.text.trim();
    final shown = all == null
        ? const <LedgerLogEntry>[]
        : [
            for (final e in all)
              if (q.isEmpty || _match(e, q)) e,
          ];
    return Scaffold(
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
                  title: '記帳操作紀錄',
                  titleIcon: Icons.history_rounded,
                  titleIconColor: ledgerAccent,
                  showSettings: false,
                ),
                const SizedBox(height: Gap.sm),
                TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '搜尋操作紀錄',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜尋',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(_q.clear),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    all == null
                        ? ''
                        : '共 ${all.length} 筆${q.isEmpty ? '' : '，符合 ${shown.length} 筆'}・只增不刪、會同步到雲端',
                    style: AppText.note.copyWith(color: AppColors.ink3),
                  ),
                ),
                Expanded(
                  child: all == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : shown.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty ? '還沒有操作紀錄' : '沒有符合的紀錄',
                            style: AppText.bodyDim,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: _items(shown),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _items(List<LedgerLogEntry> list) {
    final out = <Widget>[];
    DateTime? cur;
    for (final e in list) {
      if (cur == null || !lSameDay(cur, e.at)) {
        final first = cur == null;
        cur = e.at;
        out.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, first ? 8 : 18, 4, 8),
            child: Row(
              children: [
                Text(
                  lMdw(e.at),
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
              ],
            ),
          ),
        );
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LedgerPill(e.action, color: _color(e.action)),
                    const SizedBox(width: 8),
                    Text(
                      '${lHm(e.at)}:${e.at.second.toString().padLeft(2, '0')}',
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                    const Spacer(),
                    if (e.device.isNotEmpty)
                      Flexible(
                        child: Text(
                          e.device,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.note.copyWith(
                            fontSize: 10,
                            color: AppColors.ink3,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  e.summary,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (e.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.detail, style: AppText.note.copyWith(height: 1.55)),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  Color _color(String action) {
    if (action.contains('刪除') || action.contains('清掉')) return ledgerBad;
    if (action.contains('編輯') || action.contains('改')) return AppColors.mid;
    if (action.contains('對帳') || action.contains('餘額')) {
      return const Color(0xFF7EA6FF);
    }
    return ledgerAccent;
  }
}
