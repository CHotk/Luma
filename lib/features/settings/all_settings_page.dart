import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'other_settings_page.dart';
import 'settings_anchor.dart';
import 'settings_page.dart';

/// 設定頁的各段（2026-10-15 使用者選設計稿第 5 版「上方分頁籤」）。
enum SettingsSection {
  app('一般', Icons.tune_rounded),
  english('英文', Icons.translate_rounded),
  jp('日文', Icons.spa_outlined),
  yt('YT', Icons.smart_display_outlined),
  trade('交易&自律', Icons.candlestick_chart_outlined),
  lock('日記／負債', Icons.lock_outline_rounded),
  sync('雲端同步', Icons.cloud_sync_outlined);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 從哪一頁點齒輪，就先跳到哪一段（2026-10-15 使用者要求：在哪個功能
/// 就自動選那個功能的分頁）。英文學習的頁面跟沒帶路徑的都算英文。
SettingsSection settingsSectionFor(String? location) {
  final l = location ?? '';
  bool any(List<String> ps) => ps.any(l.startsWith);
  if (any(['/yt-tracker', '/yt-playlists'])) return SettingsSection.yt;
  if (any(['/jp', '/kana'])) return SettingsSection.jp;
  if (any(['/crypto-watch'])) return SettingsSection.trade;
  if (any(['/diary', '/debt'])) return SettingsSection.lock;
  if (any(['/sync'])) return SettingsSection.sync;
  if (any([
    '/start',
    '/fitness',
    '/smoking-log',
    '/drinking-log',
    '/debug-log',
    '/local-storage',
  ])) {
    return SettingsSection.app;
  }
  return SettingsSection.english;
}

/// 搜尋用的設定清單：哪一段、捲到哪個錨點（見 [SettingAnchor]）、標題、
/// 額外關鍵字。新增設定時順手加一行，搜尋才找得到。
class SettingEntry {
  const SettingEntry(
    this.section,
    this.anchor,
    this.title, [
    this.keywords = '',
  ]);

  final SettingsSection section;
  final String anchor;
  final String title;
  final String keywords;

  bool matches(String q) {
    final s = q.toLowerCase();
    return '$title $keywords ${section.label}'.toLowerCase().contains(s);
  }
}

const settingIndex = [
  SettingEntry(SettingsSection.app, 'app.home', '首頁樣式', '圖示格 今日儀表板'),
  SettingEntry(SettingsSection.app, 'app.bar', '底部分頁列', '各自功能 全 App 共用 不顯示 膠囊'),
  SettingEntry(SettingsSection.app, 'app.order', '功能順序', '首頁 圖示格 排序'),
  SettingEntry(SettingsSection.app, 'app.logo', 'App Logo', '開機畫面 圖示'),
  SettingEntry(SettingsSection.english, 'en.order', '英文首頁卡片順序', '排序'),
  SettingEntry(
    SettingsSection.english,
    'en.style',
    '題型',
    '點選 打字 混合 一輪幾題要打字 測驗',
  ),
  SettingEntry(SettingsSection.english, 'en.daily', '每天的份量', '每天最多幾輪 每天目標幾分鐘'),
  SettingEntry(
    SettingsSection.english,
    'en.judge',
    '掌握判定',
    '答對幾次 錯過的字 幾倍 待複習 候選池 已掌握 句型 每輪出題數',
  ),
  SettingEntry(SettingsSection.jp, 'jp.ring', '首頁顯示今天進度圈', '日文'),
  SettingEntry(SettingsSection.jp, 'jp.order', '日文首頁卡片順序', '排序'),
  SettingEntry(SettingsSection.yt, 'yt.bar', '底部分頁列（YT）', '頻道 影片 播放清單'),
  SettingEntry(SettingsSection.yt, 'yt.videoTab', '底部分頁列「影片」開的頻道', '快捷'),
  SettingEntry(SettingsSection.yt, 'yt.key', 'YouTube API 金鑰', 'key 配額'),
  SettingEntry(SettingsSection.yt, 'yt.export', '匯出分類／頻道', '備份'),
  SettingEntry(SettingsSection.yt, 'yt.catOrder', '分類顯示順序', '排序'),
  SettingEntry(SettingsSection.yt, 'yt.backfill', '補齊影片類型', 'Shorts 直播'),
  SettingEntry(SettingsSection.yt, 'yt.stats', '訂閱人數更新頻率', '天'),
  SettingEntry(SettingsSection.yt, 'yt.open', '點影片時', '內嵌播放 開新分頁 YouTube'),
  SettingEntry(SettingsSection.yt, 'yt.player', '內嵌播放器樣式', '浮動視窗 下滑收合 正中彈窗'),
  SettingEntry(SettingsSection.yt, 'yt:依影片顯示也抓冷藏頻道', '依影片顯示也抓冷藏頻道'),
  SettingEntry(SettingsSection.yt, 'yt:依影片顯示也抓待評鑑頻道', '依影片顯示也抓待評鑑頻道'),
  SettingEntry(SettingsSection.yt, 'yt:頻道頁右側捲動條', '頻道頁右側捲動條'),
  SettingEntry(SettingsSection.yt, 'yt:頻道頁「回到最上面」按鈕', '頻道頁「回到最上面」按鈕'),
  SettingEntry(SettingsSection.yt, 'yt:進頻道自動抓完全部影片', '進頻道自動抓完全部影片', '背景 快取'),
  SettingEntry(SettingsSection.yt, 'yt:頻道搜尋也問 YouTube', '頻道搜尋也問 YouTube', '快取'),
  SettingEntry(SettingsSection.yt, 'yt:搜尋時列出已看過、已隱藏', '搜尋時列出已看過、已隱藏'),
  SettingEntry(SettingsSection.yt, 'yt.removed', '影片下架檢查', '刪除 私人'),
  SettingEntry(SettingsSection.yt, 'yt.purged', '永久刪除的頻道'),
  SettingEntry(SettingsSection.trade, 'trade.rate', 'USDT 換台幣匯率', '匯率 台幣'),
  SettingEntry(SettingsSection.lock, 'lock.pw', '日記／負債密碼', '密碼'),
  SettingEntry(
    SettingsSection.sync,
    'sync.page',
    '多裝置同步',
    'R2 立即同步 同步紀錄 備份 雲端',
  ),
];

/// 全部功能的設定在同一頁，用區塊分開（2026-10-15 使用者選設計稿第 5 版）：
/// 上方分頁籤點了捲到那段、往下滑分頁籤跟著亮；從哪個功能點齒輪就先
/// 跳到那段；搜尋框打字列出符合的設定，點了捲過去閃一下。
class AllSettingsPage extends ConsumerStatefulWidget {
  const AllSettingsPage({super.key, this.fromLocation});

  /// 點齒輪那一刻的路徑（見 `open_settings.dart`）。
  final String? fromLocation;

  @override
  ConsumerState<AllSettingsPage> createState() => _AllSettingsPageState();
}

class _AllSettingsPageState extends ConsumerState<AllSettingsPage> {
  final _scroll = ScrollController();
  final _tabScroll = ScrollController();
  final _search = TextEditingController();
  final _sectionKeys = {for (final s in SettingsSection.values) s: GlobalKey()};
  final _tabKeys = {for (final s in SettingsSection.values) s: GlobalKey()};
  final _anchors = <String, GlobalKey>{};
  final _highlight = ValueNotifier<String?>(null);
  late SettingsSection _current = settingsSectionFor(widget.fromLocation);

  /// 點分頁籤捲動中：先不讓捲動監聽改亮哪一格，免得一路閃過中間的。
  bool _jumping = false;

  /// 剛打開：上面幾段（例如英文要讀設定檔）畫完會變高，把目標段落往下
  /// 推；使用者還沒自己滑之前，內容高度一變就再對準一次。
  bool _pinned = true;

  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncTab);
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpTo(_current, animate: false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _tabScroll.dispose();
    _search.dispose();
    _highlight.dispose();
    super.dispose();
  }

  void _repin() {
    if (!_pinned || !mounted) return;
    final ctx = _sectionKeys[_current]!.currentContext;
    if (ctx == null) return;
    _jumping = true;
    Scrollable.ensureVisible(ctx);
    _jumping = false;
  }

  Future<void> _jumpTo(SettingsSection s, {bool animate = true}) async {
    if (animate) _pinned = false;
    setState(() => _current = s);
    _showTab(s);
    final ctx = _sectionKeys[s]!.currentContext;
    if (ctx == null) return;
    _jumping = true;
    await Scrollable.ensureVisible(
      ctx,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
    _jumping = false;
  }

  void _showTab(SettingsSection s) {
    final ctx = _tabKeys[s]!.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  /// 往下滑：最上面那段是哪段，分頁籤就亮哪格。
  void _syncTab() {
    if (_jumping || !_scroll.hasClients) return;
    final top = (context.findRenderObject() as RenderBox?)?.localToGlobal(
      Offset.zero,
    );
    if (top == null) return;
    var cur = SettingsSection.values.first;
    for (final s in SettingsSection.values) {
      final box =
          _sectionKeys[s]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= top.dy + 180) cur = s;
    }
    // 滑到底：最後一段就算很短也要亮。
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 4) {
      cur = SettingsSection.values.last;
    }
    if (cur != _current) {
      setState(() => _current = cur);
      _showTab(cur);
    }
  }

  Future<void> _openResult(SettingEntry e) async {
    _pinned = false;
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() => _current = e.section);
    // 等清單畫回來才捲得到。
    await WidgetsBinding.instance.endOfFrame;
    final ctx =
        _anchors[e.anchor]?.currentContext ??
        _sectionKeys[e.section]!.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _jumping = true;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.2,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    _jumping = false;
    _showTab(e.section);
    _highlight.value = e.anchor;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted && _highlight.value == e.anchor) _highlight.value = null;
  }

  Widget _sectionBody(SettingsSection s) => switch (s) {
    SettingsSection.app => const AppHomeSettingsSection(),
    SettingsSection.english => const EnglishSettingsSection(),
    SettingsSection.jp => const JpSettingsSection(),
    SettingsSection.yt => const YtSettingsSection(),
    SettingsSection.trade => const TradeSettingsSection(),
    SettingsSection.lock => LockSettingsSection(
      // 不是從日記／負債（已經過密碼鎖）進來的，改密碼前要先輸入舊密碼。
      askCurrent:
          settingsSectionFor(widget.fromLocation) != SettingsSection.lock,
    ),
    SettingsSection.sync => const SyncSettingsSection(),
  };

  @override
  Widget build(BuildContext context) {
    // 訂閱人數更新頻率調了沒存，離開前要提醒（2026-09-29 使用者要求）。
    final hasUnsaved = ref.watch(ytStatsRefreshDirtyProvider);
    final q = _query;
    final results = q.isEmpty
        ? const <SettingEntry>[]
        : [
            for (final e in settingIndex)
              if (e.matches(q)) e,
          ];
    return PopScope(
      canPop: !hasUnsaved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showAppConfirmDialog(
          context,
          title: '還沒儲存',
          message: '訂閱人數更新頻率調整了但還沒按儲存，確定要離開嗎？',
          confirmLabel: '不儲存，離開',
          cancelLabel: '留下繼續調',
        );
        if (leave && context.mounted) {
          ref.read(ytStatsRefreshDirtyProvider.notifier).state = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        drawer: const AppSideDrawer(),
        body: AmbientBackground(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.sm),
                  const AppTopBar(title: '設定', showSettings: false),
                  const SizedBox(height: Gap.sm),
                  _SearchField(controller: _search),
                  const SizedBox(height: Gap.sm),
                  if (q.isEmpty)
                    SizedBox(
                      height: 36,
                      child: ListView(
                        controller: _tabScroll,
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final s in SettingsSection.values)
                            Padding(
                              key: _tabKeys[s],
                              padding: const EdgeInsets.only(right: 6),
                              child: _TabChip(
                                section: s,
                                selected: s == _current,
                                onTap: () => _jumpTo(s),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: Gap.sm),
                  Expanded(
                    child: q.isNotEmpty
                        ? _SearchResults(
                            query: q,
                            results: results,
                            onTap: _openResult,
                          )
                        : SettingsAnchors(
                            keys: _anchors,
                            highlight: _highlight,
                            child: NotificationListener<Notification>(
                              onNotification: (n) {
                                if (n is UserScrollNotification) {
                                  _pinned = false;
                                } else if (n is SizeChangedLayoutNotification &&
                                    _pinned) {
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _repin(),
                                  );
                                }
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: _scroll,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                child: SizeChangedLayoutNotifier(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final s
                                          in SettingsSection.values) ...[
                                        _SectionHeader(
                                          key: _sectionKeys[s],
                                          section: s,
                                        ),
                                        _sectionBody(s),
                                        const SizedBox(height: Gap.lg),
                                      ],
                                      const VersionFooter(),
                                      // 最後一段捲得到最上面，分頁籤才對得上；
                                      // 底部浮動分頁列也不會蓋住。
                                      SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height *
                                                0.45 +
                                            FloatingNavInset.of(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: const TextStyle(color: AppColors.ink),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: '搜尋設定，例如：播放、同步、冷藏',
      isDense: true,
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: controller.clear,
            ),
      filled: true,
      fillColor: AppColors.glassFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassEdge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassEdge),
      ),
    ),
  );
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: selected ? AppColors.accentSolid : AppColors.glassFill,
          border: Border.all(
            color: selected ? AppColors.accentSolid : AppColors.glassEdge,
          ),
        ),
        child: Text(
          section.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.ink2,
          ),
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, top: Gap.xs, bottom: Gap.sm),
    child: Row(
      children: [
        Icon(section.icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(
          section.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.results,
    required this.onTap,
  });

  final String query;
  final List<SettingEntry> results;
  final ValueChanged<SettingEntry> onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xl),
        child: Text(
          '找不到「$query」相關的設定',
          textAlign: TextAlign.center,
          style: AppText.bodyDim,
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Gap.sm),
          child: Text('找到 ${results.length} 項，點了跳過去', style: AppText.note),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final e in results)
                ListTile(
                  dense: true,
                  leading: Icon(e.section.icon, color: AppColors.accent),
                  title: Text(
                    e.title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(e.section.label, style: AppText.note),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink3,
                  ),
                  onTap: () => onTap(e),
                ),
            ],
          ),
        ),
        SizedBox(height: FloatingNavInset.of(context) + Gap.xl),
      ],
    );
  }
}
