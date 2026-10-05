import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/home_card_order_store.dart';
import '../../domain/encouragement.dart';
import '../../domain/time_of_day_label.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/open_settings.dart';
import '../../shared/widgets/sakura_petals.dart';
import '../../shared/widgets/ring_progress.dart';
import '../../shared/widgets/settings_icon.dart';
import '../../shared/widgets/stats_icon.dart';
import '../../shared/widgets/track_switcher.dart';
import '../kana_practice/gojuon_data.dart';
import '../settings/home_card_order_page.dart';
import '../kana_practice/kana_practice_page.dart';
import 'jp_home_controller.dart';

/// 日文軌道的首頁。配色是設計稿定案的「櫻」（見 `design-history/`），
/// 版面骨架照設計稿的三塊卡片：進度環、五十音手寫練習預覽、下一輪
/// 清單——只換 [AmbientBackground] 的底色跟四團模糊色塊，`GlassCard`
/// 本身不用換色，設計稿裡玻璃面板一直是中性的白霧感。
///
/// 進度環跟下一輪清單的數字都是真資料：[jpHomeStateProvider] 用
/// [JpReviewConfig] 那套簡化複習排程，從 [KanaPracticeEntry] 紀錄
/// 算出今天練了幾個字、待複習/新字/已掌握各幾個——不是設計稿裡的
/// 範例數字（使用者 2026-09-17 決定要有這套排程，不然這兩塊只能
/// 編數字，違反這個專案「不顯示假資料」的規矩）。
class JpHomePage extends ConsumerWidget {
  const JpHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jpHomeStateProvider);

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
        // 偶爾飄一片櫻花瓣的特效疊在整頁上面（見 [SakuraPetals]）。
        child: SakuraPetals(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (e, _) =>
                    Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
                data: (state) => _Body(state: state),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 日文首頁有哪些卡片可以排順序，順序就是沒排過時的預設順序。最上面的
/// 時間列跟最下面的「開始這輪」固定，不在這裡面。
const jpHomeCards = <HomeCard>[
  (id: 'calendar', label: '打卡月曆'),
  (id: 'ring', label: '今天進度圈（設定裡打開才顯示）'),
  (id: 'kana', label: '五十音預覽'),
  (id: 'exam', label: '考試入口'),
  (id: 'next', label: '下一輪'),
];

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final JpHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「今天進度」那一圈預設隱藏，設定裡打開才顯示（2026-10-05 使用者要求）。
    final showRing = ref.watch(jpShowProgressRingProvider);
    final target = state.config.dailyKanaTarget;
    final done = state.todayCount >= target;
    final cards = <String, Widget>{
      // 打卡熱度月曆卡片（2026-09-29 使用者要求：日文首頁加一個當月日曆
      // ＋簡單數據看板，一目了然這個月練了幾天）。設計稿見
      // `design-history/日文月曆看板設計/01_打卡熱度月曆(主流)`。
      'calendar': GlassCard(child: _MonthlyCalendarCard(state: state)),
      if (showRing)
        'ring': GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
          child: Column(
            children: [
              RingProgress(
                done: state.todayCount,
                total: target,
                centerLabel: '${state.todayCount}/$target',
                bottomLabel:
                    '${state.todayMinutes} / ${state.config.dailyMinutesTarget} 分',
              ),
              const SizedBox(height: Gap.sm),
              Text(
                done ? '今天的份量做完了' : Encouragement.forDate(DateTime.now()),
                textAlign: TextAlign.center,
                style: AppText.bodyDim,
              ),
            ],
          ),
        ),
      'kana': const GlassCard(child: _KanaPreview()),
      'exam': const GlassCard(child: _ExamEntryCard()),
      'next': GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PanelLabel('下一輪'),
            const SizedBox(height: Gap.sm),
            _Row('待複習', '${state.review.due}'),
            _Row('新字', '${state.review.fresh}'),
            _Row('已掌握', '${state.review.mastered}'),
            _Row('手寫練習', '$target 字'),
          ],
        ),
      ),
    };
    final order = applyHomeCardOrder([
      for (final c in jpHomeCards) c.id,
    ], ref.watch(homeCardOrderProvider('jp')).valueOrNull);

    // 跟英文首頁同一個問題：Column 直接放 Spacer() 沒有滾動能力，螢幕
    // 矮一點就整頁卡死，滾輪／手指滑動都沒反應。用 LayoutBuilder 量出
    // 可用高度，塞得下維持原排版（按鈕釘底部），塞不下就讓
    // SingleChildScrollView 接手滾動。
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.md),
                  _TopBar(now: DateTime.now()),
                  const SizedBox(height: Gap.lg),

                  // 卡片順序使用者可以自己調（2026-10-05，見
                  // [HomeCardOrderPage]），順序照存起來的排；「今天進度」
                  // 那圈設定裡關掉時不在 cards 裡，就跳過。
                  for (final id in order)
                    if (cards[id] case final card?) ...[
                      card,
                      const SizedBox(height: Gap.md),
                    ],

                  const Spacer(),
                  const SizedBox(height: Gap.lg),
                  FilledButton(
                    onPressed: () => context.push('/kana-practice'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.jpAccent,
                      foregroundColor: AppColors.jpAccentInk,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.button),
                      ),
                    ),
                    child: const Text(
                      '開始這輪',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 首頁頂端。左邊週幾＋時間＋時段 emoji，中間是語言軌道切換，右邊只留
/// 對日文軌道真的有意義的入口——英文軌道那幾顆（單字庫／總紀錄／
/// ）指向的都是英文單字資料，搬到這裡點了也是空的或誤導，
/// 所以不放；設定頁是全 App 共用的，留著。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu, size: 20),
          color: AppColors.ink2,
          tooltip: '選單',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          // 跟英文首頁同一個修法，見那邊的說明
          // （2026-09-22 使用者回饋：選單跟右邊的週四太近，空出的空間
          // 跟左邊不對稱）。
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: Gap.sm),
        Text(
          '${weekdayLabel(now)} ${clockLabel(now)} ${periodEmoji(now)}',
          style: AppText.title,
        ),
        const SizedBox(width: Gap.sm),
        const TrackSwitcher(current: LearningTrack.ja),
        const Spacer(),
        // 對應英文軌道首頁的「總紀錄」（bar_chart_rounded → /history），
        // 日文原本只有分開的練習紀錄／考試紀錄，沒有一個總覽的地方
        // （2026-09-21 使用者要求：英文右上角有統計，日文也應該要有）。
        IconButton(
          onPressed: () => context.push('/jp-stats'),
          icon: const StatsIcon(size: 20, color: AppColors.ink2),
          color: AppColors.ink2,
          tooltip: '學習統計',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: () => context.push('/kana-practice/history'),
          icon: const Icon(Icons.history, size: 20),
          color: AppColors.ink2,
          tooltip: '練習紀錄',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: () => openSettings(context),
          icon: const SettingsIcon(size: 20, color: AppColors.ink2),
          color: AppColors.ink2,
          tooltip: '設定',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }
}

/// 五十音手寫練習的預覽：選平／片假名、選行、選字，右側是描摹格的
/// 縮小預覽。行跟字這兩排本身只換預覽（要先選行才看得到裡面有哪些
/// 字，不能一點就跳走），但點下面放大預覽的那一塊（假名方塊＋說明
/// 文字，不是那兩排 chip）會直接帶著目前選的字進真正的練習頁
/// （2026-09-17 使用者回饋：原本整張卡都只是預覽，點了没反應，容易
/// 誤會成壞掉）。
class _KanaPreview extends StatefulWidget {
  const _KanaPreview();

  @override
  State<_KanaPreview> createState() => _KanaPreviewState();
}

class _KanaPreviewState extends State<_KanaPreview> {
  KanaScript _script = KanaScript.hiragana;
  String _row = gojuonRows.keys.first;
  (String, String) _selected = gojuonRows.values.first.first;

  void _pickScript(KanaScript script) {
    if (script == _script) return;
    setState(() {
      // 切平／片假名要留在原本選的那一行、原本選的第幾個字，不能
      // 跳回第一行第一個（2026-09-18 使用者回饋：切了不可以跑掉跑回
      // 第一個）。兩份表行的 key 跟每行字數本來就一一對應（見
      // gojuon_data.dart 的說明），正常不會對不到；但這裡還是分兩層
      // 防禦性處理，不是整包對不到就一起退回第一行第一個——行對不到
      // 才退回第一行，行對得到、只是字的index對不到，只退那一個字，
      // 不連行也一起拖下去（2026-09-18 使用者要求：對不到的那排才回
      // 第一個，對得到的那排要保持對到）。
      final oldList = rowsFor(_script)[_row]!;
      final charIndex = oldList.indexOf(_selected);
      _script = script;
      final newRows = rowsFor(script);
      if (!newRows.containsKey(_row)) {
        _row = newRows.keys.first;
        _selected = newRows[_row]!.first;
        return;
      }
      final newList = newRows[_row]!;
      _selected = charIndex >= 0 && charIndex < newList.length
          ? newList[charIndex]
          : newList.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(_script);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: PanelLabel('五十音・手寫練習')),
            _RowTab(
              label: '平',
              selected: _script == KanaScript.hiragana,
              onTap: () => _pickScript(KanaScript.hiragana),
            ),
            const SizedBox(width: 6),
            _RowTab(
              label: '片',
              selected: _script == KanaScript.katakana,
              onTap: () => _pickScript(KanaScript.katakana),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('先選一行，再選裡面的字', style: AppText.note),
        const SizedBox(height: Gap.sm),
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final row = rows.keys.elementAt(i);
              // 行的 key 是固定用平假名當內部代號（兩份表才對得起來，
              // 見 gojuon_data.dart），但顯示的字要照目前選的字表換
              // ——片假名模式顯示「ア行」，不是「あ行」（2026-09-18
              // 使用者回饋）。
              return _RowTab(
                label: '${rows[row]!.first.$1}行',
                selected: row == _row,
                onTap: () => setState(() {
                  _row = row;
                  _selected = rows[row]!.first;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final pair in rows[_row]!)
              _PreviewChip(
                label: pair.$1,
                selected: pair == _selected,
                onTap: () => setState(() => _selected = pair),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(
            '/kana-practice',
            extra: KanaPracticeInitial(
              script: _script,
              row: _row,
              kana: _selected,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    border: Border.all(color: AppColors.glassEdge),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _selected.$1,
                    style: const TextStyle(
                      fontSize: 42,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected.$2,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('點這裡直接進去寫這個字', style: AppText.note),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 手寫考試的入口卡片。整張卡可點，點進去先到模式選擇頁（50 音／
/// 詞彙），不在首頁先選——首頁只負責「帶你進去」，選什麼題型是那頁
/// 自己的事（2026-09-21 使用者要求：考試入口要做成卡片，不要藏在
/// 右上角圖示按鈕裡，卡片才夠顯眼、夠好點）。
class _ExamEntryCard extends StatelessWidget {
  const _ExamEntryCard();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/kana-exam'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.jpAccent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('📝', style: TextStyle(fontSize: 34)),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: PanelLabel('手寫考試')),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.jpAccent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '不看提示',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.jpAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('50 音、詞彙隨機出題，考完才公布答案', style: AppText.note),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// 行選擇器（あ／か／さ……）。故意用底線膠囊而不是跟字格一樣的方塊
/// 樣式——之前兩排都用 [_PreviewChip] 同一種外觀，使用者分不出哪排是
/// 「選一整行」、哪排是「選行裡面哪個字」（2026-09-17 回饋）。
class _RowTab extends StatelessWidget {
  const _RowTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.jpAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: AppColors.glassEdge),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.jpAccentInk : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.jpAccent.withValues(alpha: 0.28)
              : AppColors.glassFill,
          border: Border.all(
            color: selected
                ? AppColors.jpAccent.withValues(alpha: 0.6)
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.bodyDim),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 打卡熱度月曆（設計稿 01 定案）：這個月的日曆，練過的日子塗色，
/// 底下兩顆數字「連續天數」「本月達成率」——2026-09-29 使用者要求
/// 加在日文首頁最上面，不是取代原本的進度環／五十音預覽／下一輪清單，
/// 那些照舊排在這張卡片下面。
class _MonthlyCalendarCard extends StatefulWidget {
  const _MonthlyCalendarCard({required this.state});

  final JpHomeState state;

  @override
  State<_MonthlyCalendarCard> createState() => _MonthlyCalendarCardState();
}

class _MonthlyCalendarCardState extends State<_MonthlyCalendarCard>
    with SingleTickerProviderStateMixin {
  static const _weekdayLabels = ['日', '一', '二', '三', '四', '五', '六'];

  /// 點某一天的練習摘要最多列幾個假名（2026-09-29 使用者要求設上限）。
  static const _maxKanaShown = 30;

  late DateTime _viewedMonth;

  // ---- 上下滑動切換月份（2026-10-02 使用者要求：月曆往上下滑可以看
  // 其他月份，切換過程要精緻）。跟英文首頁 `home_page.dart` 的
  // `_EnMonthlyCalendarCard` 同一套行為、各自獨立一份 ----
  // 往上滑＝下個月、往下滑＝上個月（跟手機內建日曆同方向）。拖曳中
  // 格子跟著手指走、稍微變淡；放開超過門檻就換月，新月份從滑動方向
  // 滑進來、舊的往反方向滑出去；沒過門檻就彈回原位。已經是最早／最晚
  // 的月份還硬拉，阻力變大（橡皮筋），讓人感覺到「到底了」。

  /// 拖曳中格子目前的垂直位移（px）。
  double _dragDy = 0;

  /// 上一次換月的方向：+1 下個月、-1 上個月，決定進出場往哪邊滑。
  int _direction = 1;

  // 一定要在 initState 建好，不能用 late final 延遲建立：沒拖曳過的話，
  // 第一次碰到它會是離開頁面時的 dispose()，在拆畫面途中才建
  // AnimationController 會直接丟例外（2026-10-02 加這段時，這頁的單元
  // 測試抓到的）。
  late final AnimationController _snapBack;
  double _snapFrom = 0;

  static const _switchThresholdPx = 48.0;
  static const _switchVelocity = 350.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewedMonth = DateTime(now.year, now.month);
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(_onSnapBackTick);
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  /// 能看的範圍跟「選擇月份」選單一致：第一次練習的那個月～這個月。
  DateTime get _earliestMonth {
    final source = widget.state.firstPracticedAt ?? DateTime.now();
    return DateTime(source.year, source.month);
  }

  DateTime get _latestMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  bool get _canGoPrev => _viewedMonth.isAfter(_earliestMonth);
  bool get _canGoNext => _viewedMonth.isBefore(_latestMonth);

  void _goTo(int delta) {
    if (delta < 0 && !_canGoPrev || delta > 0 && !_canGoNext) return;
    _snapBack.stop();
    setState(() {
      _direction = delta;
      _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month + delta);
      _dragDy = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _snapBack.stop();
    final next = _dragDy + d.delta.dy;
    // 往上拉（負）是要去下個月、往下拉（正）是要去上個月；那個方向
    // 已經沒有月份了，位移只吃四分之一，做出橡皮筋的阻力感。
    final blocked = next < 0 && !_canGoNext || next > 0 && !_canGoPrev;
    setState(() => _dragDy += blocked ? d.delta.dy * 0.25 : d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if ((_dragDy < -_switchThresholdPx || v < -_switchVelocity) && _canGoNext) {
      _goTo(1);
    } else if ((_dragDy > _switchThresholdPx || v > _switchVelocity) &&
        _canGoPrev) {
      _goTo(-1);
    } else {
      _snapFrom = _dragDy;
      _snapBack.forward(from: 0);
    }
  }

  void _onSnapBackTick() {
    final t = Curves.easeOutCubic.transform(_snapBack.value);
    setState(() => _dragDy = _snapFrom * (1 - t));
  }

  Widget _navArrow(IconData icon, String tooltip, VoidCallback? onTap) =>
      IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        color: AppColors.ink2,
        disabledColor: AppColors.ink3.withValues(alpha: 0.35),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
      );

  /// 點月份標題開的選單（2026-09-29 使用者要求：不是只能看當月，點了
  /// 要能選別的月）。範圍從第一次練習的那個月列到現在這個月，最新的
  /// 排最上面。
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final earliestSource = widget.state.firstPracticedAt ?? now;
    final earliest = DateTime(earliestSource.year, earliestSource.month);
    final months = <DateTime>[];
    var cursor = DateTime(now.year, now.month);
    while (!cursor.isBefore(earliest)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month - 1);
    }
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('選擇月份', style: TextStyle(color: AppColors.ink)),
        children: [
          for (final m in months)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, m),
              child: Text(
                '${m.year} 年 ${m.month} 月',
                style: TextStyle(
                  fontWeight:
                      m.year == _viewedMonth.year &&
                          m.month == _viewedMonth.month
                      ? FontWeight.w700
                      : FontWeight.normal,
                  color:
                      m.year == _viewedMonth.year &&
                          m.month == _viewedMonth.month
                      ? AppColors.jpAccent
                      : AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked != _viewedMonth) {
      // 從選單跳月份也走同一套進出場動畫，方向依前後判斷。
      _goTo(
        (picked.year - _viewedMonth.year) * 12 +
            picked.month -
            _viewedMonth.month,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final now = DateTime.now();
    final viewed = _viewedMonth;
    final isCurrentMonth = viewed.year == now.year && viewed.month == now.month;
    final daysInMonth = DateTime(viewed.year, viewed.month + 1, 0).day;
    final firstWeekday =
        DateTime(viewed.year, viewed.month).weekday % 7; // 週日=0
    final practiced = {
      for (final d in state.allPracticedDates)
        if (d.year == viewed.year && d.month == viewed.month) d.day,
    };
    final rate = daysInMonth == 0
        ? 0
        : (practiced.length * 100 / daysInMonth).round();
    // 跨年看舊月份時標題帶上年份，不然「12 月」分不出是哪一年。
    final monthLabel = viewed.year == now.year
        ? '${viewed.month} 月練習'
        : '${viewed.year} 年 ${viewed.month} 月練習';
    final monthKey = ValueKey(viewed.year * 12 + viewed.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: _pickMonth,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      monthLabel,
                      key: monthKey,
                      style: AppText.bodyDim,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
            // 上下箭頭：滑動之外的明確入口（電腦用滑鼠、或不知道可以
            // 滑的人）。往上＝較早的月份、往下＝較晚的，跟滑動方向一致。
            _navArrow(
              Icons.keyboard_arrow_up_rounded,
              '上個月',
              _canGoPrev ? () => _goTo(-1) : null,
            ),
            _navArrow(
              Icons.keyboard_arrow_down_rounded,
              '下個月',
              _canGoNext ? () => _goTo(1) : null,
            ),
            const Spacer(),
            Text(
              '${practiced.length}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.jpAccent,
              ),
            ),
            Text(' / $daysInMonth 天', style: AppText.note),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            for (final w in _weekdayLabels)
              Expanded(
                child: Center(child: Text(w, style: AppText.note)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // 不用 GridView／PageView：這張卡片包在日文首頁最外層的
        // IntrinsicHeight 裡（撐住「按鈕釘底部」那個版面），GridView、
        // PageView 內部是 Viewport，量不出「intrinsic 高度」，會直接丟例外
        // （2026-09-29 加這張卡片時，單元測試才抓到這個問題）。格子用
        // Row／Column 手排 7 欄，換月動畫用 AnimatedSwitcher（底下是
        // Stack）＋AnimatedSize（5 週↔6 週的月份高度不同，平滑過渡不
        // 跳動），都是能量 intrinsic 的純版面元件。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  // 新月份從滑動方向進來、舊月份往反方向出去（舊的動畫
                  // 是倒著播 1→0，所以 begin 就是它最後停的位置）。
                  final incoming = child.key == monthKey;
                  final from = Offset(
                    0,
                    0.28 * _direction * (incoming ? 1 : -1),
                  );
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: from,
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: monthKey,
                  child: Transform.translate(
                    offset: Offset(0, _dragDy),
                    child: Opacity(
                      opacity: 1 - (_dragDy.abs() / 240).clamp(0.0, 0.35),
                      child: _weekGrid(
                        [
                          for (var i = 0; i < firstWeekday; i++) null,
                          for (var d = 1; d <= daysInMonth; d++) d,
                        ],
                        now,
                        practiced,
                        isCurrentMonth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(child: _statPill('🔥 ${state.streakDays}', '連續天數')),
            const SizedBox(width: Gap.sm),
            Expanded(child: _statPill('$rate%', '本月達成率')),
          ],
        ),
        // 「幾號開始學習、已經幾天」改放到「學習統計」那頁
        // （`jp_stats_page.dart`），首頁月曆卡片不重複顯示
        // （2026-09-29 使用者要求）。
      ],
    );
  }

  /// [days] 是這個月的日期，前面補 `null` 代表當月 1 號前的空格。
  Widget _weekGrid(
    List<int?> days,
    DateTime now,
    Set<int> practiced,
    bool isCurrentMonth,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < days.length; i += 7) {
      final week = days.sublist(i, i + 7 > days.length ? days.length : i + 7);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              for (final d in week)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    // 格子矮一點，整張卡高度矮約 1/5（2026-09-29 使用者
                    // 要求）：長寬比從 1（正方形）改成 1.25，高度＝寬度
                    // ÷1.25＝寬度×0.8，只動這裡，不用一個個改邊距。
                    child: AspectRatio(
                      aspectRatio: 1.25,
                      child: d == null
                          ? const SizedBox.shrink()
                          : _dayCell(d, now, practiced, isCurrentMonth),
                    ),
                  ),
                ),
              // 最後一週天數不滿 7 天就補空格，維持格子寬度一致。
              for (var pad = week.length; pad < 7; pad++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _dayCell(
    int day,
    DateTime now,
    Set<int> practiced,
    bool isCurrentMonth,
  ) {
    final done = practiced.contains(day);
    final isToday = isCurrentMonth && day == now.day;
    final date = DateTime(_viewedMonth.year, _viewedMonth.month, day);
    return InkWell(
      // 點某一天要能看到那天的練習資訊，不是只能看塗色（2026-09-29
      // 使用者要求）。
      onTap: () => _showDaySummary(date),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: done
              ? AppColors.jpAccent
              : AppColors.jpAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppColors.jpAccent, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 11,
            fontWeight: done ? FontWeight.w700 : FontWeight.w400,
            color: done ? AppColors.jpAccentInk : AppColors.ink2,
          ),
        ),
      ),
    );
  }

  /// 點某一天彈出的資訊視窗：有練習就顯示筆數、分鐘數跟練過哪些假名
  /// （依練習次數排序），沒練過就老實說沒有紀錄。
  Future<void> _showDaySummary(DateTime date) async {
    final summary = widget.state.daySummaries[date];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text(
          '${date.month} 月 ${date.day} 日',
          style: const TextStyle(color: AppColors.ink),
        ),
        content: summary == null
            ? Text('這天沒有練習紀錄', style: AppText.bodyDim)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summary.count > 0)
                    Text(
                      '練習了 ${summary.count} 筆・共 ${summary.minutes} 分鐘',
                      style: AppText.bodyDim,
                    ),
                  if (summary.examCount > 0)
                    Text(
                      '考試 ${summary.examCount} 題・答對 ${summary.examCorrect} 題',
                      style: AppText.bodyDim,
                    ),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // 最多列這麼多種，練得多的一天不會把清單塞爆
                      // （2026-09-29 使用者要求設上限；本來就已經是依
                      // 「不同假名」歸類、不是每筆練習各佔一個，但還是
                      // 加個保險上限）。
                      for (final k in summary.kana.take(_maxKanaShown))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.jpAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.jpAccent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            k.count > 1
                                ? '${k.kana}（${k.romaji}）×${k.count}'
                                : '${k.kana}（${k.romaji}）',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (summary.kana.length > _maxKanaShown) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      '還有 ${summary.kana.length - _maxKanaShown} 個字沒列出來',
                      style: AppText.note,
                    ),
                  ],
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.jpAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.jpAccent.withValues(alpha: 0.3)),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.jpAccent,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.note),
      ],
    ),
  );
}
