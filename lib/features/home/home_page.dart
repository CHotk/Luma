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
import '../../shared/widgets/ring_progress.dart';
import '../../shared/widgets/settings_icon.dart';
import '../../shared/widgets/stats_icon.dart';
import '../../shared/widgets/track_switcher.dart';
import '../settings/home_card_order_page.dart';
import 'home_controller.dart';

/// 首頁。版型 04 節制版：圓環是主角，其餘都讓路。
///
/// 這個畫面只排版，所有數字都由 [homeStateProvider] 算好送進來。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeStateProvider);

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) =>
                  Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
              data: (s) => _Body(state: s),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutesUsed = state.usage.practiceSeconds ~/ 60;
    final cards = _enCards(state, minutesUsed);
    final order = applyHomeCardOrder([
      for (final c in enHomeCards) c.id,
    ], ref.watch(homeCardOrderProvider('en')).valueOrNull);

    // Column 直接塞 Spacer() 沒有滾動能力：內容剛好塞滿螢幕時看不出來，
    // 一旦螢幕矮一點（或字級調大），滑鼠滾輪／手指上下滑動都不會動，
    // 只會裁切或噴 overflow。這裡用 LayoutBuilder 量出可用高度，內容
    // 塞得下就照原樣把按鈕釘在底部，塞不下就讓 SingleChildScrollView
    // 接手滾動。
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
                  // 週幾／時間用當下的真實時間，不是 state.usage.date——
                  // 後者是「今天這筆用量第一次建立時」的時間戳，同一天內
                  // 重新打開 App 不會更新，拿來顯示時間會是舊的。
                  _TopBar(now: DateTime.now()),
                  const SizedBox(height: Gap.lg),

                  // 卡片順序使用者可以自己調（2026-10-05，見
                  // [HomeCardOrderPage]），順序照存起來的排；卡片本身見
                  // [_enCards]。
                  for (final id in order)
                    if (cards[id] case final card?) ...[
                      card,
                      const SizedBox(height: Gap.md),
                    ],

                  const Spacer(),
                  const SizedBox(height: Gap.lg),
                  _StartButton(state: state),
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

/// 英文首頁有哪些卡片可以排順序，順序就是沒排過時的預設順序。最上面的
/// 時間列跟最下面的開始按鈕固定，不在這裡面。
const enHomeCards = <HomeCard>[
  (id: 'calendar', label: '打卡月曆'),
  (id: 'ring', label: '今天進度'),
  (id: 'next', label: '下一輪'),
];

/// 英文首頁各張卡片本身。
Map<String, Widget> _enCards(HomeState state, int minutesUsed) => {
  // 打卡熱度月曆卡片（2026-09-29 使用者要求：跟日文首頁一樣要有，見
  // `jp_home_page.dart` 的 `_MonthlyCalendarCard`，這裡是英文軌道自己
  // 獨立一份，不共用）。
  'calendar': GlassCard(child: _EnMonthlyCalendarCard(state: state)),
  'ring': GlassCard(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
    child: Column(
      children: [
        RingProgress(
          done: state.usage.roundsDone,
          total: state.rules.roundsPerDay,
          centerLabel: '${state.usage.roundsDone}/${state.rules.roundsPerDay}',
          bottomLabel: '$minutesUsed / ${state.rules.minutesPerDay} 分',
        ),
        const SizedBox(height: Gap.sm),
        Text(
          // 做滿了就講做滿了，其餘時候給一句每天不一樣的話。
          state.limitReached
              ? '今天的份量做完了'
              : Encouragement.forDate(state.usage.date),
          textAlign: TextAlign.center,
          style: AppText.bodyDim,
        ),
      ],
    ),
  ),
  'next': GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PanelLabel('下一輪'),
        const SizedBox(height: Gap.sm),
        _Row('待複習', '${state.rules.pendingPerRound}'),
        _Row('新字', '${state.rules.freshPerRound}'),
        _Row('已掌握', '${state.rules.masteredPerRound}'),

        if (state.rules.effectiveTypeQuestions > 0)
          _Row('要打字的題數', '${state.rules.effectiveTypeQuestions}'),
      ],
    ),
  ),
};

/// 首頁頂端。左邊週幾＋時間＋時段 emoji，中間是語言軌道切換，
/// 右邊功能入口。
///
/// 偽裝模式放在最右邊，因為需要用到的時候通常很急。
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // IconButton 預設的點擊區是 48 見方，四顆排在一起會超出手機寬度，
    // 最右邊那顆就被擠不見。這裡改成 36 並清掉內距。
    final entries = <({IconData icon, String tip, VoidCallback tap})>[
      (
        icon: Icons.tips_and_updates_outlined,
        tip: '用法地雷',
        tap: () => context.push('/notes'),
      ),
      (
        icon: Icons.menu_book_rounded,
        tip: '單字庫',
        tap: () => context.push('/library'),
      ),
    ];
    final trailingEntries = <({IconData icon, String tip, VoidCallback tap})>[
      (
        icon: Icons.terminal_rounded,
        tip: '偽裝模式',
        tap: () {
          // 進偽裝模式前先掀旗標，出題時才知道要強制點選題。
          ref.read(stealthModeProvider.notifier).state = true;
          context.push('/stealth');
        },
      ),
    ];

    return Row(
      children: [
        IconButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu, size: 20),
          color: AppColors.ink2,
          tooltip: '選單',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          // 32 而不是跟其他按鈕一樣的 36——這顆是最左邊，命中框自己的
          // 內距已經佔掉「畫面邊緣→圖示」的視覺間距，框越大，右邊
          // SizedBox 那段「圖示→文字」的間距相對就顯得更擠、跟左邊不
          // 對稱（2026-09-22 使用者回饋：選單跟右邊的週四太近，空出的
          // 空間跟左邊不對稱）。
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: Gap.sm),
        Text(
          '${weekdayLabel(now)} ${clockLabel(now)} ${periodEmoji(now)}',
          style: AppText.title,
        ),
        const SizedBox(width: Gap.sm),
        const TrackSwitcher(current: LearningTrack.en),
        const Spacer(),
        for (final e in entries)
          IconButton(
            onPressed: e.tap,
            icon: Icon(e.icon, size: 20),
            color: AppColors.ink2,
            tooltip: e.tip,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        IconButton(
          onPressed: () => context.push('/history'),
          icon: const StatsIcon(size: 20, color: AppColors.ink2),
          color: AppColors.ink2,
          tooltip: '總紀錄',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        for (final e in trailingEntries)
          IconButton(
            onPressed: e.tap,
            icon: Icon(e.icon, size: 20),
            color: AppColors.ink2,
            tooltip: e.tip,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        IconButton(
          onPressed: () => context.push('/settings'),
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

/// 做滿上限就真的按不下去。這是防放棄機制的核心，不要改成只跳提示。
class _StartButton extends ConsumerWidget {
  const _StartButton({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = state.limitReached;
    return FilledButton(
      onPressed: blocked
          ? null
          : () {
              // 從首頁走一般流程，確保上一次的偽裝旗標不會殘留。
              ref.read(stealthModeProvider.notifier).state = false;
              context.push('/quiz');
            },
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentSolid,
        disabledBackgroundColor: AppColors.glassFill,
        disabledForegroundColor: AppColors.ink3,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
        ),
      ),
      child: Text(
        blocked ? '今天做完了' : '開始這輪',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 英文軌道的打卡熱度月曆卡片，跟 `jp_home_page.dart` 的
/// `_MonthlyCalendarCard` 是同一個概念但各自獨立一份實作（2026-09-29
/// 使用者要求：英文首頁也要有一樣的日期卡片；兩個軌道的資料來源、
/// 主色都不一樣，不共用元件——跟英文/日文其他地方分開兩份的慣例一致）。
class _EnMonthlyCalendarCard extends StatefulWidget {
  const _EnMonthlyCalendarCard({required this.state});

  final HomeState state;

  @override
  State<_EnMonthlyCalendarCard> createState() => _EnMonthlyCalendarCardState();
}

class _EnMonthlyCalendarCardState extends State<_EnMonthlyCalendarCard>
    with SingleTickerProviderStateMixin {
  static const _weekdayLabels = ['日', '一', '二', '三', '四', '五', '六'];

  /// 點某一天的練習摘要最多列幾個單字，超過就截斷＋顯示「還有幾個」
  /// （2026-09-29 使用者要求：練得多的一天不該把清單塞爆）。
  static const _maxWordsShown = 30;

  late DateTime _viewedMonth;

  // ---- 上下滑動切換月份（2026-10-02 使用者要求：月曆往上下滑可以看
  // 其他月份，切換過程要精緻）----
  // 往上滑＝下個月、往下滑＝上個月（跟手機內建日曆同方向：往上推，
  // 底下比較晚的月份冒出來）。拖曳中格子跟著手指走、稍微變淡；放開
  // 超過門檻就換月，新月份從滑動方向滑進來、舊的往反方向滑出去；
  // 沒過門檻就彈回原位。已經是最早／最晚的月份還硬拉，阻力變大
  // （橡皮筋），讓人感覺到「到底了」。

  /// 拖曳中格子目前的垂直位移（px）。
  double _dragDy = 0;

  /// 上一次換月的方向：+1 下個月、-1 上個月，決定進出場往哪邊滑。
  int _direction = 1;

  // 一定要在 initState 建好，不能用 late final 延遲建立：沒拖曳過的話，
  // 第一次碰到它會是離開頁面時的 dispose()，在拆畫面途中才建
  // AnimationController 會直接丟例外（2026-10-02 加這段時，日文首頁的
  // 單元測試抓到的）。
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
                      ? AppColors.accent
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
    final firstWeekday = DateTime(viewed.year, viewed.month).weekday % 7;
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
                color: AppColors.accent,
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
        // 不用 GridView／PageView：這張卡片包在首頁最外層的 IntrinsicHeight
        // 裡（撐住「按鈕釘底部」那個版面），GridView、PageView 內部是
        // Viewport，量不出「intrinsic 高度」，會直接丟例外——跟日文首頁
        // 那張卡片同一個坑（見 `jp_home_page.dart` 的說明）。格子用
        // Row／Column 手排，換月動畫用 AnimatedSwitcher（底下是 Stack）
        // ＋AnimatedSize（5 週↔6 週的月份高度不同，平滑過渡不跳動），
        // 都是能量 intrinsic 的純版面元件。
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
      ],
    );
  }

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
                    child: AspectRatio(
                      aspectRatio: 1.25,
                      child: d == null
                          ? const SizedBox.shrink()
                          : _dayCell(d, now, practiced, isCurrentMonth),
                    ),
                  ),
                ),
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
      onTap: () => _showDaySummary(date),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: done
              ? AppColors.accent
              : AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 11,
            fontWeight: done ? FontWeight.w700 : FontWeight.w400,
            color: done ? AppColors.bgDeep : AppColors.ink2,
          ),
        ),
      ),
    );
  }

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
                  Text(
                    '答了 ${summary.count} 題・共 ${summary.minutes} 分鐘',
                    style: AppText.bodyDim,
                  ),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final w in summary.words.take(_maxWordsShown))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            w.count > 1 ? '${w.word} ×${w.count}' : w.word,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (summary.words.length > _maxWordsShown) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      '還有 ${summary.words.length - _maxWordsShown} 個單字沒列出來',
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
      color: AppColors.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.note),
      ],
    ),
  );
}
