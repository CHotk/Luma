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
///
/// 每段一個固定圖示（2026-10-15 使用者要求，照設計稿
/// `design-history/已選擇完成/2026-10-15_設定頁五種排法.html`）：一看就知道
/// 是哪個功能——日文是「あ」、YT 是播放鍵、交易是「₮」。這段裡每一列
/// 左邊都是同一個，不會一列一個樣子。
enum SettingsSection {
  app('一般', Color(0xFF8E8E93), icon: Icons.settings_rounded),
  english('英文', Color(0xFFFF9F0A), text: 'A'),
  jp('日文', Color(0xFFFF2D55), text: 'あ'),
  yt('YT', Color(0xFFFF3B30), icon: Icons.play_arrow_rounded),
  trade('交易&自律', Color(0xFF30B0C7), text: '₮'),
  lock('日記／負債', Color(0xFF5E5CE6), icon: Icons.lock_rounded),
  sync('雲端同步', Color(0xFF0A84FF), icon: Icons.cloud_rounded);

  const SettingsSection(this.label, this.color, {this.icon, this.text});
  final String label;

  /// 圖示用 Material 的 [icon]，或直接一個字 [text]（あ、₮ 這種）。
  final IconData? icon;
  final String? text;

  /// 這段的顏色：區塊裡每列左邊小方塊圖示的底色（iOS 設定那樣）。
  final Color color;
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
  SettingEntry(SettingsSection.jp, 'jp.light', '五十音櫻花樹畫法', '點亮 GPT 原本'),
  SettingEntry(SettingsSection.jp, 'jp.order', '日文首頁卡片順序', '排序'),
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
  SettingEntry(SettingsSection.yt, 'yt:搜尋時列出已看過、已隱藏', '搜尋時列出已看過、已隱藏'),
  SettingEntry(SettingsSection.yt, 'yt.removed', '影片下架檢查', '刪除 私人'),
  SettingEntry(SettingsSection.yt, 'yt.views', '觀看次數更新', '播放次數 觀看 熱門'),
  SettingEntry(SettingsSection.yt, 'yt.new', '影片 NEW 標記', '新片 幾天內 沒看過'),
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

class _AllSettingsPageState extends ConsumerState<AllSettingsPage>
    with SingleTickerProviderStateMixin {
  /// 真正的分頁（2026-10-16 使用者要求）：一段一頁，可以左右滑，每頁自己
  /// 記捲到哪、沒存的設定也留著（[_KeepAlive]）。
  late final TabController _tabs = TabController(
    length: SettingsSection.values.length,
    vsync: this,
    initialIndex: settingsSectionFor(widget.fromLocation).index,
  )..addListener(_onTabChanged);
  final _tabScroll = ScrollController();
  final _search = TextEditingController();
  final _tabKeys = {for (final s in SettingsSection.values) s: GlobalKey()};
  final _anchors = <String, GlobalKey>{};
  final _highlight = ValueNotifier<String?>(null);
  late SettingsSection _current = settingsSectionFor(widget.fromLocation);

  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTab(_current));
  }

  /// 滑動或點分頁籤換頁：上面那排分頁籤跟著亮、捲到看得到。
  void _onTabChanged() {
    final s = SettingsSection.values[_tabs.index];
    if (s == _current) return;
    setState(() => _current = s);
    _showTab(s);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _tabScroll.dispose();
    _search.dispose();
    _highlight.dispose();
    super.dispose();
  }

  void _select(SettingsSection s) => _tabs.animateTo(s.index);

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

  Future<void> _openResult(SettingEntry e) async {
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() => _current = e.section);
    _tabs.index = e.section.index;
    // 等那一頁畫出來才捲得到。
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    _showTab(e.section);
    final ctx = _anchors[e.anchor]?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.2,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
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
                                onTap: () => _select(s),
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
                            child: TabBarView(
                              controller: _tabs,
                              children: [
                                for (final s in SettingsSection.values)
                                  _KeepAlive(
                                    child: SingleChildScrollView(
                                      key: PageStorageKey(s),
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _SectionHeader(section: s),
                                          _sectionBody(s),
                                          const SizedBox(height: Gap.lg),
                                          const VersionFooter(),
                                          // 底部浮動分頁列不要蓋住最後一列。
                                          SizedBox(
                                            height:
                                                Gap.lg +
                                                FloatingNavInset.of(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
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
  const _SectionHeader({required this.section});

  final SettingsSection section;

  @override
  // iOS 設定那樣：區塊上面一行灰色小字（2026-10-15 最終版 2）。
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 16, top: Gap.xs, bottom: 6),
    child: Text(
      section.label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink3,
      ),
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
                  leading: SettingIcon(section: e.section),
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

/// 分頁滑走時不要把那一頁拆掉：捲動位置、還沒存的輸入都留著。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
