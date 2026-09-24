import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/cloud/r2_client.dart';
import '../../data/cloud/r2_sync_service.dart';
import '../../data/export/file_download.dart';
import '../../domain/models/sync_log_entry.dart';
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
      final data = await R2SyncService(client).fetchBackupJson();
      final filename = 'lume-backup-${_backupTodayStamp()}.json';
      final ok = saveTextFile(filename, data.json);
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: DateTime.now(),
          action: SyncLogAction.backup,
          success: ok,
          detail: ok
              ? '日記 ${data.diaryCount} 筆、健身 ${data.fitnessCount} 筆'
              : '這個平台還不支援下載',
        ),
      );
      await _reloadLog();
      if (!mounted) return;
      setState(() => _downloading = false);
      showAppNotice(context, ok ? '已下載 $filename' : '這個平台還不支援下載', isError: !ok);
    } catch (e) {
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: DateTime.now(),
          action: SyncLogAction.backup,
          success: false,
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
            if (_log.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await ref.read(syncLogRepositoryProvider).clear();
                  await _reloadLog();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink3,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                ),
                child: const Text('清空', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        if (_log.isEmpty)
          Text('還沒有同步或備份紀錄', style: AppText.bodyDim)
        else
          for (final entry in _log) _SyncLogRow(entry: entry),
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

class _SyncLogRow extends StatelessWidget {
  const _SyncLogRow({required this.entry});

  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.success ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: entry.success ? AppColors.ok : AppColors.bad,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.action.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_relativeTime(entry.at), style: AppText.note),
                  ],
                ),
                if (entry.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      color: entry.success ? AppColors.ink3 : AppColors.bad,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
