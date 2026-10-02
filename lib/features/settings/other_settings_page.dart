import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/diary_password_store.dart';
import '../../data/repositories/yt_embed_player_style_store.dart';
import '../../data/repositories/yt_stats_refresh_setting_store.dart';
import '../../data/repositories/yt_video_open_mode_store.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../yt_tracker/yt_api_key_dialog.dart';
import '../yt_tracker/yt_tracker_browse_page.dart'
    show refreshYtSubscriberStats;
import '../yt_tracker/yt_tracker_home_page.dart' show showYtExportDialog;

/// 英文學習以外的功能（日記、健身、YT、日文…）點齒輪來到的設定頁。
/// [fromLocation] 是點齒輪那一刻所在的路徑（見 `open_settings.dart`），
/// 用來決定要顯示哪個功能專屬的設定項目——目前只有 YT 頻道追蹤有
/// （API 金鑰、匯出分類／頻道，2026-09-29 使用者要求從頂部列的按鈕
/// 移進齒輪，原本那排按鈕太擠），其他功能還沒有設定項目就照舊留白。
class OtherSettingsPage extends ConsumerWidget {
  const OtherSettingsPage({super.key, this.fromLocation});

  final String? fromLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isYtTracker = fromLocation?.startsWith('/yt-tracker') ?? false;
    final isDiary = fromLocation?.startsWith('/diary') ?? false;
    // 訂閱人數更新頻率調了但還沒按儲存，按上一頁要提醒（2026-09-29
    // 使用者要求），不然改動白調了。只有在 YT 設定頁才需要看這個旗標。
    final hasUnsaved = isYtTracker && ref.watch(ytStatsRefreshDirtyProvider);
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.sm),
                  const AppTopBar(title: '設定', showSettings: false),
                  const SizedBox(height: Gap.md),
                  Expanded(
                    child: isYtTracker
                        ? const _YtTrackerSettings()
                        : isDiary
                        ? const _DiarySettings()
                        : Center(
                            child: Text('這個功能還沒有設定項目', style: AppText.bodyDim),
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

class _YtTrackerSettings extends ConsumerWidget {
  const _YtTrackerSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = (ref.watch(ytApiKeyProvider) ?? '').isNotEmpty;
    return ListView(
      children: [
        Text('YT 頻道追蹤', style: AppText.note),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasKey ? Icons.vpn_key : Icons.vpn_key_outlined,
                    size: 18,
                    color: hasKey ? AppColors.ok : AppColors.ink2,
                  ),
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
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              Row(
                children: [
                  const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: AppColors.ink2,
                  ),
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
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              Row(
                children: [
                  const Icon(
                    Icons.reorder_rounded,
                    size: 18,
                    color: AppColors.ink2,
                  ),
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
                    onPressed: () => context.push('/yt-tracker/category-order'),
                    child: const Text('調整'),
                  ),
                ],
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const _StatsRefreshRow(),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              const _VideoOpenModeRow(),
              const _EmbedPlayerStyleRow(),
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
class _DiarySettings extends ConsumerWidget {
  const _DiarySettings();

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('變更日記密碼', style: TextStyle(color: AppColors.ink)),
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
    showAppNotice(context, '已更新日記密碼');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        Text('日記', style: AppText.note),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.ink2,
              ),
              const SizedBox(width: Gap.sm),
              const Expanded(
                child: Text(
                  '日記密碼',
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
      ],
    );
  }
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
          child: Icon(Icons.groups_outlined, size: 18, color: AppColors.ink2),
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
          child: Icon(
            Icons.smart_display_outlined,
            size: 18,
            color: AppColors.ink2,
          ),
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
            child: Icon(
              Icons.picture_in_picture_alt_outlined,
              size: 18,
              color: AppColors.ink2,
            ),
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
