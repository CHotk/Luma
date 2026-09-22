import 'dart:convert' show utf8, JsonEncoder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/seed/diary_seed_loader.dart';
import '../../data/seed/seed_merge.dart';
import '../../domain/models/diary_entry.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

/// 打開日記詳情（點某一篇）之後可以選的動作。
enum _EntryAction { edit, delete }

/// 日記功能。走「極簡打卡」路線（設計稿 04），頂部日期跳轉條借設計稿
/// 02 的版面（2026-09-22 使用者拍板：頂部日期用 02 的，其餘照 04）。
///
/// 一天原則上打卡一次：那一天已經記錄過，打卡卡會鎖住，要改就點下面
/// 列表那一則編輯，或刪掉重打，不是無限疊加同一天的紀錄。
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  late Future<List<DiaryEntry>> _future;
  final _textController = TextEditingController();
  String _mood = diaryMoods.first;
  // 天氣現象／冷熱感受選填，預設各自第一個選項——兩個獨立屬性，分開
  // 兩排選（2026-09-22 使用者糾正：陰晴雨／冷熱普通不是同一屬性）。
  String _weather = diaryWeathers.first;
  String _temperature = diaryTemperatures.first;
  // 0 = 今天／1 = 昨天／2 = 前天，補寫之前忘記打卡的日子用
  // （2026-09-22 使用者要求：怕 12 點才寫或忘記寫一天）。
  int _dayOffset = 0;
  // 點頂部日期條選中的那一天，下面「最近」列表還是照樣顯示全部，只是
  // 把這一天的那則特別標起來、捲到看得到的地方方便找，不是把其他都
  // 藏掉（2026-09-22 使用者糾正：原本誤做成過濾掉其他天）。
  DateTime? _selectedDay;
  DateTime? _lastScrolledSelection;
  final _listScrollController = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    _future = _loadWithSeedMerge();
  }

  /// 打開這頁那一瞬間先把日記快照（見 [loadDiarySeed]）併回本機，跟
  /// `kana_practice_history_page.dart` 的 `_loadWithSeedMerge` 同一套。
  Future<List<DiaryEntry>> _loadWithSeedMerge() async {
    final repo = ref.read(diaryRepositoryProvider);
    final seed = await loadDiarySeed();
    if (seed.isNotEmpty) await repo.mergeSeed(seed);
    return repo.loadAll();
  }

  @override
  void dispose() {
    _textController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = ref.read(diaryRepositoryProvider).loadAll();
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = _selectedDay != null && isSameDay(_selectedDay!, day)
          ? null
          : day;
    });
  }

  /// 「最近」列表永遠是全部日記都在（2026-09-22 使用者糾正：點頂部
  /// 日期原本誤做成把其他天都濾掉，其實應該照樣全部顯示，只是把選中
  /// 那天特別標起來、捲到看得到的地方方便找）。[selectedEntry] 非 null
  /// 的話，捲一次讓它進入可視範圍——只在「這次選的天」跟上次捲過的不
  /// 一樣時才捲，不然每次 build 都會被拉走，使用者自己往上滑找別的
  /// 紀錄時會一直被拉回去。
  Widget _buildRecentList(List<DiaryEntry> all, DiaryEntry? selectedEntry) {
    if (selectedEntry != null && _lastScrolledSelection != _selectedDay) {
      _lastScrolledSelection = _selectedDay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _rowKeys[selectedEntry.id]?.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      });
    }
    return ListView.separated(
      controller: _listScrollController,
      itemCount: all.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.glassEdge),
      itemBuilder: (_, i) {
        final entry = all[i];
        final key = _rowKeys.putIfAbsent(entry.id, () => GlobalKey());
        return _SimpleRow(
          key: key,
          entry: entry,
          highlighted: selectedEntry != null && entry.id == selectedEntry.id,
          onTap: () => _showEntry(entry),
        );
      },
    );
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(diaryRepositoryProvider);
    final now = DateTime.now();
    await repo.add(
      DiaryEntry(
        id: now.microsecondsSinceEpoch.toString(),
        mood: _mood,
        text: text,
        weather: _weather,
        temperature: _temperature,
        // 補寫昨天／前天：日期往回推，但時分照實際送出的當下記錄。
        savedAt: now.subtract(Duration(days: _dayOffset)),
      ),
    );
    _textController.clear();
    _mood = diaryMoods.first;
    _weather = diaryWeathers.first;
    _temperature = diaryTemperatures.first;
    _dayOffset = 0;
    _reload();
  }

  Future<void> _showEntry(DiaryEntry entry) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(entry.mood, style: const TextStyle(fontSize: 22)),
                  if (entry.weather.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(entry.weather, style: const TextStyle(fontSize: 15)),
                  ],
                  if (entry.temperature.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      entry.temperature,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(_dateLabel(entry.savedAt), style: AppText.bodyDim),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(entry.text, style: AppText.body),
              const SizedBox(height: Gap.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, _EntryAction.edit),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('編輯'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                  ),
                  const SizedBox(width: Gap.xs),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(sheetContext, _EntryAction.delete),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('刪除'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.bad),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == _EntryAction.edit) {
      await _showEditDialog(entry);
    } else if (action == _EntryAction.delete) {
      final confirmed = await _confirmDelete(entry);
      if (confirmed != true) return;
      await ref.read(diaryRepositoryProvider).delete(entry.id);
      if (!mounted) return;
      _reload();
    }
  }

  /// 刪除是不可逆動作，點「刪除」只是打開這篇的操作選單，還要再確認
  /// 一次才會真的刪（2026-09-22 使用者要求：點下去要問是否確定）。
  Future<bool?> _confirmDelete(DiaryEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('確定要刪除這篇？', style: TextStyle(color: AppColors.ink)),
        content: Text(
          '${_dateLabel(entry.savedAt)}\n刪除後無法復原。',
          style: AppText.bodyDim,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.bad),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  /// 編輯只改心情／文字，原始打卡時間（[DiaryEntry.savedAt]）不變——
  /// 那是「哪天打的卡」的紀錄，編輯內容不該連帶改掉。
  Future<void> _showEditDialog(DiaryEntry entry) async {
    final controller = TextEditingController(text: entry.text);
    var mood = entry.mood;
    // 舊資料沒有天氣／冷熱欄位（空字串），編輯時給個預設選項，不留空著。
    var weather = entry.weather.isEmpty ? diaryWeathers.first : entry.weather;
    var temperature = entry.temperature.isEmpty
        ? diaryTemperatures.first
        : entry.temperature;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('編輯日記', style: TextStyle(color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final m in diaryMoods) ...[
                    Expanded(
                      child: _MoodButton(
                        mood: m,
                        selected: m == mood,
                        onTap: () => setDialogState(() => mood = m),
                      ),
                    ),
                    if (m != diaryMoods.last) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  for (final w in diaryWeathers) ...[
                    Expanded(
                      child: _TagChip(
                        label: w,
                        selected: w == weather,
                        onTap: () => setDialogState(() => weather = w),
                      ),
                    ),
                    if (w != diaryWeathers.last) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: Gap.xs),
              Row(
                children: [
                  for (final t in diaryTemperatures) ...[
                    Expanded(
                      child: _TagChip(
                        label: t,
                        selected: t == temperature,
                        onTap: () => setDialogState(() => temperature = t),
                      ),
                    ),
                    if (t != diaryTemperatures.last) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: Gap.sm),
              // 跟打卡卡輸入框同一個理由：固定行數＋換行，不要單行內部
              // 橫向自動捲動，不然拖曳選字會變成拖著框內容跑
              // （2026-09-22 使用者要求：編輯這邊也要能選取文字）。
              TextField(
                controller: controller,
                maxLength: 60,
                minLines: 1,
                // 塞不下就多長一行，最多長到 7 行，超過才用內建的上下
                // 捲動看剩下的內容（2026-09-22 使用者要求）。
                maxLines: 7,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                autofocus: true,
                decoration: const InputDecoration(counterText: ''),
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                await ref
                    .read(diaryRepositoryProvider)
                    .update(
                      DiaryEntry(
                        id: entry.id,
                        mood: mood,
                        text: text,
                        weather: weather,
                        temperature: temperature,
                        savedAt: entry.savedAt,
                      ),
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.diaryAccent,
                foregroundColor: AppColors.diaryAccentInk,
              ),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 左上角三條線選單是全 App 共用、固定的位置，子頁面不能把它換成
      // 只有返回鍵——兩個都要，返回鍵放三條線旁邊（2026-09-22 使用者
      // 要求）。
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: '日記',
                  actions: [
                    IconButton(
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出日記',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<DiaryEntry>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final all = [...snap.data!]
                        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
                      final targetDay = DateTime.now().subtract(
                        Duration(days: _dayOffset),
                      );
                      final checkedInForTarget = all.any(
                        (e) => isSameDay(e.savedAt, targetDay),
                      );
                      final selectedDay = _selectedDay;
                      DiaryEntry? selectedEntry;
                      if (selectedDay != null) {
                        for (final e in all) {
                          if (!isSameDay(e.savedAt, selectedDay)) continue;
                          if (selectedEntry == null ||
                              e.savedAt.isAfter(selectedEntry.savedAt)) {
                            selectedEntry = e;
                          }
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DateStrip(
                            entries: all,
                            selectedDay: _selectedDay,
                            onSelectDay: _selectDay,
                          ),
                          const SizedBox(height: Gap.md),
                          _CheckInCard(
                            controller: _textController,
                            mood: _mood,
                            weather: _weather,
                            temperature: _temperature,
                            dayOffset: _dayOffset,
                            checkedInForTarget: checkedInForTarget,
                            onDayOffsetChanged: (v) =>
                                setState(() => _dayOffset = v),
                            onMoodChanged: (m) => setState(() => _mood = m),
                            onWeatherChanged: (w) =>
                                setState(() => _weather = w),
                            onTemperatureChanged: (t) =>
                                setState(() => _temperature = t),
                            onSubmit: _submit,
                          ),
                          const SizedBox(height: Gap.md),
                          const PanelLabel('最近'),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: all.isEmpty
                                ? Center(
                                    child: Text(
                                      '還沒有任何日記，上面打個卡開始吧',
                                      style: AppText.bodyDim,
                                    ),
                                  )
                                : _buildRecentList(all, selectedEntry),
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

/// 頂部日期跳轉條，借設計稿 02 的版面精神再擴充：預設顯示這一週（週一
/// 到週日），可以左右切換週，也可以展開成整月月曆挑日子
/// （2026-09-22 使用者要求）。有打卡的日子在方塊左上角標一個小點；點
/// 任何一天（不限定有沒有打卡）都會選中那天，選中的方塊用跟毛玻璃同
/// 色系的特別外框標出來，同時讓下面的日記顯示跳到那一天
/// （2026-09-22 使用者要求）。
class _DateStrip extends StatefulWidget {
  const _DateStrip({
    required this.entries,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final List<DiaryEntry> entries;
  final DateTime? selectedDay;
  final void Function(DateTime day) onSelectDay;

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  DateTime _focusedDay = _stripDate(DateTime.now());
  bool _calendarOpen = false;

  // 展開的月曆要能像 iOS 行事曆一樣上下滑動切換月份（2026-09-22
  // 使用者要求），用 PageView 而不是「按鈕才能換月」。
  late final PageController _monthPageController = PageController(
    initialPage: _monthIndex(_focusedDay),
  );

  @override
  void dispose() {
    _monthPageController.dispose();
    super.dispose();
  }

  /// 把 PageView 目前停在的月份頁跟 [_focusedDay] 同步——[_shiftWeek]
  /// 或點月曆選日期都可能把 [_focusedDay] 換到跟 PageView 目前顯示的
  /// 不同月，不同步的話展開月曆時會看到舊的那一頁。跳頁方向是使用者
  /// 手動滑動以外的操作才呼叫，不會跟使用者正在滑的手勢互搶。
  void _syncMonthPage() {
    if (!_monthPageController.hasClients) return;
    final target = _monthIndex(_focusedDay);
    if (_monthPageController.page?.round() != target) {
      _monthPageController.jumpToPage(target);
    }
  }

  Map<DateTime, DiaryEntry> get _byDay {
    final map = <DateTime, DiaryEntry>{};
    for (final e in widget.entries) {
      final day = _stripDate(e.savedAt);
      final existing = map[day];
      if (existing == null || e.savedAt.isAfter(existing.savedAt)) {
        map[day] = e;
      }
    }
    return map;
  }

  List<DateTime> get _weekDays {
    final monday = _focusedDay.subtract(
      Duration(days: _focusedDay.weekday - 1),
    );
    return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
  }

  void _shiftWeek(int delta) {
    setState(() => _focusedDay = _focusedDay.add(Duration(days: 7 * delta)));
    _syncMonthPage();
  }

  void _tapDay(DateTime day) {
    setState(() {
      _focusedDay = day;
      _calendarOpen = false;
    });
    _syncMonthPage();
    widget.onSelectDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _shiftWeek(-1),
              icon: const Icon(Icons.chevron_left, size: 18),
              color: AppColors.ink3,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            Expanded(
              child: Text(
                _weekRangeLabel(_weekDays),
                textAlign: TextAlign.center,
                style: AppText.bodyDim,
              ),
            ),
            IconButton(
              onPressed: () => _shiftWeek(1),
              icon: const Icon(Icons.chevron_right, size: 18),
              color: AppColors.ink3,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => setState(() => _calendarOpen = !_calendarOpen),
              icon: Icon(
                _calendarOpen
                    ? Icons.calendar_month
                    : Icons.calendar_month_outlined,
                size: 18,
              ),
              color: _calendarOpen ? AppColors.diaryAccent : AppColors.ink3,
              tooltip: '展開月曆選日期',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _calendarOpen
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: _WeekRow(
            days: _weekDays,
            byDay: byDay,
            selectedDay: widget.selectedDay,
            onTap: _tapDay,
          ),
          // 月曆頁固定高度＋垂直 PageView 才能滑，高度照當下螢幕寬度
          // 反推格子大小再算，不用猜一個寫死的數字（每格是正方形，
          // 寬度隨螢幕變，寫死高度在窄螢幕會滑出格子外、寬螢幕又留一堆
          // 空白）。
          secondChild: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 4.0;
              const rows = 6.0;
              const headerHeight = 50.0;
              final cellSize = (constraints.maxWidth - spacing * 6) / 7;
              final gridHeight = cellSize * rows + spacing * (rows - 1);
              return SizedBox(
                height: headerHeight + gridHeight,
                child: PageView.builder(
                  controller: _monthPageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: (index) =>
                      setState(() => _focusedDay = _monthFromIndex(index)),
                  itemBuilder: (context, index) => _MonthCalendar(
                    month: _monthFromIndex(index),
                    byDay: byDay,
                    selectedDay: widget.selectedDay,
                    onTap: _tapDay,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 月份跟一個線性整數互轉，拿來當 [PageView] 的頁碼——月份差幾頁就是
/// 這兩個整數差幾，PageView 才能正確算出滑到第幾頁對應哪個月。
int _monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

DateTime _monthFromIndex(int index) =>
    DateTime(index ~/ 12, index % 12 + 1);

String _weekRangeLabel(List<DateTime> days) {
  final start = days.first;
  final end = days.last;
  if (start.month == end.month) {
    return '${start.month} 月 ${start.day} - ${end.day} 日';
  }
  return '${start.month}/${start.day} - ${end.month}/${end.day}';
}

/// 只留年月日，用來當 Map 的 key／比較「是不是同一天」。
DateTime _stripDate(DateTime d) => DateTime(d.year, d.month, d.day);

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.days,
    required this.byDay,
    required this.selectedDay,
    required this.onTap,
  });

  final List<DateTime> days;
  final Map<DateTime, DiaryEntry> byDay;
  final DateTime? selectedDay;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final today = _stripDate(DateTime.now());
    final selected = selectedDay == null ? null : _stripDate(selectedDay!);
    // 固定寬度＋spaceBetween，不是每格硬用 Expanded 撐滿——七格平分整個
    // 螢幕寬度會把每格擠成細細長長的比例，跟原本方方正正的日期方塊
    // 比例對不起來（2026-09-22 使用者回饋：日期變好窄，很醜）。
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          _DayChip(
            day: day,
            hasEntry: byDay.containsKey(day),
            isToday: day == today,
            isSelected: day == selected,
            onTap: () => onTap(day),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.hasEntry,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool hasEntry;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelected
                  ? AppColors.diaryAccent.withValues(alpha: 0.30)
                  : hasEntry
                  ? AppColors.diaryAccent.withValues(alpha: 0.16)
                  : AppColors.glassFill,
              border: Border.all(
                color: isSelected
                    ? AppColors.diaryAccent
                    : isToday
                    ? AppColors.diaryAccent.withValues(alpha: 0.55)
                    : AppColors.glassEdge,
                width: isSelected ? 1.6 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.diaryAccent.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Text(
                  '${day.day}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  '週${_weekdayLabels[day.weekday - 1]}',
                  style: const TextStyle(fontSize: 9, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          if (hasEntry)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.diaryAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 展開的整月月曆，跟一般日曆 App 一樣的網格版面，一樣有打卡小點跟
/// 選中外框。
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.byDay,
    required this.selectedDay,
    required this.onTap,
  });

  final DateTime month;
  final Map<DateTime, DiaryEntry> byDay;
  final DateTime? selectedDay;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1;
    final today = _stripDate(DateTime.now());
    final selected = selectedDay == null ? null : _stripDate(selectedDay!);

    return Column(
      children: [
        Text('${month.year} 年 ${month.month} 月', style: AppText.bodyDim),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in _weekdayLabels)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AppColors.ink3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingBlanks + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (_, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(
              month.year,
              month.month,
              i - leadingBlanks + 1,
            );
            return _MonthCell(
              day: day,
              hasEntry: byDay.containsKey(day),
              isToday: day == today,
              isSelected: day == selected,
              onTap: () => onTap(day),
            );
          },
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.hasEntry,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool hasEntry;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isSelected
                  ? AppColors.diaryAccent.withValues(alpha: 0.30)
                  : hasEntry
                  ? AppColors.diaryAccent.withValues(alpha: 0.16)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppColors.diaryAccent
                    : isToday
                    ? AppColors.diaryAccent.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: hasEntry ? FontWeight.w800 : FontWeight.w500,
                color: hasEntry ? AppColors.ink : AppColors.ink2,
              ),
            ),
          ),
          if (hasEntry)
            const Positioned(
              top: 1,
              left: 3,
              child: SizedBox(
                width: 5,
                height: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.diaryAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _dayOffsetLabels = ['今天', '昨天', '前天'];

/// 打卡卡：選心情＋一行文字＋送出，全部同一個操作完成（設計稿 04）。
/// 那天打過卡了就鎖住，不能重複打（要改就去下面列表編輯或刪掉那篇）。
///
/// 右上角可以選「今天／昨天／前天」——不是每天都剛好想到就寫，晚上
/// 12 點才想寫或漏了一天，補寫給前幾天用（2026-09-22 使用者要求）。
class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.controller,
    required this.mood,
    required this.weather,
    required this.temperature,
    required this.dayOffset,
    required this.checkedInForTarget,
    required this.onDayOffsetChanged,
    required this.onMoodChanged,
    required this.onWeatherChanged,
    required this.onTemperatureChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String mood;
  final String weather;
  final String temperature;
  final int dayOffset;
  final bool checkedInForTarget;
  final ValueChanged<int> onDayOffsetChanged;
  final ValueChanged<String> onMoodChanged;
  final ValueChanged<String> onWeatherChanged;
  final ValueChanged<String> onTemperatureChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final targetLabel = _dayOffsetLabels[dayOffset];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  checkedInForTarget
                      ? '$targetLabel已經記錄過了 ✓'
                      : '$targetLabel過得怎樣？一句話就好',
                  style: AppText.bodyDim,
                ),
              ),
              _DayOffsetDropdown(
                value: dayOffset,
                onChanged: onDayOffsetChanged,
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              for (final m in diaryMoods) ...[
                Expanded(
                  child: _MoodButton(
                    mood: m,
                    selected: m == mood,
                    onTap: checkedInForTarget ? null : () => onMoodChanged(m),
                  ),
                ),
                if (m != diaryMoods.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
          // 天氣現象跟冷熱感受是兩個獨立屬性，各自一排（2026-09-22
          // 使用者糾正：一開始誤把六個選項塞進同一排）。
          Row(
            children: [
              for (final w in diaryWeathers) ...[
                Expanded(
                  child: _TagChip(
                    label: w,
                    selected: w == weather,
                    onTap: checkedInForTarget
                        ? null
                        : () => onWeatherChanged(w),
                  ),
                ),
                if (w != diaryWeathers.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              for (final t in diaryTemperatures) ...[
                Expanded(
                  child: _TagChip(
                    label: t,
                    selected: t == temperature,
                    onTap: checkedInForTarget
                        ? null
                        : () => onTemperatureChanged(t),
                  ),
                ),
                if (t != diaryTemperatures.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // 固定行數＋不夠就換行（不是單行內部橫向自動捲動），不然
                // 打字超出框寬時框會自己滑動，滑鼠拖曳想選取文字時會變
                // 成拖著框內容跑，選不到字（2026-09-22 使用者要求）。
                child: TextField(
                  controller: controller,
                  enabled: !checkedInForTarget,
                  maxLength: 60,
                  minLines: 1,
                  // 塞不下就多長一行，最多長到 7 行，超過才用內建的
                  // 上下捲動看剩下的內容（2026-09-22 使用者要求）。
                  maxLines: 7,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  // 鎖住的時候底色、字色都要跟著變暗＋補一個鎖頭圖示，
                  // 不能只靠 enabled 那個不太看得出來的預設灰階差異，
                  // 不然使用者分不出「打不開」跟「還沒打字」
                  // （2026-09-22 使用者回饋：鎖起來但顏色沒變會混淆）。
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '例如：把日記功能接上真的資料了',
                    counterText: '',
                    filled: true,
                    fillColor: checkedInForTarget
                        ? AppColors.glassFill.withValues(alpha: 0.5)
                        : Colors.transparent,
                    suffixIcon: checkedInForTarget
                        ? const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: AppColors.ink3,
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: checkedInForTarget ? AppColors.ink3 : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                onPressed: checkedInForTarget ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.diaryAccent,
                  foregroundColor: AppColors.diaryAccentInk,
                  disabledBackgroundColor: AppColors.glassFill,
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Icon(Icons.check, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 補寫今天／昨天／前天的小選單（2026-09-22 使用者要求）。用
/// [PopupMenuButton] 不是 [DropdownButton]：後者開合時會把「目前選中的
/// 那個選項」對齊在按鈕位置展開，選到清單下面的選項（例如前天）之後，
/// 選單再打開就會整個往上跳一截去把那個選項對齊回按鈕——每次開合位置
/// 都不一樣，容易誤觸（2026-09-22 使用者回饋）。[PopupMenuButton] 固定
/// 貼著按鈕下面展開，跟目前選了哪一項無關，位置每次都一樣。
///
/// 按鈕本身用 [GlassCard]（全 App 唯一的毛玻璃實作，見該檔案說明），
/// 半圓角做成膠囊形——原本只有純色底+邊框，跟卡片其他地方的玻璃質感
/// 對不起來，看起來很突兀（2026-09-22 使用者回饋：沒有一點毛玻璃）。
class _DayOffsetDropdown extends StatelessWidget {
  const _DayOffsetDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      color: const Color(0xFF1A1A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      itemBuilder: (context) => [
        for (var i = 0; i < _dayOffsetLabels.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              _dayOffsetLabels[i],
              style: TextStyle(
                color: i == value ? AppColors.diaryAccent : AppColors.ink2,
                fontWeight: i == value ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        radius: Radii.chip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _dayOffsetLabels[value],
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final String mood;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? AppColors.diaryAccent.withValues(alpha: 0.26)
              : AppColors.glassFill,
          border: Border.all(
            color: selected ? AppColors.diaryAccent : AppColors.glassEdge,
          ),
        ),
        child: Text(mood, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}

/// 天氣現象／冷熱感受共用的小標籤按鈕。
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? AppColors.diaryAccent.withValues(alpha: 0.26)
              : AppColors.glassFill,
          border: Border.all(
            color: selected ? AppColors.diaryAccent : AppColors.glassEdge,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// 一行一則，滑過去就好，不是大卡片（設計稿 04）。[highlighted] 是點了
/// 頂部日期條選中那天時，用來標出「就是這一則」的（2026-09-22 使用者
/// 糾正：選日期不該把其他天濾掉，全部照樣顯示，只是標記+捲過去）。
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.highlighted = false,
  });

  final DiaryEntry entry;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: highlighted
              ? AppColors.diaryAccent.withValues(alpha: 0.18)
              : Colors.transparent,
          border: highlighted
              ? Border.all(color: AppColors.diaryAccent)
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(_shortDateLabel(entry.savedAt), style: AppText.note),
            ),
            Text(entry.mood, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                entry.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDateLabel(DateTime d) => '${d.month}/${d.day}';

/// 詳情／編輯／刪除確認都要看到完整的「哪年哪月哪日星期幾幾點幾分」
/// （2026-09-22 使用者要求），列表那種一行預覽才用 [_shortDateLabel]。
String _dateLabel(DateTime d) {
  final weekday = _weekdayLabels[d.weekday - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year} 年 ${d.month} 月 ${d.day} 日・週$weekday '
      '${two(d.hour)}:${two(d.minute)}';
}

/// 匯出的範圍：只匯出這台裝置 localStorage 裡的，還是連專案已經打包
/// 好的日記快照一起，跟 `kana_practice_history_page.dart` 的
/// `_ExportScope` 同一個用途。
enum _ExportScope { localOnly, withSeed }

Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(diaryRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExportDialog(repo: repo),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.repo});

  final DiaryRepository repo;

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
    final merged = mergeSeedRecords(
      local: await widget.repo.loadAll(),
      seed: await loadDiarySeed(),
      idOf: (e) => e.id,
      // 本機為準：要的是「補齊這台裝置漏掉、但專案快照裡已經有」的
      // 紀錄，不是拿快照蓋掉這台裝置剛打的卡。
      priority: SeedMergePriority.local,
    );
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
    final filename = 'lume-diary-${_exportTodayStamp()}.json';

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出日記',
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
                label: Text('連日記快照一起'),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => _setScope(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.glassFill,
              foregroundColor: AppColors.ink2,
              selectedBackgroundColor: AppColors.diaryAccent.withValues(
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
            backgroundColor: AppColors.diaryAccent,
            foregroundColor: AppColors.diaryAccentInk,
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
