import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/app_home_style_store.dart';
import '../../data/repositories/diary_password_store.dart';
import '../../data/repositories/jp_home_ring_store.dart';
import '../../data/repositories/jp_light_style_store.dart';
import '../../data/repositories/usdt_twd_rate_store.dart';
import '../../data/repositories/yt_embed_player_style_store.dart';
import '../../data/repositories/yt_stats_refresh_setting_store.dart';
import '../../data/repositories/nav_bar_prefs_store.dart';
import '../../data/repositories/yt_display_prefs_store.dart';
import '../../data/repositories/yt_video_open_mode_store.dart';
import '../../shared/widgets/app_notice.dart';
import 'settings_page.dart' show AppLogoSettingsCard;
import 'all_settings_page.dart' show SettingsSection;
import 'settings_anchor.dart';
import '../crypto_watch/trade_ui.dart' show oneDecimalInput, round1;
import '../yt_tracker/yt_api_key_dialog.dart';
import '../yt_tracker/yt_playlist_actions.dart';
import '../yt_tracker/yt_tracker_browse_page.dart'
    show refreshYtSubscriberStats;
import '../yt_tracker/yt_tracker_home_page.dart' show showYtExportDialog;
import '../yt_tracker/yt_type_backfill.dart';

/// App 首頁的設定：首頁樣式（2026-10-05 使用者要求：今日儀表板當預設，
/// 這裡可以切回原本的圖示格）。
class AppHomeSettingsSection extends ConsumerWidget {
  const AppHomeSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appHomeStyleProvider);
    return SettingsBlock(
      section: SettingsSection.app,
      children: [
        SettingAnchor(
          id: 'app.home',
          child: SettingsRowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '首頁樣式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  style == AppHomeStyle.dashboard
                      ? '打開就看到各功能今天的狀態，點卡片進去'
                      : '像手機桌面，每個功能一格圖示',
                  style: AppText.note,
                ),
                const SizedBox(height: Gap.sm),
                SegmentedButton<AppHomeStyle>(
                  // 順序：圖示格在前（預設）、儀表板在後（2026-10-06 使用者要求）。
                  segments: const [
                    ButtonSegment(value: AppHomeStyle.grid, label: Text('圖示格')),
                    ButtonSegment(
                      value: AppHomeStyle.dashboard,
                      label: Text('今日儀表板'),
                    ),
                  ],
                  selected: {style},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) async {
                    ref.read(appHomeStyleProvider.notifier).state = s.first;
                    await AppHomeStyleStore(
                      ref.read(keyValueStoreProvider),
                    ).save(s.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        const SettingAnchor(id: 'app.bar', child: _NavBarModeCard()),
        const SizedBox(height: Gap.sm),
        // 圖示格的功能順序（2026-10-06 使用者要求：像 YT 分類順序那樣，
        // 在設定裡拖曳調整）。
        SettingAnchor(
          id: 'app.order',
          child: SettingsRowCard(
            child: Row(
              children: [
                const SettingIcon(),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '功能順序',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text('圖示格裡每個功能的先後', style: AppText.note),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/home-card-order/app'),
                  child: const Text('調整'),
                ),
              ],
            ),
          ),
        ),
        // App Logo 原本在英文學習的設定裡，它是整個 App 的，搬到一般。
        const SizedBox(height: Gap.sm),
        const SettingAnchor(id: 'app.logo', child: AppLogoSettingsCard()),
      ],
    );
  }
}

/// 交易&自律的設定（2026-10-10 使用者要求）：USDT 換台幣的匯率，預設 31。
/// 改完各頁的「≈ NT$」馬上跟著變，按同步會帶到其他裝置。
class TradeSettingsSection extends ConsumerStatefulWidget {
  const TradeSettingsSection({super.key});

  @override
  ConsumerState<TradeSettingsSection> createState() =>
      _TradeSettingsSectionState();
}

class _TradeSettingsSectionState extends ConsumerState<TradeSettingsSection> {
  late final _ctrl = TextEditingController(
    text: _fmt(ref.read(usdtTwdRateProvider)),
  )..addListener(() => setState(() {}));

  static String _fmt(double v) {
    final r = round1(v);
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_ctrl.text.trim());
    return v == null || v <= 0 ? null : round1(v);
  }

  Future<void> _save(double rate) async {
    ref.read(usdtTwdRateProvider.notifier).state = rate;
    await UsdtTwdRateStore(ref.read(keyValueStoreProvider)).save(rate);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    showAppNotice(context, '已設定匯率：1 USDT ≈ ${_fmt(rate)} 台幣');
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(usdtTwdRateProvider);
    final v = _value;
    return SettingsBlock(
      section: SettingsSection.trade,
      children: [
        SettingAnchor(
          id: 'trade.rate',
          child: SettingsRowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'USDT 換台幣匯率',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'USDT 金額後面會加上「≈ NT\$」換算，預設 '
                  '${_fmt(UsdtTwdRateStore.defaultRate)}・同步時會帶到其他裝置',
                  style: AppText.note,
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    const Text(
                      '1 USDT ＝',
                      style: TextStyle(fontSize: 14, color: AppColors.ink2),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // 跟交易功能其他數字一樣最多小數第一位。
                        inputFormatters: oneDecimalInput,
                        decoration: InputDecoration(
                          suffixText: '台幣',
                          isDense: true,
                          errorText: _ctrl.text.trim().isNotEmpty && v == null
                              ? '要大於 0 的數字'
                              : null,
                        ),
                        onSubmitted: (_) {
                          if (v != null) _save(v);
                        },
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    FilledButton(
                      onPressed: v == null || v == saved
                          ? null
                          : () => _save(v),
                      child: const Text('儲存'),
                    ),
                  ],
                ),
                if (saved != UsdtTwdRateStore.defaultRate)
                  TextButton(
                    onPressed: () {
                      _ctrl.text = _fmt(UsdtTwdRateStore.defaultRate);
                      _save(UsdtTwdRateStore.defaultRate);
                    },
                    child: Text('改回預設 ${_fmt(UsdtTwdRateStore.defaultRate)}'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 日文的設定（2026-10-05 使用者要求：首頁「今天進度」那一圈預設隱藏，
/// 在這裡打開）。
class JpSettingsSection extends ConsumerWidget {
  const JpSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showRing = ref.watch(jpShowProgressRingProvider);
    final lightStyle = ref.watch(jpLightStyleProvider);
    return SettingsBlock(
      section: SettingsSection.jp,
      children: [
        SettingAnchor(
          id: 'jp.ring',
          child: SettingsRowCard(
            child: Row(
              children: [
                const SettingIcon(),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '首頁顯示今天進度圈',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text('今天練了幾題／幾分鐘的那一圈', style: AppText.note),
                    ],
                  ),
                ),
                Switch(
                  value: showRing,
                  onChanged: (v) async {
                    ref.read(jpShowProgressRingProvider.notifier).state = v;
                    await JpHomeRingStore(
                      ref.read(keyValueStoreProvider),
                    ).save(v);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        SettingAnchor(
          id: 'jp.light',
          child: SettingsRowCard(
            child: Row(
              children: [
                const SettingIcon(),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '五十音櫻花樹畫法',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text('GPT 圖版（預設）或原本的樹枝版', style: AppText.note),
                    ],
                  ),
                ),
                SegmentedButton<JpLightStyle>(
                  segments: const [
                    ButtonSegment(value: JpLightStyle.gpt, label: Text('GPT')),
                    ButtonSegment(
                      value: JpLightStyle.classic,
                      label: Text('原本'),
                    ),
                  ],
                  selected: {lightStyle},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) async {
                    ref.read(jpLightStyleProvider.notifier).state = v.first;
                    await JpLightStyleStore(
                      ref.read(keyValueStoreProvider),
                    ).save(v.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        SettingAnchor(
          id: 'jp.order',
          child: SettingsRowCard(
            child: Row(
              children: [
                const SettingIcon(),
                const SizedBox(width: Gap.sm),
                const Expanded(
                  child: Text(
                    '首頁卡片順序',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/home-card-order/jp'),
                  child: const Text('調整'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class YtSettingsSection extends ConsumerWidget {
  const YtSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = (ref.watch(ytApiKeyProvider) ?? '').isNotEmpty;
    return SettingsBlock(
      section: SettingsSection.yt,
      children: [
        // 底部分頁列的顯示方式只放「一般」（2026-10-15 使用者要求：YT 這裡
        // 不用重複一份）。「影片」要開哪個頻道還是放最上面（2026-10-14
        // 使用者回報在 YT 設定找不到）。
        SettingAnchor(
          id: 'yt.videoTab',
          child: SettingsRowCard(
            child: Consumer(
              builder: (context, ref, _) => _VideoTabChannelRow(
                channelId: ref.watch(
                  ytDisplayPrefsProvider.select((p) => p.videoTabChannelId),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        SettingsRowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingAnchor(
                id: 'yt.key',
                child: Row(
                  children: [
                    const SettingIcon(),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'YouTube API 金鑰',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(hasKey ? '已儲存' : '還沒設定', style: AppText.note),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => showYtApiKeyDialog(context, ref),
                      child: const Text('設定'),
                    ),
                  ],
                ),
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              SettingAnchor(
                id: 'yt.export',
                child: Row(
                  children: [
                    const SettingIcon(),
                    const SizedBox(width: Gap.sm),
                    const Expanded(
                      child: Text(
                        '匯出分類／頻道',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => showYtExportDialog(context, ref),
                      child: const Text('匯出'),
                    ),
                  ],
                ),
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              SettingAnchor(
                id: 'yt.catOrder',
                child: Row(
                  children: [
                    const SettingIcon(),
                    const SizedBox(width: Gap.sm),
                    const Expanded(
                      child: Text(
                        '分類顯示順序',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.push('/yt-tracker/category-order'),
                      child: const Text('調整'),
                    ),
                  ],
                ),
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const SettingAnchor(
                id: 'yt.backfill',
                child: YtTypeBackfillRow(),
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const SettingAnchor(id: 'yt.stats', child: _StatsRefreshRow()),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const SettingAnchor(id: 'yt.open', child: _VideoOpenModeRow()),
              const SettingAnchor(
                id: 'yt.player',
                child: _EmbedPlayerStyleRow(),
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const _YtDisplayPrefsRows(),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              // 永久刪除的頻道清單（2026-10-06 使用者要求：放設定裡，想看
              // 刪了哪些可以點開；放最下面）。
              SettingAnchor(
                id: 'yt.purged',
                child: Row(
                  children: [
                    const SettingIcon(),
                    const SizedBox(width: Gap.sm),
                    const Expanded(
                      child: Text(
                        '永久刪除的頻道',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/yt-tracker/purged'),
                      child: const Text('查看'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 日記密碼設定（2026-09-29 使用者要求）：只有一顆「變更密碼」，密碼
/// 存在 [DiaryPasswordStore]，預設 `15975311`，改掉的值也會同步到雲端
/// （見 `r2_sync_section.dart` 把 `syncDiaryPassword` 併進「日記」那個
/// 同步任務）。這頁本身要先過日記的密碼鎖才進得來（齒輪在日記解鎖後的
/// 頂部列），不用在這裡再驗證一次目前密碼。
class LockSettingsSection extends ConsumerWidget {
  const LockSettingsSection({super.key, this.askCurrent = false});

  /// 設定全部在同一頁以後（2026-10-15），不是從日記／負債（已經過密碼
  /// 鎖）點齒輪進來的，改密碼前要先輸入目前的密碼，不然誰都改得掉。
  final bool askCurrent;

  Future<bool> _checkCurrent(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('先輸入目前的密碼', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '目前的密碼'),
          style: const TextStyle(color: AppColors.ink),
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final current = await DiaryPasswordStore(
      ref.read(keyValueStoreProvider),
    ).loadPassword();
    if (controller.text.trim() == current) return true;
    if (context.mounted) showAppNotice(context, '密碼不對', isError: true);
    return false;
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (askCurrent && !await _checkCurrent(context, ref)) return;
    if (!context.mounted) return;
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('變更日記／負債密碼', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '新密碼'),
          style: const TextStyle(color: AppColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.diaryAccent,
              foregroundColor: AppColors.diaryAccentInk,
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    final newPassword = controller.text.trim();
    if (saved != true || newPassword.isEmpty) return;
    await DiaryPasswordStore(
      ref.read(keyValueStoreProvider),
    ).savePassword(newPassword);
    if (!context.mounted) return;
    showAppNotice(context, '已更新日記／負債密碼');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsBlock(
      section: SettingsSection.lock,
      children: [
        SettingAnchor(
          id: 'lock.pw',
          child: SettingsRowCard(
            child: Row(
              children: [
                const SettingIcon(),
                const SizedBox(width: Gap.sm),
                const Expanded(
                  child: Text(
                    '日記／負債密碼',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _showChangePasswordDialog(context, ref),
                  child: const Text('變更'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 雲端同步那段：同步本身（R2 帳號、立即同步、同步紀錄）在同步頁，這裡
/// 放一列連過去，搜尋「同步」也找得到。
class SyncSettingsSection extends StatelessWidget {
  const SyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context) => SettingsBlock(
    section: SettingsSection.sync,
    children: [
      SettingAnchor(
        id: 'sync.page',
        child: SettingsRowCard(
          child: Row(
            children: [
              const SettingIcon(),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '多裝置同步',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text('R2 帳號、立即同步、同步紀錄', style: AppText.note),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push('/sync'),
                child: const Text('開啟'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// 訂閱人數多久重新問一次 API，這裡調（2026-09-29 使用者要求：原本寫死
/// 12 小時，改成可設定天數，預設一天一輪）。只影響「依頻道顯示」畫面
/// 自動更新訂閱人數的節奏，跟多裝置同步無關，不用跨裝置同步這個值。
///
/// +/- 只改本地草稿值，不會馬上生效——要按「儲存」才真的存檔，而且
/// 儲存那一下也會立刻觸發一次檢查（2026-09-29 使用者要求：「設定調完
/// 以後應該這天數要有儲存按鈕 點下也該處發一次」），不用等下次剛好
/// 打開某個分類列表才生效。
class _StatsRefreshRow extends ConsumerStatefulWidget {
  const _StatsRefreshRow();

  @override
  ConsumerState<_StatsRefreshRow> createState() => _StatsRefreshRowState();
}

class _StatsRefreshRowState extends ConsumerState<_StatsRefreshRow> {
  static const _min = 1;
  static const _max = 14;

  late int _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(ytStatsRefreshDaysProvider);
    // 每次重新進這個設定頁都先歸零，避免上次選了「不儲存離開」殘留下來
    // 的髒旗標一直卡著（2026-09-29 使用者要求加離開提醒後才需要注意
    // 這個，見下面 [_setDraft] 跟 `OtherSettingsPage` 的 `PopScope`）。
    ref.read(ytStatsRefreshDirtyProvider.notifier).state = false;
  }

  void _setDraft(int value) {
    setState(() => _draft = value);
    final saved = ref.read(ytStatsRefreshDaysProvider);
    ref.read(ytStatsRefreshDirtyProvider.notifier).state = _draft != saved;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      ref.read(ytStatsRefreshDaysProvider.notifier).state = _draft;
      ref.read(ytStatsRefreshDirtyProvider.notifier).state = false;
      await YtStatsRefreshSettingStore(
        ref.read(keyValueStoreProvider),
      ).save(_draft);
      final result = await refreshYtSubscriberStats(ref);
      if (!mounted) return;
      showAppNotice(
        context,
        result.updated.isEmpty
            ? '已儲存，目前沒有需要更新的頻道'
            : '已儲存，${result.updated.length} 個頻道更新了訂閱人數',
      );
    } catch (e) {
      if (mounted) showAppNotice(context, '儲存失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(ytStatsRefreshDaysProvider);
    final dirty = _draft != saved;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: const SettingIcon(),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '訂閱人數更新頻率',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              // 天數數字改沒存的時候變色提醒，存了才變回原本顏色
              // （2026-09-29 使用者要求：不用另外寫「還沒儲存」文字，
              // 數字變色本身就是提示）。
              RichText(
                text: TextSpan(
                  style: AppText.note,
                  children: [
                    const TextSpan(text: '每 '),
                    TextSpan(
                      text: '$_draft',
                      style: TextStyle(
                        color: dirty ? AppColors.mid : AppColors.ink3,
                        fontWeight: dirty ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                    const TextSpan(text: ' 天重新問一次 API'),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xs),
              Row(
                children: [
                  // 加減做成膠囊狀，不用「圓圈裡一個加減號」那種圖示
                  // （2026-09-29 使用者要求：圓點很醜）。
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.glassFill,
                        border: Border.all(color: AppColors.glassEdge),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StepperButton(
                            icon: Icons.remove,
                            onTap: _draft > _min
                                ? () => _setDraft(_draft - 1)
                                : null,
                          ),
                          Container(
                            width: 1,
                            height: 16,
                            color: AppColors.glassEdge,
                          ),
                          _StepperButton(
                            icon: Icons.add,
                            onTap: _draft < _max
                                ? () => _setDraft(_draft + 1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  SizedBox(
                    height: 32,
                    child: FilledButton(
                      onPressed: dirty && !_saving ? _save : null,
                      style: FilledButton.styleFrom(
                        // 一般藍色主色，不用 ytAccent 的紅——「儲存」不是
                        // 危險動作，紅色看起來像警告（2026-09-29 使用者
                        // 要求）。
                        backgroundColor: AppColors.accentSolid,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('儲存', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 膠囊狀加減按鈕裡的其中一顆（2026-09-29 使用者要求：不要「圓圈裡一個
/// 加減號」那種圖示，改成膠囊裡分兩半點）。
/// YT 顯示設定（2026-10-12 使用者要求）：依影片顯示要不要抓冷藏頻道、
/// 頻道詳情頁的捲動條跟「回到最上面」。三個存成同一筆
/// [YtDisplayPrefs]，跨裝置同步。
/// 底部浮動分頁列（2026-10-14 使用者要求）：全 App 共用一條、各功能
/// 自己的、或不顯示。跨裝置同步。
class _NavBarModeCard extends ConsumerWidget {
  const _NavBarModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(navBarPrefsProvider);
    return SettingsRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '底部分頁列',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          Text(switch (prefs.mode) {
            NavBarMode.global => 'App 首頁、英文、日文跟 YT 都是同一條「英文／日文／YT」',
            NavBarMode.feature => '有自己分頁列的功能顯示自己的（YT：頻道／影片／播放清單），其他不顯示',
            NavBarMode.off => '都不顯示',
          }, style: AppText.note),
          const SizedBox(height: Gap.sm),
          SegmentedButton<NavBarMode>(
            segments: [
              for (final m in NavBarMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {prefs.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) async {
              final next = prefs.copyWith(mode: s.first);
              ref.read(navBarPrefsProvider.notifier).state = next;
              ref
                  .read(navBarPrefsProvider.notifier)
                  .state = await NavBarPrefsStore(
                ref.read(keyValueStoreProvider),
              ).save(next);
            },
          ),
        ],
      ),
    );
  }
}

class _YtDisplayPrefsRows extends ConsumerWidget {
  const _YtDisplayPrefsRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(ytDisplayPrefsProvider);

    Future<void> update(YtDisplayPrefs next) async {
      ref.read(ytDisplayPrefsProvider.notifier).state = next;
      final saved = await YtDisplayPrefsStore(
        ref.read(keyValueStoreProvider),
      ).save(next);
      ref.read(ytDisplayPrefsProvider.notifier).state = saved;
    }

    Widget row(
      IconData icon,
      String title,
      String note,
      bool value,
      ValueChanged<bool> onChanged,
    ) => SettingAnchor(
      id: 'yt:$title',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.ink2),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(note, style: AppText.note),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );

    return Column(
      children: [
        row(
          Icons.ac_unit_rounded,
          '依影片顯示也抓冷藏頻道',
          prefs.videoIncludeCold ? '冷藏頻道的影片也會混進來' : '冷藏頻道不抓，依頻道顯示照樣看得到',
          prefs.videoIncludeCold,
          (v) => update(prefs.copyWith(videoIncludeCold: v)),
        ),
        row(
          Icons.hourglass_empty_rounded,
          '依影片顯示也抓待評鑑頻道',
          prefs.videoIncludePending ? '還沒分區的頻道影片也會混進來' : '待評鑑頻道不抓，依頻道顯示照樣看得到',
          prefs.videoIncludePending,
          (v) => update(prefs.copyWith(videoIncludePending: v)),
        ),
        row(
          Icons.drag_handle_rounded,
          '頻道頁右側捲動條',
          '可以拖著快速捲到想看的影片',
          prefs.showScrollbar,
          (v) => update(prefs.copyWith(showScrollbar: v)),
        ),
        row(
          Icons.vertical_align_top_rounded,
          '頻道頁「回到最上面」按鈕',
          '影片滑下去以後右下角出現',
          prefs.showBackToTop,
          (v) => update(prefs.copyWith(showBackToTop: v)),
        ),
        row(
          Icons.cloud_download_outlined,
          '進頻道自動抓完全部影片',
          prefs.autoFillChannel ? '背景慢慢抓，往下滑、搜尋都很快；每個頻道只有第一次花配額' : '往下滑到哪才抓到哪',
          prefs.autoFillChannel,
          (v) => update(prefs.copyWith(autoFillChannel: v)),
        ),
        // 頻道頁搜尋（2026-10-14）：要不要照篩選。「也問 YouTube」那個開關
        // 2026-10-15 拿掉：搜尋一律只搜快取（使用者要求）。
        row(
          Icons.visibility_outlined,
          '搜尋時列出已看過、已隱藏',
          prefs.searchShowAll ? '不管「隱藏已看過／顯示已隱藏」，全部列出來' : '照「隱藏已看過／顯示已隱藏」篩',
          prefs.searchShowAll,
          (v) => update(prefs.copyWith(searchShowAll: v)),
        ),
        // 影片下架檢查多久一次（2026-10-12 使用者要求：設定可調、跨裝置同步）。
        SettingAnchor(
          id: 'yt.views',
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SettingIcon(),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '觀看次數更新',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        prefs.viewsRefreshDays <= 0
                            ? '不更新，只有新抓到的影片會帶觀看次數'
                            : '打開頻道時在背景重抓：一個月內的影片每次都抓，其他超過這麼久沒更新的才抓（50 部 1 點配額）',
                        style: AppText.note,
                      ),
                      const SizedBox(height: Gap.xs),
                      SegmentedButton<int>(
                        segments: [
                          for (final d in YtDisplayPrefs.viewsRefreshChoices)
                            ButtonSegment(
                              value: d,
                              label: Text(switch (d) {
                                0 => '不更新',
                                7 => '一週',
                                14 => '兩週',
                                30 => '一個月',
                                _ => '$d 天',
                              }),
                            ),
                        ],
                        selected: {prefs.viewsRefreshDays},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            update(prefs.copyWith(viewsRefreshDays: s.first)),
                        style: SegmentedButton.styleFrom(
                          backgroundColor: AppColors.glassFill,
                          foregroundColor: AppColors.ink2,
                          selectedBackgroundColor: AppColors.accentSolid
                              .withValues(alpha: 0.28),
                          selectedForegroundColor: AppColors.ink,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingAnchor(
          id: 'yt.removed',
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: const SettingIcon(),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '影片下架檢查',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        prefs.removedCheckDays <= 0
                            ? '不檢查，已下架的影片不會被標出來'
                            : '打開頻道時，超過這麼久沒查就問 YouTube 哪些影片被刪或改私人',
                        style: AppText.note,
                      ),
                      const SizedBox(height: Gap.xs),
                      SegmentedButton<int>(
                        segments: [
                          for (final d in YtDisplayPrefs.removedCheckChoices)
                            ButtonSegment(
                              value: d,
                              label: Text(switch (d) {
                                0 => '不檢查',
                                7 => '一週',
                                14 => '兩週',
                                30 => '一個月',
                                _ => '$d 天',
                              }),
                            ),
                        ],
                        selected: {prefs.removedCheckDays},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            update(prefs.copyWith(removedCheckDays: s.first)),
                        style: SegmentedButton.styleFrom(
                          backgroundColor: AppColors.glassFill,
                          foregroundColor: AppColors.ink2,
                          selectedBackgroundColor: AppColors.accentSolid
                              .withValues(alpha: 0.28),
                          selectedForegroundColor: AppColors.ink,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 點影片要內嵌播放還是開新分頁（2026-09-30 使用者要求：預設內嵌，
/// 設定頁能切回開新分頁）。
class _VideoOpenModeRow extends ConsumerWidget {
  const _VideoOpenModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ytVideoOpenModeProvider);

    Future<void> setMode(YtVideoOpenMode value) async {
      ref.read(ytVideoOpenModeProvider.notifier).state = value;
      await YtVideoOpenModeStore(ref.read(keyValueStoreProvider)).save(value);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: const SettingIcon(),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '點影片時',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                mode == YtVideoOpenMode.embedded
                    ? '在 App 裡直接播放（可另外按鈕跳去 YouTube）'
                    : '開新分頁去 YouTube',
                style: AppText.note,
              ),
              const SizedBox(height: Gap.xs),
              SegmentedButton<YtVideoOpenMode>(
                segments: const [
                  ButtonSegment(
                    value: YtVideoOpenMode.embedded,
                    label: Text('內嵌播放'),
                  ),
                  ButtonSegment(
                    value: YtVideoOpenMode.external,
                    label: Text('開新分頁'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setMode(s.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.glassFill,
                  foregroundColor: AppColors.ink2,
                  selectedBackgroundColor: AppColors.accentSolid.withValues(
                    alpha: 0.28,
                  ),
                  selectedForegroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.glassEdge),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 內嵌播放器要用哪種外層呈現方式（2026-09-30 使用者要求：正中央
/// Dialog、下滑收合式、可拖曳浮動視窗三種都留著讓使用者切，預設用
/// 浮動視窗，見 [YtEmbedPlayerStyle]）。只有點影片選「內嵌播放」時
/// 這個設定才有意義，開新分頁模式不會用到任何一種呈現方式，所以只在
/// [_VideoOpenModeRow] 選了內嵌播放時才顯示這一列。
class _EmbedPlayerStyleRow extends ConsumerWidget {
  const _EmbedPlayerStyleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openMode = ref.watch(ytVideoOpenModeProvider);
    if (openMode != YtVideoOpenMode.embedded) return const SizedBox.shrink();
    final style = ref.watch(ytEmbedPlayerStyleProvider);

    Future<void> setStyle(YtEmbedPlayerStyle value) async {
      ref.read(ytEmbedPlayerStyleProvider.notifier).state = value;
      await YtEmbedPlayerStyleStore(
        ref.read(keyValueStoreProvider),
      ).save(value);
    }

    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: const SettingIcon(),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '內嵌播放器樣式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(switch (style) {
                  YtEmbedPlayerStyle.floating => '可拖曳、可收合成小泡泡的浮動視窗',
                  YtEmbedPlayerStyle.bottomSheet => '從下方滑出，只佔下半螢幕',
                  YtEmbedPlayerStyle.centeredDialog => '正中央彈窗，整頁變暗',
                }, style: AppText.note),
                const SizedBox(height: Gap.xs),
                SegmentedButton<YtEmbedPlayerStyle>(
                  segments: const [
                    ButtonSegment(
                      value: YtEmbedPlayerStyle.floating,
                      label: Text('浮動視窗'),
                    ),
                    ButtonSegment(
                      value: YtEmbedPlayerStyle.bottomSheet,
                      label: Text('下滑收合'),
                    ),
                    ButtonSegment(
                      value: YtEmbedPlayerStyle.centeredDialog,
                      label: Text('正中彈窗'),
                    ),
                  ],
                  selected: {style},
                  onSelectionChanged: (s) => setStyle(s.first),
                  style: SegmentedButton.styleFrom(
                    backgroundColor: AppColors.glassFill,
                    foregroundColor: AppColors.ink2,
                    selectedBackgroundColor: AppColors.accentSolid.withValues(
                      alpha: 0.28,
                    ),
                    selectedForegroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.glassEdge),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 30,
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? AppColors.ink2
              : AppColors.ink3.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _VideoTabChannelRow extends ConsumerWidget {
  const _VideoTabChannelRow({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: channelId.isEmpty
          ? Future.value(null)
          : ref.read(ytTrackerRepositoryProvider).loadChannels().then((cs) {
              for (final c in cs) {
                if (c.id == channelId) return c;
              }
              return null;
            }),
      builder: (context, snap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const SettingIcon(),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '底部分頁列「影片」開的頻道',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    channelId.isEmpty
                        ? '還沒選，點「影片」時會先問'
                        : snap.data?.name ?? '（頻道不在了）',
                    style: AppText.note,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => pickVideoTabChannel(context, ref),
              child: const Text('選擇'),
            ),
          ],
        ),
      ),
    );
  }
}
