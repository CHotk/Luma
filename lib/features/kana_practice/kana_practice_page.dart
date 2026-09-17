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
/// （使用者 2026-09-17 決定）：**畫完一筆（放手）就存一次**，同一個字
/// 只要沒換行／換字／切模式，一路都是同一筆紀錄被整版換掉（見
/// [KanaPracticeRepository.upsert]）——不是等「離開這個字」才補存一次
/// 整份。這樣存檔時機只有一個地方要管，不用在換行／換字／切模式／
/// 開紀錄頁／離開頁面各自埋一次「記得存」的邏輯，也不怕中途漏存
/// （2026-09-17 使用者要求）。存的是每一筆每個點的座標＋時間戳（見
/// [KanaPracticeEntry.strokes]），不是圖片——這樣重播時筆畫之間停頓
/// 多久、每一筆寫多快，都跟實際寫的時候一致，而且純數字比一張 PNG
/// 小很多，省空間。「輔助描摹」跟「純手寫」是兩種模式：前者背景印著
/// 淡淡的假名當參考線，後者是空白紙，練久了想測自己記不記得筆順就
/// 切過去。
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

  /// 目前這個字存檔用的 id。第一筆落筆時才生出來，之後同一個字每畫完
  /// 一筆都拿同一個 id 去 [KanaPracticeRepository.upsert]，換字／清除
  /// 才會歸零、換一個新的——這樣「同一個字」跟「存檔的哪一筆」是綁在
  /// 一起的，不用另外決定「什麼時候該存」。
  String? _entryId;

  /// 上一次 [_saveStroke] 觸發的寫入，還沒完成的話留著給
  /// [_openHistory] 之類真的要確保寫完才能做下一步的地方等。
  Future<void>? _pendingSave;

  late KanaScript _script = widget.initial?.script ?? KanaScript.hiragana;
  late String _row = widget.initial?.row ?? 'あ';
  late (String, String) _selected =
      widget.initial?.kana ?? rowsFor(_script)[_row]!.first;
  bool _assisted = true;

  /// 一筆畫完（放手）就存一次，不等使用者換字／離開頁面才補存
  /// （2026-09-17 使用者要求，見這個 State 開頭的說明）。
  void _saveStroke() {
    if (_strokes.isEmpty || _entryId == null) return;
    final repo = ref.read(kanaPracticeRepositoryProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    _pendingSave = repo.upsert(_buildEntry()).then((_) => revision.state++);
  }

  KanaPracticeEntry _buildEntry() => KanaPracticeEntry(
    id: _entryId!,
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

  /// 換到下一個字／收掉目前這個字的本地畫布狀態。已經存過的紀錄留著
  /// 不動——這只是清畫布，不是「丟掉這次練習」，那是 [_discard] 的事。
  void _clearInk() {
    _strokes.clear();
    _strokeTimes.clear();
    _sessionStart = null;
    _entryId = null;
  }

  /// 「清除重寫」：跟換字不一樣，這是使用者主動說這次嘗試不算，連
  /// 已經存過的幾版也要一起丟掉，不能留著半成品紀錄。
  Future<void> _discard() async {
    final id = _entryId;
    setState(_clearInk);
    if (id == null) return;
    final repo = ref.read(kanaPracticeRepositoryProvider);
    await repo.delete(id);
    ref.read(dataRevisionProvider.notifier).state++;
  }

  double _elapsedMs() =>
      DateTime.now().difference(_sessionStart!).inMicroseconds / 1000;

  void _pickScript(KanaScript script) {
    if (script == _script) return;
    setState(() {
      _script = script;
      _row = rowsFor(script).keys.first;
      _selected = rowsFor(script)[_row]!.first;
      _clearInk();
    });
  }

  void _pickRow(String row) {
    setState(() {
      _row = row;
      _selected = rowsFor(_script)[row]!.first;
      _clearInk();
    });
  }

  void _pickKana((String, String) pair) {
    setState(() {
      _selected = pair;
      _clearInk();
    });
  }

  Future<void> _openHistory() async {
    // 每一筆已經在放手那一刻就存過了，這裡只需要確保「最後一筆」的
    // 寫入真的完成，不然練習紀錄頁的初始讀取可能比這次寫入還早跑完，
    // 剛畫的那幾筆就看不到（2026-09-17 使用者回饋：點進練習紀錄，剛練
    // 的那筆沒出現）。
    if (_pendingSave != null) await _pendingSave;
    if (!mounted) return;
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
                              onPressed: _discard,
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
                  // 字級要跟紙的實際大小算，不能寫死：紙（AspectRatio）
                  // 會跟著視窗縮放，固定字級縮到一定程度會比紙還大，
                  // 超出的部分被 Container 的 clipBehavior 裁掉——而
                  // 中日文字型的字框上下留白本來就不對稱，裁完看起來
                  // 就像參考字跑位，其實是裁切不對稱（2026-09-17 使用者
                  // 回饋）。
                  child: Text(
                    _selected.$1,
                    style: TextStyle(
                      fontSize: box.shortestSide * 0.62,
                      height: 1,
                      color: guideColor,
                    ),
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
                  _entryId ??= DateTime.now().microsecondsSinceEpoch.toString();
                  _strokes.add([normalize(e.localPosition)]);
                  _strokeTimes.add([_elapsedMs()]);
                }),
                onPointerMove: (e) => setState(() {
                  _strokes.last.add(normalize(e.localPosition));
                  _strokeTimes.last.add(_elapsedMs());
                }),
                // 放手＝這一筆畫完了，存一次（見這個 State 開頭的說明）。
                onPointerUp: (_) => _saveStroke(),
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

