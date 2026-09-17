import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_practice.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import 'gojuon_data.dart';

/// 五十音手寫練習頁。
///
/// 練習紙是真的畫布：手指／滑鼠拖著寫，筆畫即時畫出來。按「儲存這張」
/// 會把整張紙（格線＋輔助字＋墨跡）拍成一張 PNG 存進紀錄，不是只存筆畫
/// 座標——這樣以後回頭看才看得出「當時紙面長怎樣」，不用重新描一次線
/// 才能重播。「輔助描摹」跟「純手寫」是兩種模式：前者背景印著淡淡的
/// 假名當參考線，後者是空白紙，練久了想測自己記不記得筆順就切過去。
///
/// 這頁的顏色是全 App 唯一的例外，沒有全部從 [AppColors] 取：紙本來就
/// 該是亮色，跟其餘畫面統一的暗色玻璃底不是同一件事，硬套 AppColors
/// 會讓墨跡完全看不清楚，道理跟 [MiniFlag] 不用 AppColors 畫國旗一樣。
class KanaPracticePage extends ConsumerStatefulWidget {
  const KanaPracticePage({super.key});

  @override
  ConsumerState<KanaPracticePage> createState() => _KanaPracticePageState();
}

class _KanaPracticePageState extends ConsumerState<KanaPracticePage> {
  static const _paper = Color(0xFFF7ECEC);
  static const _paperLine = Color(0x382A1420);
  static const _ink = Color(0xFF2A1420);
  static const _guide = Color(0x292A1420);

  final _paperKey = GlobalKey();
  final _strokes = <List<Offset>>[];

  String _row = 'あ';
  (String, String) _selected = gojuonRows['あ']!.first;
  bool _assisted = true;
  bool _saving = false;

  void _pickRow(String row) {
    setState(() {
      _row = row;
      _selected = gojuonRows[row]!.first;
      _strokes.clear();
    });
  }

  void _pickKana((String, String) pair) {
    setState(() {
      _selected = pair;
      _strokes.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _paperKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final entry = KanaPracticeEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kana: _selected.$1,
        romaji: _selected.$2,
        assisted: _assisted,
        savedAt: DateTime.now(),
        imageBase64: base64Encode(bytes!.buffer.asUint8List()),
      );
      await ref.read(kanaPracticeRepositoryProvider).add(entry);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已存檔：${entry.kana}（${entry.romaji}）')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                    const Text('五十音・手寫練習', style: AppText.title),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          context.push('/kana-practice/history'),
                      icon: const Icon(Icons.history, size: 20),
                      color: AppColors.ink2,
                      tooltip: '練習紀錄',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PanelLabel('選一行'),
                      const SizedBox(height: Gap.sm),
                      _RowTabs(active: _row, onPick: _pickRow),
                      const SizedBox(height: Gap.md),
                      _KanaGrid(
                        row: _row,
                        selected: _selected,
                        onPick: _pickKana,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                // 這張卡不放進 SingleChildScrollView：畫布要接原始拖曳
                // 事件，跟捲動手勢放在同一顆可捲動祖先底下容易搶手勢，
                // 乾脆整頁用固定版面，跟 home_page/quiz_page 同一套做法。
                Expanded(
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ModeToggle(
                          assisted: _assisted,
                          onChanged: (v) => setState(() {
                            _assisted = v;
                            _strokes.clear();
                          }),
                        ),
                        const SizedBox(height: Gap.md),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: _buildPaper(),
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.md),
                        Row(
                          children: [
                            Text(
                              _selected.$1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: Gap.xs),
                            Text(
                              _selected.$2,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.ink3,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => setState(_strokes.clear),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('清除重寫'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                GlassButton(
                  label: _saving ? '存檔中…' : '儲存這張',
                  onPressed: _saving ? () {} : _save,
                ),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaper() {
    return RepaintBoundary(
      key: _paperKey,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: const _GridPainter(color: _paperLine)),
            if (_assisted)
              Center(
                child: Text(
                  _selected.$1,
                  style: const TextStyle(fontSize: 130, color: _guide),
                ),
              ),
            // 用 Listener 接原始指標事件，不用 GestureDetector 的
            // onPan*：這頁外層包著 SingleChildScrollView，兩邊都想要
            // 垂直拖曳的話會搶手勢競技場，畫直筆畫時可能反而變成在
            // 捲頁面。Listener 不進競技場，畫布裡的每一筆一定畫得到。
            Listener(
              onPointerDown: (e) => setState(() {
                _strokes.add([e.localPosition]);
              }),
              onPointerMove: (e) => setState(() {
                _strokes.last.add(e.localPosition);
              }),
              child: CustomPaint(
                painter: _InkPainter(strokes: _strokes, color: _ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTabs extends StatelessWidget {
  const _RowTabs({required this.active, required this.onPick});

  final String active;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: gojuonRows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final row = gojuonRows.keys.elementAt(i);
          return _Chip(
            label: row,
            selected: row == active,
            onTap: () => onPick(row),
          );
        },
      ),
    );
  }
}

class _KanaGrid extends StatelessWidget {
  const _KanaGrid({
    required this.row,
    required this.selected,
    required this.onPick,
  });

  final String row;
  final (String, String) selected;
  final ValueChanged<(String, String)> onPick;

  @override
  Widget build(BuildContext context) {
    final chars = gojuonRows[row]!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final pair in chars)
          _Chip(
            label: pair.$1,
            selected: pair == selected,
            onTap: () => onPick(pair),
            width: 40,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 34,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: width,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSolid.withValues(alpha: 0.28)
              : AppColors.glassFill,
          border: Border.all(
            color: selected
                ? AppColors.accentSolid.withValues(alpha: 0.6)
                : AppColors.glassEdge,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.assisted, required this.onChanged});

  final bool assisted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('輔助描摹')),
        ButtonSegment(value: false, label: Text('純手寫')),
      ],
      selected: {assisted},
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.glassFill,
        foregroundColor: AppColors.ink2,
        selectedBackgroundColor: AppColors.accentSolid.withValues(alpha: 0.28),
        selectedForegroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.glassEdge),
      ),
    );
  }
}

/// 仿「原稿用紙」的十字參考線，不是真的稿紙格，練字夠用。
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final padX = size.width * 0.08;
    final padY = size.height * 0.08;
    _dashed(
      canvas,
      Offset(size.width / 2, padY),
      Offset(size.width / 2, size.height - padY),
      paint,
    );
    _dashed(
      canvas,
      Offset(padX, size.height / 2),
      Offset(size.width - padX, size.height / 2),
      paint,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segEnd = covered + dash > total ? total : covered + dash;
      canvas.drawLine(a + dir * covered, a + dir * segEnd, paint);
      covered += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// 畫使用者實際寫下的筆畫。每次落筆／放開都會有新資料，簡單起見不比對
/// 內容，一律重畫。
class _InkPainter extends CustomPainter {
  const _InkPainter({required this.strokes, required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.5, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
