import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/cloud/r2_client.dart';
import '../../data/cloud/r2_sync_service.dart';
import '../../data/export/device_label.dart';
import '../../data/export/file_download.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../settings/r2_sync_section.dart';

/// 多裝置同步，獨立成一個功能頁面，不是塞在「設定」頁裡的一個區塊
/// ——2026-09-23 使用者要求：這個功能夠獨立、之後會一直擴充（日記
/// 之外的功能陸續加進來），該有自己的入口，不該埋在設定頁一堆規則
/// 選項中間。選單裡排在「除錯」正上方，跟 `debug_log_page.dart` 同一種
/// 「大功能首頁」處理方式（`showBack: false`，靠側邊選單導航進來，不
/// 是子頁面鑽進來的）。
///
/// 右上角「備份雲端資料」按鈕（2026-09-24 使用者要求）：把 R2 上目前
/// 每個功能的資料整包抓下來存成一份 JSON 檔，純讀不寫，方便使用者
/// 自己另外備份，跟「立即同步」（會寫回本機、寫回雲端）是兩件事。
/// 這個按鈕跟「立即同步」都會各自留一筆紀錄在下面的「同步紀錄」卡片
/// 裡（見 [SyncLogEntry] 的說明）。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  List<SyncLogEntry> _log = const [];
  bool _downloading = false;

  /// 同步紀錄一次只顯示 10 筆，往下滑到底附近才多顯示下一個 10 筆
  /// （2026-09-24 使用者要求）。
  static const _logPageSize = 10;
  int _visibleLogCount = _logPageSize;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reloadLog();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
        _visibleLogCount < _log.length) {
      setState(() => _visibleLogCount += _logPageSize);
    }
  }

  Future<void> _reloadLog() async {
    final log = await ref.read(syncLogRepositoryProvider).loadAll();
    if (mounted) setState(() => _log = log);
  }

  Future<void> _downloadBackup() async {
    final credentials = ref.read(r2CredentialsProvider);
    if (credentials == null) {
      showAppNotice(context, '請先連接雲端才能備份', isError: true);
      return;
    }
    setState(() => _downloading = true);
    try {
      final client = R2Client(
        credentials: credentials,
        bucket: ref.read(r2BucketNameProvider),
      );
      final data = await R2SyncService(client).fetchBackupJson();
      final filename = 'lume-backup-${_backupTodayStamp()}.json';
      final ok = saveTextFile(filename, data.json);
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: DateTime.now(),
          action: SyncLogAction.backup,
          success: ok,
          device: currentDeviceLabel(),
          detail: ok
              ? '日記 ${data.diaryCount} 筆、健身 ${data.fitnessCount} 筆、YT 頻道 ${data.ytCount} 個'
              : '這個平台還不支援下載',
        ),
      );
      await _reloadLog();
      if (!mounted) return;
      setState(() => _downloading = false);
      showAppNotice(context, ok ? '已下載 $filename' : '這個平台還不支援下載', isError: !ok);
    } catch (e, stack) {
      AppLog.add('[備份] 下載失敗：$e\n$stack', isError: true);
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: DateTime.now(),
          action: SyncLogAction.backup,
          success: false,
          device: currentDeviceLabel(),
          detail: '$e',
        ),
      );
      await _reloadLog();
      if (!mounted) return;
      setState(() => _downloading = false);
      showAppNotice(context, '備份下載失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  title: '多裝置同步',
                  showBack: false,
                  actions: [
                    IconButton(
                      onPressed: _downloading ? null : _downloadBackup,
                      icon: _downloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined, size: 20),
                      color: AppColors.ink2,
                      tooltip: '備份雲端資料到本機',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        R2SyncSection(onLogged: _reloadLog),
                        const SizedBox(height: Gap.sm),
                        GlassCard(child: _buildLogCard()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '同步紀錄',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const Spacer(),
            Text('共 ${_log.length} 筆', style: AppText.note),
          ],
        ),
        const SizedBox(height: Gap.sm),
        if (_log.isEmpty)
          Text('還沒有同步或備份紀錄', style: AppText.bodyDim)
        else
          for (final entry in _log.take(_visibleLogCount))
            _SyncLogRow(entry: entry),
        if (_log.length > _visibleLogCount)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Center(
              child: Text('往下滑載入更多', style: AppText.note),
            ),
          ),
      ],
    );
  }
}

String _backupTodayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

String _absoluteTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// detail 是「；」分功能、「、」分項目的一整串文字（見 r2_sync_section
/// 跟備份下載寫入的格式），畫面上拆成一項一行才不會全擠在同一行。
List<String> _detailLines(String detail) => detail
    .split(RegExp('[；、]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

class _SyncLogRow extends StatelessWidget {
  const _SyncLogRow({required this.entry});

  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.success ? AppColors.ok : AppColors.bad;
    final lines = entry.detail == null ? const <String>[] : _detailLines(entry.detail!);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.success ? Icons.check_circle : Icons.error_outline,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                '${entry.action.label}${entry.success ? '' : '失敗'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(_relativeTime(entry.at), style: AppText.note),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 21),
            child: Text(
              '${_absoluteTime(entry.at)}  ·  ${entry.device ?? '未知裝置'}',
              style: AppText.note,
            ),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: entry.success ? AppColors.ink2 : AppColors.bad,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
