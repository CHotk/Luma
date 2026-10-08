import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'sync_log_row.dart';

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

  /// 主畫面最多顯示 10 筆，其他從右上角「同步紀錄」按鈕進全部紀錄頁看
  /// （2026-10-08 使用者要求；原本是往下滑一直多載，主畫面會越拉越長）。
  static const _logPreview = 10;

  @override
  void initState() {
    super.initState();
    _reloadLog();
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
      final data = await R2SyncService(client).fetchBackupZip();
      final filename = 'lume-backup-${_backupTodayStamp()}.zip';
      final ok = saveBytesFile(filename, data.zip, 'application/zip');
      await ref
          .read(syncLogRepositoryProvider)
          .add(
            SyncLogEntry(
              at: DateTime.now(),
              action: SyncLogAction.backup,
              success: ok,
              device: currentDeviceLabel(),
              detail: ok
                  ? '雲端 ${data.fileCount} 個檔案全部打包、'
                        '${(data.totalBytes / 1024).toStringAsFixed(0)} KB'
                  : '這個平台還不支援下載',
            ),
          );
      await _reloadLog();
      if (!mounted) return;
      setState(() => _downloading = false);
      showAppNotice(context, ok ? '已下載 $filename' : '這個平台還不支援下載', isError: !ok);
    } catch (e, stack) {
      AppLog.add('[備份] 下載失敗：$e\n$stack', isError: true);
      await ref
          .read(syncLogRepositoryProvider)
          .add(
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
                  titleIcon: Icons.cloud_sync_outlined,
                  showBack: false,
                  // 按鈕大小、間距跟交易&自律等其他功能一致（2026-10-08
                  // 使用者回報這裡太擠）。
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/sync/log'),
                      icon: const Icon(Icons.receipt_long_outlined, size: 22),
                      color: AppColors.ink2,
                      tooltip: '全部同步紀錄',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
                      ),
                    ),
                    IconButton(
                      onPressed: _downloading ? null : _downloadBackup,
                      icon: _downloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined, size: 22),
                      color: AppColors.ink2,
                      tooltip: '備份雲端資料到本機',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: SingleChildScrollView(
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '同步紀錄',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            Text(
              _log.length > _logPreview
                  ? '最近 $_logPreview 筆・共 ${_log.length} 筆'
                  : '共 ${_log.length} 筆',
              style: AppText.note,
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        if (_log.isEmpty)
          Text('還沒有同步或備份紀錄', style: AppText.bodyDim)
        else
          for (final entry in _log.take(_logPreview)) SyncLogRow(entry: entry),
        if (_log.length > _logPreview)
          TextButton(
            onPressed: () => context.push('/sync/log'),
            child: Text('看全部 ${_log.length} 筆紀錄 ›'),
          ),
      ],
    );
  }
}

String _backupTodayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
}
