import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/i88.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

const _accent = Color(0xFFE08F5F);

/// i88 的操作紀錄（2026-11-04 使用者：每個動作都存一份 log，只會變大、不會被刪）。
/// 新的在前、依日期分隔；可以搜尋（每個欄位）。畫面上不提供任何刪除。
final i88LogProvider = FutureProvider.autoDispose<List<I88LogEntry>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  return ref.read(i88RepositoryProvider).loadLog();
});

class I88LogPage extends ConsumerStatefulWidget {
  const I88LogPage({super.key});

  @override
  ConsumerState<I88LogPage> createState() => _I88LogPageState();
}

class _I88LogPageState extends ConsumerState<I88LogPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  bool _match(I88LogEntry e, String q) {
    final hay = [
      e.action,
      e.summary,
      e.detail,
      e.device,
      '${e.at.month}/${e.at.day}',
      '${e.at.year}/${_two(e.at.month)}/${_two(e.at.day)}',
    ].join('\n').toLowerCase();
    return q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(i88LogProvider).valueOrNull;
    final q = _q.text.trim();
    final shown = all == null
        ? const <I88LogEntry>[]
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
                  title: 'i88 操作紀錄',
                  titleIcon: Icons.history_rounded,
                  titleIconColor: _accent,
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

  static const _wd = ['一', '二', '三', '四', '五', '六', '日'];

  List<Widget> _items(List<I88LogEntry> list) {
    final out = <Widget>[];
    DateTime? cur;
    for (final e in list) {
      if (cur == null ||
          cur.year != e.at.year ||
          cur.month != e.at.month ||
          cur.day != e.at.day) {
        final first = cur == null;
        cur = e.at;
        out.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, first ? 8 : 18, 4, 8),
            child: Row(
              children: [
                Text(
                  '${e.at.month}/${e.at.day}（${_wd[e.at.weekday - 1]}）',
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
      final c = _color(e.action);
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.action,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: c,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_two(e.at.hour)}:${_two(e.at.minute)}:${_two(e.at.second)}',
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
    if (action.contains('刪除')) return AppColors.bad;
    if (action.contains('編輯') || action.contains('改')) return AppColors.mid;
    return _accent;
  }
}
