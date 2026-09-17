import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_practice.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
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

  @override
  void initState() {
    super.initState();
    _future = ref.read(kanaPracticeRepositoryProvider).loadAll();
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
    return Scaffold(
      body: AmbientBackground(
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
                      final entries = [...snap.data!]
                        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
                      if (entries.isEmpty) {
                        return Center(
                          child: Text('還沒有任何練習紀錄', style: AppText.bodyDim),
                        );
                      }
                      return ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Gap.sm),
                        itemBuilder: (_, i) => _EntryCard(entry: entries[i]),
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
              color:
                  (entry.assisted ? AppColors.accentSolid : AppColors.ink3)
                      .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
            child: Text(
              entry.assisted ? '輔助描摹' : '純手寫',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: entry.assisted ? AppColors.accentSolid : AppColors.ink2,
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
          CustomPaint(painter: InkPainter(strokes: _asOffsets(entry.strokes))),
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
    final stamp = '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';

    await FileSaver.instance.saveFile(
      name: '${stamp}_${entry.kana}_${entry.romaji}',
      bytes: bytes,
      ext: 'png',
      mimeType: MimeType.png,
    );
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
