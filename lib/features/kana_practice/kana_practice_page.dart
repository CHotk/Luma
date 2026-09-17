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
import 'kana_paper.dart';

/// 五十音手寫練習頁。
///
/// 練習紙是真的畫布：手指／滑鼠拖著寫，筆畫即時畫出來。按「儲存這張」
/// 會存兩份東西：整張紙（格線＋輔助字＋墨跡）拍成的 PNG，給列表跟
/// 匯入的圖片統一用同一種方式顯示；以及每一筆每個點的座標＋時間戳
/// （見 [KanaPracticeEntry.strokes]），給練習紀錄頁「重播當初怎麼寫的」
/// 用——PNG 是死的看不出筆順跟節奏，要重播動作非得存座標跟時間不可，
/// 位置跟筆畫之間停頓多久都要跟實際寫的時候一致（使用者 2026-09-17
/// 要求），不能用猜的固定配速交差。「輔助描摹」跟「純手寫」是兩種
/// 模式：前者背景印著淡淡的假名當參考線，後者是空白紙，練久了想測
/// 自己記不記得筆順就切過去。
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
  final _paperKey = GlobalKey();
  final _strokes = <List<Offset>>[];

  /// 跟 [_strokes] 同樣結構，同一個索引存那個點的毫秒時間戳
  /// （從 [_sessionStart] 算起）。分開放兩個平行陣列，是為了不動
  /// [_strokes] 原本的型別——畫面即時畫筆畫只需要座標，時間只在
  /// 存檔那一刻才用得到。
  final _strokeTimes = <List<double>>[];

  /// 這次寫的第一筆落筆時間。整份紀錄的時間軸從這裡算起，換字／清除
  /// 都要歸零，下一次落筆才會重新設定。
  DateTime? _sessionStart;

  String _row = 'あ';
  (String, String) _selected = gojuonRows['あ']!.first;
  bool _assisted = true;
  bool _saving = false;

  void _clearInk() {
    _strokes.clear();
    _strokeTimes.clear();
    _sessionStart = null;
  }

  double _elapsedMs() =>
      DateTime.now().difference(_sessionStart!).inMicroseconds / 1000;

  void _pickRow(String row) {
    setState(() {
      _row = row;
      _selected = gojuonRows[row]!.first;
      _clearInk();
    });
  }

  void _pickKana((String, String) pair) {
    setState(() {
      _selected = pair;
      _clearInk();
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
        strokes: [
          for (var i = 0; i < _strokes.length; i++)
            [
              for (var j = 0; j < _strokes[i].length; j++)
                (_strokes[i][j].dx, _strokes[i][j].dy, _strokeTimes[i][j]),
            ],
        ],
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
                            _clearInk();
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
                              onPressed: () => setState(_clearInk),
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
          color: paperColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: PaperGridPainter()),
            if (_assisted)
              Center(
                child: Text(
                  _selected.$1,
                  style: const TextStyle(fontSize: 130, color: guideColor),
                ),
              ),
            // 用 Listener 接原始指標事件，不用 GestureDetector 的
            // onPan*：如果這頁以後又包進可捲動的容器，兩邊都想要
            // 垂直拖曳的話會搶手勢競技場，畫直筆畫時可能反而變成在
            // 捲頁面。Listener 不進競技場，畫布裡的每一筆一定畫得到——
            // 這也是這頁目前故意用固定版面、不放 SingleChildScrollView
            // 的原因。
            Listener(
              onPointerDown: (e) => setState(() {
                _sessionStart ??= DateTime.now();
                _strokes.add([e.localPosition]);
                _strokeTimes.add([_elapsedMs()]);
              }),
              onPointerMove: (e) => setState(() {
                _strokes.last.add(e.localPosition);
                _strokeTimes.last.add(_elapsedMs());
              }),
              child: CustomPaint(painter: InkPainter(strokes: _strokes)),
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

