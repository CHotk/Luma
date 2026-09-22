import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/repositories/kana_practice_repository.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../data/seed/kana_practice_seed_loader.dart';
import '../../domain/models/kana_practice.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import 'gojuon_data.dart';
import 'kana_paper.dart';

/// 五十音手寫練習的歷史紀錄。
///
/// 兩種來源都會出現在這裡：練習頁現寫、離開時自動存的，跟這裡右上角
/// 「匯入既有圖片」手動挑檔案存的（例如在這個功能做出來之前，已經用
/// 別的方式寫、存在別的地方的練習圖）。兩種存法最後都是同一筆
/// [KanaPracticeEntry]，畫面上分不出差別，也不需要分——差別只在前者
/// 沒有 `imageBase64`（靠 [KanaPracticeEntry.strokes] 現畫），後者
/// 沒有 `strokes`（外部圖片沒有筆畫過程）。
///
/// 點一筆紀錄可以重播（有 `strokes` 才有得播），也可以匯出成真正的
/// 檔案——用 `file_saver`，Web 上是觸發瀏覽器下載，App 上是存到裝置，
/// 同一份 API 全平台通用，跟 `image_picker` 選型理由一樣。
class KanaPracticeHistoryPage extends ConsumerStatefulWidget {
  const KanaPracticeHistoryPage({super.key});

  @override
  ConsumerState<KanaPracticeHistoryPage> createState() =>
      _KanaPracticeHistoryPageState();
}

class _KanaPracticeHistoryPageState
    extends ConsumerState<KanaPracticeHistoryPage> {
  late Future<List<KanaPracticeEntry>> _future;

  /// 篩選條件，null 表示「全部」。兩個維度各自獨立，可以同時篩
  /// （2026-09-18 使用者要求：練習紀錄要能篩選標籤、看統計數量）。
  KanaScript? _scriptFilter;
  bool? _assistedFilter;

  /// 這台瀏覽器 localStorage 原本有幾筆、專案內建快照有幾筆——都是
  /// 「合併前」的數字，合併之後兩者的界線就看不出來了，所以要在合併
  /// 前先記下來（2026-09-21 使用者要求：要能分別看到專案內建跟本機
  /// 瀏覽器各自有幾筆）。合併動作只在 initState 做一次，這兩個數字
  /// 也就只在那時候設定一次，之後單純重整（[_reload]）不會再變。
  int? _localCountBeforeMerge;
  int? _seedCount;

  @override
  void initState() {
    super.initState();
    _future = _loadWithSeedMerge();
  }

  /// 打開這頁那一瞬間先把手寫紀錄快照（見 [loadKanaPracticeSeed]）併回
  /// 本機，再讀出來顯示（2026-09-18 使用者要求：觸發點就是打開練習
  /// 紀錄頁的時候）。之後單純重整（[_reload]）不用每次都重新合併——
  /// 快照不會無緣無故變，只有第一次打開這頁才需要做這件事。
  Future<List<KanaPracticeEntry>> _loadWithSeedMerge() async {
    final repo = ref.read(kanaPracticeRepositoryProvider);
    final localBefore = await repo.loadAll();
    final seed = await loadKanaPracticeSeed();
    _localCountBeforeMerge = localBefore.length;
    _seedCount = seed.length;
    if (seed.isNotEmpty) await repo.mergeSeed(seed);
    return repo.loadAll();
  }

  void _reload() {
    setState(() {
      _future = ref.read(kanaPracticeRepositoryProvider).loadAll();
    });
  }

  Future<void> _import() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final result = await showDialog<_ImportResult>(
      context: context,
      builder: (_) => _ImportDialog(bytes: bytes),
    );
    if (result == null) return;

    await ref
        .read(kanaPracticeRepositoryProvider)
        .add(
          KanaPracticeEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            kana: result.kana,
            romaji: result.romaji,
            assisted: result.assisted,
            savedAt: DateTime.now(),
            imageBase64: base64Encode(bytes),
            // 匯入的圖片沒有筆畫過程可言，重播功能會顯示「沒有紀錄」。
            strokes: const [],
          ),
        );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    // 練習頁存檔完會 bump 這個 provider；只在 initState 讀一次的話，
    // 如果這個畫面是被 pop 回來重新看到的舊 instance（不是重新 push
    // 出來的新 instance），initState 不會再跑，畫面就停在舊資料，剛
    // 存的那筆練習紀錄看起來像不見了（2026-09-17 使用者回饋）。
    ref.listen<int>(dataRevisionProvider, (prev, next) {
      if (prev != next) _reload();
    });

    return Scaffold(
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const SizedBox(width: Gap.xs),
                    const Text('手寫練習紀錄', style: AppText.title),
                    const Spacer(),
                    // 手機跟電腦各自練的紀錄存在各自瀏覽器的 localStorage
                    // 裡，不會自動合併，這顆按鈕把整份紀錄（含筆畫座標／
                    // 時間戳）匯出成檔案，讓使用者自己拿去手動合併
                    // （2026-09-18 使用者要求，跟 history_page.dart 的
                    // 匯出紀錄同一個用途，見 [_showExportDialog]）。
                    IconButton(
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出紀錄',
                    ),
                    IconButton(
                      onPressed: _import,
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 20,
                      ),
                      color: AppColors.ink2,
                      tooltip: '匯入既有圖片',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<KanaPracticeEntry>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final all = [...snap.data!]
                        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
                      if (all.isEmpty) {
                        return Center(
                          child: Text('還沒有任何練習紀錄', style: AppText.bodyDim),
                        );
                      }

                      // 標籤上的數量永遠算「全部紀錄」裡各分類有幾筆，
                      // 不是算篩選後還剩幾筆——不然篩下去數字全部變成
                      // 自己那一類的總數，看不出其他分類原本有多少。
                      final hiraganaCount = all
                          .where(
                            (e) => _scriptOf(e.kana) == KanaScript.hiragana,
                          )
                          .length;
                      final katakanaCount = all.length - hiraganaCount;
                      final assistedCount = all.where((e) => e.assisted).length;
                      final rawCount = all.length - assistedCount;

                      final filtered = all.where((e) {
                        if (_scriptFilter != null &&
                            _scriptOf(e.kana) != _scriptFilter) {
                          return false;
                        }
                        if (_assistedFilter != null &&
                            e.assisted != _assistedFilter) {
                          return false;
                        }
                        return true;
                      }).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_localCountBeforeMerge != null &&
                              _seedCount != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _SourceCountChip(
                                    label: '這台瀏覽器',
                                    count: _localCountBeforeMerge!,
                                  ),
                                  _SourceCountChip(
                                    label: '專案內建快照',
                                    count: _seedCount!,
                                  ),
                                  _SourceCountChip(
                                    label: '合併後共',
                                    count: all.length,
                                    emphasize: true,
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              _FilterChip(
                                label: '全部',
                                count: all.length,
                                selected: _scriptFilter == null,
                                onTap: () =>
                                    setState(() => _scriptFilter = null),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '平假名',
                                count: hiraganaCount,
                                selected: _scriptFilter == KanaScript.hiragana,
                                onTap: () => setState(
                                  () => _scriptFilter = KanaScript.hiragana,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '片假名',
                                count: katakanaCount,
                                selected: _scriptFilter == KanaScript.katakana,
                                onTap: () => setState(
                                  () => _scriptFilter = KanaScript.katakana,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.xs),
                          Row(
                            children: [
                              _FilterChip(
                                label: '全部',
                                count: all.length,
                                selected: _assistedFilter == null,
                                onTap: () =>
                                    setState(() => _assistedFilter = null),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '輔助描摹',
                                count: assistedCount,
                                selected: _assistedFilter == true,
                                onTap: () =>
                                    setState(() => _assistedFilter = true),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: '純手寫',
                                count: rawCount,
                                selected: _assistedFilter == false,
                                onTap: () =>
                                    setState(() => _assistedFilter = false),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            '符合條件 ${filtered.length} / ${all.length} 筆',
                            style: AppText.note,
                          ),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      '沒有符合篩選條件的紀錄',
                                      style: AppText.bodyDim,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: Gap.sm),
                                    itemBuilder: (_, i) =>
                                        _EntryCard(entry: filtered[i]),
                                  ),
                          ),
                        ],
                      );
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
}

/// 匯出的範圍：只匯出這台裝置 localStorage 裡的，還是連專案已經
/// 打包好的手寫紀錄快照一起（2026-09-18 使用者要求：哪天真的想把
/// 專案的也一起匯出就也可以）。多數時候兩者是一樣的——練習紀錄頁
/// 打開時就會把快照併進 localStorage（見 [_loadWithSeedMerge]）；
/// 差別只在使用者還沒開過那個合併流程、或快照比 localStorage 新的
/// 情況。
enum _ExportScope { localOnly, withSeed }

/// 跳出匯出對話框，內容是整份 [KanaPracticeEntry] 紀錄的 JSON 陣列。
///
/// 不像 `history_page.dart` 那份用空白分隔欄位的文字格式——這裡的紀錄
/// 有巢狀的筆畫座標／時間戳陣列，有些還帶著匯入圖片的 base64，塞進
/// 那種欄位格式會失真或整行爆長，直接用 JSON 最省事、也保留得住完整
/// 結構。下載走的是同一套 `file_download.dart`（見 `history_page.dart`
/// 的說明），複製到剪貼簿當備用。
Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(kanaPracticeRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final KanaPracticeRepository repo;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  _ExportScope _scope = _ExportScope.localOnly;
  late Future<({String text, int count})> _future;

  @override
  void initState() {
    super.initState();
    _future = _build(_scope);
  }

  Future<({String text, int count})> _build(_ExportScope scope) async {
    if (scope == _ExportScope.localOnly) {
      return widget.repo.exportJson();
    }
    final local = await widget.repo.loadAll();
    final seed = await loadKanaPracticeSeed();
    // 本機為準：本機有的 id 蓋掉快照那份，本機沒有、快照有的才補上
    // ——這裡要的是「補齊這台裝置漏掉、但專案快照裡已經有」的
    // 紀錄，不是拿快照蓋掉這台裝置剛練的東西。
    final byId = {for (final e in seed) e.id: e};
    for (final e in local) {
      byId[e.id] = e;
    }
    final merged = byId.values.toList();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in merged) e.toJson()]),
      count: merged.length,
    );
  }

  void _setScope(_ExportScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _future = _build(scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filename = 'lume-kana-practice-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出手寫練習紀錄',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_ExportScope>(
            segments: const [
              ButtonSegment(
                value: _ExportScope.localOnly,
                label: Text('僅這台裝置'),
              ),
              ButtonSegment(
                value: _ExportScope.withSeed,
                label: Text('連手寫紀錄快照一起'),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => _setScope(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.glassFill,
              foregroundColor: AppColors.ink2,
              selectedBackgroundColor: AppColors.jpAccent.withValues(
                alpha: 0.28,
              ),
              selectedForegroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.glassEdge),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FutureBuilder<({String text, int count})>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.md),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final data = snap.data!;
              final sizeLabel = _formatExportSize(
                utf8.encode(data.text).length,
              );
              return Text(
                '$filename\n共 ${data.count} 筆 ・ 約 $sizeLabel',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
              );
            },
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () async {
            final data = await _future;
            final ok = saveTextFile(filename, data.text);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? '已下載 $filename' : '這個平台還不支援下載，改用複製')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.jpAccent,
            foregroundColor: AppColors.jpAccentInk,
          ),
          child: const Text('下載'),
        ),
        OutlinedButton(
          onPressed: () async {
            final data = await _future;
            await Clipboard.setData(ClipboardData(text: data.text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已複製到剪貼簿')));
          },
          child: const Text('複製'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

String _formatExportSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _exportTodayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}

/// 紀錄本身沒存「這是平假名還是片假名」——不查 gojuon_data.dart 的表
/// （匯入既有圖片時 `kana` 是使用者自己打的文字，不保證剛好對得上表
/// 裡的 92 個字），用 Unicode 分區判斷比較穩：片假名區段是
/// U+30A0–U+30FF，其餘（含平假名 U+3040–309F）都當平假名。
KanaScript _scriptOf(String kana) {
  if (kana.isEmpty) return KanaScript.hiragana;
  final code = kana.codeUnitAt(0);
  return code >= 0x30A0 && code <= 0x30FF
      ? KanaScript.katakana
      : KanaScript.hiragana;
}

/// 篩選用的膠囊按鈕，帶著這個分類目前有幾筆——數量是為了讓使用者
/// 一眼看出「篩下去大概還剩多少」，不用先點下去才知道
/// （2026-09-18 使用者要求：練習紀錄要有篩選標籤、看統計數量）。
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.jpAccent.withValues(alpha: 0.28)
              : AppColors.glassFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.jpAccent.withValues(alpha: 0.6)
                : AppColors.glassEdge,
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// 純顯示用的小標籤，不可點——跟 [_FilterChip] 長得像但語意不同，
/// 這裡是「資料來源各有幾筆」的說明，不是篩選條件（2026-09-21 使用者
/// 要求：要能分別看到專案內建跟本機瀏覽器各自有幾筆）。
class _SourceCountChip extends StatelessWidget {
  const _SourceCountChip({
    required this.label,
    required this.count,
    this.emphasize = false,
  });

  final String label;
  final int count;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasize
            ? AppColors.jpAccent.withValues(alpha: 0.16)
            : AppColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasize
              ? AppColors.jpAccent.withValues(alpha: 0.4)
              : AppColors.glassEdge,
        ),
      ),
      child: Text(
        '$label $count 筆',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: emphasize ? AppColors.jpAccent : AppColors.ink3,
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final KanaPracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _ReplayDialog(entry: entry),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _Thumb(entry: entry),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.kana,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      entry.romaji,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(_formatDate(entry.savedAt), style: AppText.note),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (entry.assisted ? AppColors.jpAccent : AppColors.ink3)
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
            child: Text(
              entry.assisted ? '輔助描摹' : '純手寫',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: entry.assisted ? AppColors.jpAccent : AppColors.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 縮圖：有存圖片（匯入的）就直接顯示；沒有（現寫自動存的）就靠
/// [KanaPracticeEntry.strokes] 現畫——同一份 painter，不用另外存縮圖。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry});

  final KanaPracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final img = entry.imageBase64;
    if (img != null) {
      return Image.memory(
        base64Decode(img),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
      );
    }
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: paperColor),
          const CustomPaint(painter: PaperGridPainter()),
          CustomPaint(
            painter: InkPainter(
              strokes: _asOffsets(entry.strokes),
              strokeWidth: inkStrokeWidth(56),
            ),
          ),
        ],
      ),
    );
  }
}

List<List<Offset>> _asOffsets(List<List<(double, double, double)>> strokes) => [
  for (final stroke in strokes) [for (final p in stroke) Offset(p.$1, p.$2)],
];

/// 點一筆紀錄跳出來的重播對話框。
///
/// 有存筆畫資料（練習頁現寫存的）就照原始順序漸進畫出來；沒有
/// （匯入既有圖片存的）就老實顯示「沒有筆畫紀錄可以重播」，不要假裝
/// 有資料硬播一個看起來像那麼回事的動畫。
class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog({required this.entry});

  final KanaPracticeEntry entry;

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<List<TimedPoint>> _strokes;
  bool _exportingGif = false;

  @override
  void initState() {
    super.initState();
    _strokes = [
      for (final stroke in widget.entry.strokes)
        [for (final p in stroke) (Offset(p.$1, p.$2), p.$3)],
    ];
    final totalMs = ReplayInkPainter.totalDurationMs(_strokes);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs <= 0 ? 1 : totalMs.round()),
    );
    if (_strokes.isNotEmpty) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final entry = widget.entry;
    final img = entry.imageBase64;
    final bytes = img != null
        ? base64Decode(img)
        : await renderStrokesToPng(_asOffsets(entry.strokes));

    final d = entry.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';

    await FileSaver.instance.saveFile(
      name: '${stamp}_${entry.kana}_${entry.romaji}',
      bytes: bytes,
      ext: 'png',
      mimeType: MimeType.png,
    );
  }

  /// 「下載動畫」：把重播（筆畫怎麼畫出來）編成一份動畫 GIF 下載，
  /// 不是只匯出寫完的靜態圖（2026-09-18 使用者要求）。逐格畫、編碼
  /// 都要花時間，按下去到存檔中間有一段等待，用 [_exportingGif] 鎖住
  /// 按鈕、換成轉圈，不然使用者按了沒反應會以為壞掉、重複按好幾次。
  Future<void> _exportGif() async {
    if (_exportingGif) return;
    setState(() => _exportingGif = true);
    try {
      final entry = widget.entry;
      final gifConfig = await loadKanaGifDefaults();
      final bytes = await renderStrokesToGif(
        _strokes,
        size: gifConfig.size,
        maxFrames: gifConfig.maxFrames,
        frameIntervalMs: gifConfig.frameIntervalMs,
        numColors: gifConfig.numColors,
      );
      final d = entry.savedAt;
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';

      await FileSaver.instance.saveFile(
        name: '${stamp}_${entry.kana}_${entry.romaji}',
        bytes: bytes,
        ext: 'gif',
        mimeType: MimeType.gif,
      );
    } finally {
      if (mounted) setState(() => _exportingGif = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final hasStrokes = _strokes.isNotEmpty;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: Text(
        '${entry.kana}（${entry.romaji}）',
        style: const TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: hasStrokes
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: paperColor),
                        const CustomPaint(painter: PaperGridPainter()),
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (_, _) => CustomPaint(
                            painter: ReplayInkPainter(
                              strokes: _strokes,
                              elapsedMs:
                                  _controller.value *
                                  _controller.duration!.inMilliseconds,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: entry.imageBase64 != null
                        ? Image.memory(
                            base64Decode(entry.imageBase64!),
                            fit: BoxFit.contain,
                          )
                        : const ColoredBox(color: paperColor),
                  ),
          ),
          if (!hasStrokes) ...[
            const SizedBox(height: Gap.sm),
            const Text(
              '這張是匯入的圖片，沒有筆畫紀錄可以重播',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (hasStrokes)
          TextButton.icon(
            onPressed: () {
              _controller.reset();
              _controller.forward();
            },
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('重播'),
          ),
        if (hasStrokes)
          TextButton.icon(
            onPressed: _exportingGif ? null : _exportGif,
            icon: _exportingGif
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.gif_box_outlined, size: 16),
            label: Text(_exportingGif ? '編碼中…' : '下載該次筆跡'),
          ),
        TextButton.icon(
          onPressed: _export,
          icon: const Icon(Icons.download_outlined, size: 16),
          label: const Text('匯出圖片'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

class _ImportResult {
  const _ImportResult({
    required this.kana,
    required this.romaji,
    required this.assisted,
  });

  final String kana;
  final String romaji;
  final bool assisted;
}

/// 匯入既有圖片時要補問的中繼資料：圖片本身看不出寫的是哪個假名，
/// 也看不出當時有沒有開輔助描摹，這兩件事只能請使用者自己填。
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _kanaCtrl = TextEditingController();
  final _romajiCtrl = TextEditingController();
  bool _assisted = false;

  @override
  void dispose() {
    _kanaCtrl.dispose();
    _romajiCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final kana = _kanaCtrl.text.trim();
    if (kana.isEmpty) return;
    Navigator.of(context).pop(
      _ImportResult(
        kana: kana,
        romaji: _romajiCtrl.text.trim(),
        assisted: _assisted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text('匯入這張圖片', style: TextStyle(color: AppColors.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(widget.bytes, height: 110, fit: BoxFit.contain),
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _kanaCtrl,
            autofocus: true,
            style: const TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(labelText: '寫的是哪個假名'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _romajiCtrl,
            style: const TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(labelText: '羅馬拼音（可留空）'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              const Text(
                '當時有開輔助描摹嗎',
                style: TextStyle(color: AppColors.ink2, fontSize: 13),
              ),
              const Spacer(),
              Switch(
                value: _assisted,
                onChanged: (v) => setState(() => _assisted = v),
              ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('存進紀錄')),
      ],
    );
  }
}
