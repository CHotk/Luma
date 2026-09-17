import 'package:flutter/material.dart';
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
/// 練習紙是真的畫布：手指／滑鼠拖著寫，筆畫即時畫出來。**不用手動按存**
/// （使用者 2026-09-17 決定）：換行、換字、切換輔助/純手寫模式、或離開
/// 這頁，只要紙上有墨跡就自動存一筆，不管在 App 還是 Web 上都一樣。
/// 存的是每一筆每個點的座標＋時間戳（見 [KanaPracticeEntry.strokes]），
/// 不是圖片——這樣重播時筆畫之間停頓多久、每一筆寫多快，都跟實際寫
/// 的時候一致，而且純數字比一張 PNG 小很多，省空間（這份紀錄以後會
/// 越存越多，省下來的空間差很多）。「輔助描摹」跟「純手寫」是兩種
/// 模式：前者背景印著淡淡的假名當參考線，後者是空白紙，練久了想測
/// 自己記不記得筆順就切過去。
///
/// 這頁的顏色是全 App 唯一的例外，沒有全部從 [AppColors] 取：紙本來就
/// 該是亮色，跟其餘畫面統一的暗色玻璃底不是同一件事，硬套 AppColors
/// 會讓墨跡完全看不清楚。
class KanaPracticePage extends ConsumerStatefulWidget {
  const KanaPracticePage({super.key, this.initial});

  /// 從日文首頁的預覽卡片點進來時，帶著使用者當下選的行／字直接開始
  /// 寫，不用進來再選一次（2026-09-17 使用者要求：點預覽卡片空白處
  /// 要直接進練習，不是只換預覽畫面）。
  final KanaPracticeInitial? initial;

  @override
  ConsumerState<KanaPracticePage> createState() => _KanaPracticePageState();
}

/// 從首頁預覽帶進來的起始選擇。
class KanaPracticeInitial {
  const KanaPracticeInitial({
    required this.script,
    required this.row,
    required this.kana,
  });

  final KanaScript script;
  final String row;
  final (String, String) kana;
}

class _KanaPracticePageState extends ConsumerState<KanaPracticePage> {
  final _strokes = <List<Offset>>[];

  /// 跟 [_strokes] 同樣結構，同一個索引存那個點的毫秒時間戳
  /// （從 [_sessionStart] 算起）。分開放兩個平行陣列，是為了不動
  /// [_strokes] 原本的型別——畫面即時畫筆畫只需要座標，時間只在
  /// 存檔那一刻才用得到。
  final _strokeTimes = <List<double>>[];

  /// 這次寫的第一筆落筆時間。整份紀錄的時間軸從這裡算起，換字／清除
  /// 都要歸零，下一次落筆才會重新設定。
  DateTime? _sessionStart;

  late KanaScript _script = widget.initial?.script ?? KanaScript.hiragana;
  late String _row = widget.initial?.row ?? 'あ';
  late (String, String) _selected =
      widget.initial?.kana ?? rowsFor(_script)[_row]!.first;
  bool _assisted = true;

  @override
  void dispose() {
    // dispose() 不能 await，所以自動存檔在這裡是點火就走：repository
    // 本身的寫入邏輯跟這個 State 的生命週期無關，就算這個 widget 已經
    // 銷毀，寫入還是會跑完。
    _autoSave();
    super.dispose();
  }

  /// 紙上有墨跡才存，「清除重寫」按下去代表使用者不想留這次的嘗試，
  /// 不能在那裡也偷偷存一筆。
  ///
  /// 存完要 bump `dataRevisionProvider`，日文首頁才會重新算「已存幾筆」
  /// ——先把 repository 跟 notifier 這兩個物件同步抓出來，不要在
  /// `.then()` 裡才去用 `ref`：這個方法在 `dispose()` 裡也會被呼叫，
  /// 寫入完成時這個 State 可能已經銷毀，`ref` 那時候未必還能用，但
  /// 抓出來的物件本身跟這個 State 的生死無關，用起來才安全。
  void _autoSave() {
    if (_strokes.isEmpty) return;
    final repo = ref.read(kanaPracticeRepositoryProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    repo.add(_buildEntry()).then((_) => revision.state++);
  }

  KanaPracticeEntry _buildEntry() => KanaPracticeEntry(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    kana: _selected.$1,
    romaji: _selected.$2,
    assisted: _assisted,
    savedAt: DateTime.now(),
    imageBase64: null,
    strokes: [
      for (var i = 0; i < _strokes.length; i++)
        [
          for (var j = 0; j < _strokes[i].length; j++)
            (_strokes[i][j].dx, _strokes[i][j].dy, _strokeTimes[i][j]),
        ],
    ],
  );

  void _clearInk() {
    _strokes.clear();
    _strokeTimes.clear();
    _sessionStart = null;
  }

  double _elapsedMs() =>
      DateTime.now().difference(_sessionStart!).inMicroseconds / 1000;

  void _pickScript(KanaScript script) {
    if (script == _script) return;
    _autoSave();
    setState(() {
      _script = script;
      _row = rowsFor(script).keys.first;
      _selected = rowsFor(script)[_row]!.first;
      _clearInk();
    });
  }

  void _pickRow(String row) {
    _autoSave();
    setState(() {
      _row = row;
      _selected = rowsFor(_script)[row]!.first;
      _clearInk();
    });
  }

  void _pickKana((String, String) pair) {
    _autoSave();
    setState(() {
      _selected = pair;
      _clearInk();
    });
  }

  Future<void> _openHistory() async {
    // push 不會 dispose 這一頁，dispose() 那邊的自動存檔救不到這個情境，
    // 要在離開前自己補存一次。
    _autoSave();
    await context.push('/kana-practice/history');
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
                      onPressed: _openHistory,
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
                      _ScriptToggle(script: _script, onChanged: _pickScript),
                      const SizedBox(height: Gap.md),
                      const PanelLabel('選一行'),
                      const SizedBox(height: Gap.sm),
                      _RowTabs(
                        rows: rowsFor(_script),
                        active: _row,
                        onPick: _pickRow,
                      ),
                      const SizedBox(height: Gap.md),
                      _KanaGrid(
                        rows: rowsFor(_script),
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
                          onChanged: (v) {
                            _autoSave();
                            setState(() {
                              _assisted = v;
                              _clearInk();
                            });
                          },
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
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaper() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: paperColor,
        borderRadius: BorderRadius.circular(14),
      ),
      // LayoutBuilder 拿到紙的實際大小，落筆座標才能除回 0~1 存成
      // 正規化座標——紙在手機上跟桌面上大小不一樣，不正規化的話存下來
      // 的座標範圍會不一樣，重播/匯出到別的尺寸就會跑位或縮成一角。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          Offset normalize(Offset local) =>
              Offset(local.dx / box.width, local.dy / box.height);

          return Stack(
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
              // 捲頁面。Listener 不進競技場，畫布裡的每一筆一定畫得到
              // ——這也是這頁目前故意用固定版面、不放
              // SingleChildScrollView 的原因。
              Listener(
                onPointerDown: (e) => setState(() {
                  _sessionStart ??= DateTime.now();
                  _strokes.add([normalize(e.localPosition)]);
                  _strokeTimes.add([_elapsedMs()]);
                }),
                onPointerMove: (e) => setState(() {
                  _strokes.last.add(normalize(e.localPosition));
                  _strokeTimes.last.add(_elapsedMs());
                }),
                child: CustomPaint(painter: InkPainter(strokes: _strokes)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScriptToggle extends StatelessWidget {
  const _ScriptToggle({required this.script, required this.onChanged});

  final KanaScript script;
  final ValueChanged<KanaScript> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<KanaScript>(
      segments: const [
        ButtonSegment(value: KanaScript.hiragana, label: Text('平假名')),
        ButtonSegment(value: KanaScript.katakana, label: Text('片假名')),
      ],
      selected: {script},
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

class _RowTabs extends StatelessWidget {
  const _RowTabs({required this.rows, required this.active, required this.onPick});

  final Map<String, List<(String, String)>> rows;
  final String active;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final row = rows.keys.elementAt(i);
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
    required this.rows,
    required this.row,
    required this.selected,
    required this.onPick,
  });

  final Map<String, List<(String, String)>> rows;
  final String row;
  final (String, String) selected;
  final ValueChanged<(String, String)> onPick;

  @override
  Widget build(BuildContext context) {
    final chars = rows[row]!;
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

