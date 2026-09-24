import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/cloud/r2_client.dart';
import '../../data/cloud/r2_credentials_store.dart';
import '../../data/cloud/r2_sync_service.dart';
import '../../data/export/device_label.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../shared/debug/app_log.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/glass_card.dart';

const _lastSyncedKey = 'r2_sync.last_synced_at.v1';

enum _Phase { idle, testing, success, error }

/// 「各功能同步狀況」卡片裡，單一功能目前跑到哪一步（2026-09-23
/// 使用者要求：同步頁要看得出目前是哪個功能在下載還是上傳，不是只有
/// 一顆「立即同步」按鈕看不出進度）。日記、健身都用同一組狀態，之後
/// 每加一個功能的同步，這個卡片就多加一行。
enum _FeaturePhase { idle, downloading, uploading, done, error }

/// 設定頁「多裝置同步」區塊，照設計稿
/// `design-history/雲端同步設計/01_簡潔卡片式.html` 做：沒設定過就是
/// 輸入卡片（Account ID／Access Key ID／Secret Access Key 三欄＋
/// 「儲存並測試連線」），設定完成後換成「已連接雲端」狀態卡＋「立即
/// 同步」——第一階段（打地基）「立即同步」只做下載，還沒有上傳
/// （2026-09-23 使用者決定分階段開發，先驗證連線/簽章/資料格式）。
class R2SyncSection extends ConsumerStatefulWidget {
  const R2SyncSection({super.key, this.onLogged});

  /// 每次同步結束（不管成功失敗）寫完 [SyncLogEntry] 之後呼叫一次，讓
  /// 外層（`sync_page.dart`）知道要重讀同步紀錄卡的列表——同步紀錄的
  /// 儲存跟顯示分屬不同 widget，用這個回呼串起來，不用共用 provider
  /// 硬湊（2026-09-24）。
  final VoidCallback? onLogged;

  @override
  ConsumerState<R2SyncSection> createState() => _R2SyncSectionState();
}

class _R2SyncSectionState extends ConsumerState<R2SyncSection> {
  final _endpointController = TextEditingController();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();

  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  DateTime? _lastSyncedAt;
  bool _syncing = false;
  _FeaturePhase _diaryPhase = _FeaturePhase.idle;
  _FeaturePhase _fitnessPhase = _FeaturePhase.idle;
  _FeaturePhase _ytPhase = _FeaturePhase.idle;
  _FeaturePhase _kanaPracticePhase = _FeaturePhase.idle;
  _FeaturePhase _kanaExamPhase = _FeaturePhase.idle;
  _FeaturePhase _englishPhase = _FeaturePhase.idle;
  _FeaturePhase _syncLogPhase = _FeaturePhase.idle;
  _FeaturePhase _errorLogPhase = _FeaturePhase.idle;

  /// 各功能這次同步的上傳／下載筆數，顯示在「各功能同步狀況」每一列
  /// 右邊（2026-09-24 使用者要求：各功能同步狀況也要看得到結果）。
  final Map<String, String> _results = {};

  void _record(String label, ({int downloaded, int uploaded}) r) {
    if (!mounted) return;
    setState(() => _results[label] = '↑${r.uploaded} ↓${r.downloaded}');
  }

  @override
  void initState() {
    super.initState();
    _loadLastSyncedAt();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSyncedAt() async {
    final raw = await ref.read(keyValueStoreProvider).read(_lastSyncedKey);
    if (raw != null && mounted) {
      setState(() => _lastSyncedAt = DateTime.tryParse(raw));
    }
  }

  Future<void> _saveAndTestConnection() async {
    final endpoint = _endpointController.text.trim();
    final accessKey = _accessKeyController.text.trim();
    final secretKey = _secretKeyController.text.trim();
    if (endpoint.isEmpty || accessKey.isEmpty || secretKey.isEmpty) return;

    setState(() {
      _phase = _Phase.testing;
      _errorMessage = null;
    });

    final credentials = R2Credentials(
      endpoint: endpoint,
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
    );
    try {
      final client = R2Client(
        credentials: credentials,
        bucket: ref.read(r2BucketNameProvider),
      );
      await R2SyncService(client).testConnection();
      final store = ref.read(keyValueStoreProvider);
      await R2CredentialsStore(store).save(credentials);
      ref.read(r2CredentialsProvider.notifier).state = credentials;
      if (!mounted) return;
      setState(() => _phase = _Phase.success);
      // 成功打勾停留一下再自動切到「已連接」畫面，跟設計稿一致，不要
      // 一測完馬上跳走，使用者才看得到「有成功」這個回饋。
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = '$e';
      });
    }
  }

  Future<void> _clearCredentials() async {
    final store = ref.read(keyValueStoreProvider);
    await R2CredentialsStore(store).clear();
    ref.read(r2CredentialsProvider.notifier).state = null;
    _endpointController.clear();
    _accessKeyController.clear();
    _secretKeyController.clear();
  }

  /// 給單一功能用的 [SyncPhase] → [_FeaturePhase] 轉接，[onUpdate] 是
  /// 對應功能自己的 setState 賦值——日記、健身各自呼叫一次
  /// [R2SyncService] 的 `syncXxx`，用這個共用轉接省得兩邊各寫一份幾乎
  /// 一樣的 callback。
  void Function(SyncPhase) _phaseCallback(void Function(_FeaturePhase) onUpdate) {
    return (phase) {
      if (!mounted) return;
      setState(() {
        onUpdate(switch (phase) {
          SyncPhase.downloading => _FeaturePhase.downloading,
          SyncPhase.uploading => _FeaturePhase.uploading,
        });
      });
    };
  }

  Future<void> _syncNow() async {
    final credentials = ref.read(r2CredentialsProvider);
    if (credentials == null || _syncing) return;
    // 目前跑到哪個功能，失敗時要能講出是哪一個出的錯。
    var stage = '日記';
    setState(() {
      _syncing = true;
      _diaryPhase = _FeaturePhase.downloading;
      _fitnessPhase = _FeaturePhase.idle;
      _ytPhase = _FeaturePhase.idle;
      _kanaPracticePhase = _FeaturePhase.idle;
      _kanaExamPhase = _FeaturePhase.idle;
      _englishPhase = _FeaturePhase.idle;
      _syncLogPhase = _FeaturePhase.idle;
      _errorLogPhase = _FeaturePhase.idle;
      _results.clear();
    });
    try {
      final client = R2Client(
        credentials: credentials,
        bucket: ref.read(r2BucketNameProvider),
      );
      final service = R2SyncService(client);
      // 日記、健身依序同步，不是同時打——避免兩邊同時搶著寫 R2 造成
      // 混亂的請求時序，個人手動按同步的使用情境對速度沒有要求。
      // 每個功能自己一結束就馬上標記完成，不是等兩個都做完才一起標記
      // ——不然萬一健身那邊失敗，明明已經同步好的日記那一行也會卡在
      // 「上傳中…」，看起來像日記也失敗了。
      // 上傳／下載各異動幾筆不再塞進通知（太長，2026-09-24 使用者
      // 要求），但同步紀錄 log 還是要留這個細節，所以結果還是要接住。
      stage = '日記';
      final diaryResult = await service.syncDiary(
        ref.read(diaryRepositoryProvider),
        onPhase: _phaseCallback((p) => _diaryPhase = p),
      );
      _record('日記', diaryResult);
      if (mounted) setState(() => _diaryPhase = _FeaturePhase.done);

      stage = '健身';
      final fitnessResult = await service.syncFitness(
        ref.read(fitnessRepositoryProvider),
        onPhase: _phaseCallback((p) => _fitnessPhase = p),
      );
      _record('健身', fitnessResult);
      if (mounted) setState(() => _fitnessPhase = _FeaturePhase.done);

      stage = 'YT 頻道／分類';
      final ytResult = await service.syncYtTracker(
        ref.read(ytTrackerRepositoryProvider),
        onPhase: _phaseCallback((p) => _ytPhase = p),
      );
      // 頻道詳情頁上傳頻率圖用的歷史影片快取，每個頻道一份，跟著一起同步。
      stage = 'YT 影片快取';
      final ytVideoResult = await service.syncYtVideoCache(
        YtVideoCacheStore(ref.read(keyValueStoreProvider)),
        await ref.read(ytTrackerRepositoryProvider).loadChannels(),
      );
      _record('YT 頻道追蹤', (
        downloaded: ytResult.downloaded + ytVideoResult.downloaded,
        uploaded: ytResult.uploaded + ytVideoResult.uploaded,
      ));
      if (mounted) setState(() => _ytPhase = _FeaturePhase.done);

      stage = '五十音練習';
      final kanaPracticeResult = await service.syncKanaPractice(
        ref.read(kanaPracticeRepositoryProvider),
        onPhase: _phaseCallback((p) => _kanaPracticePhase = p),
      );
      _record('五十音練習', kanaPracticeResult);
      if (mounted) setState(() => _kanaPracticePhase = _FeaturePhase.done);

      stage = '五十音考試';
      final kanaExamResult = await service.syncKanaExam(
        ref.read(kanaExamRepositoryProvider),
        onPhase: _phaseCallback((p) => _kanaExamPhase = p),
      );
      _record('五十音考試', kanaExamResult);
      if (mounted) setState(() => _kanaExamPhase = _FeaturePhase.done);

      stage = '英文單字紀錄';
      final englishResult = await service.syncEnglishHistory(
        ref.read(historyRepositoryProvider),
        onPhase: _phaseCallback((p) => _englishPhase = p),
      );
      // 單字庫有記憶體快取（對錯次數是從紀錄現算的），紀錄變了要丟掉重算。
      ref.read(wordRepositoryProvider).invalidate();
      _record('英文單字紀錄', englishResult);
      if (mounted) setState(() => _englishPhase = _FeaturePhase.done);

      final now = DateTime.now();
      await ref
          .read(keyValueStoreProvider)
          .write(_lastSyncedKey, now.toIso8601String());
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: now,
          action: SyncLogAction.sync,
          success: true,
          device: currentDeviceLabel(),
          detail:
              '日記 上傳${diaryResult.uploaded}／下載${diaryResult.downloaded}；'
              '健身 上傳${fitnessResult.uploaded}／下載${fitnessResult.downloaded}；'
              'YT頻道 上傳${ytResult.uploaded}／下載${ytResult.downloaded}；'
              'YT影片快取 上傳${ytVideoResult.uploaded}／下載${ytVideoResult.downloaded}；'
              '五十音練習 上傳${kanaPracticeResult.uploaded}／下載${kanaPracticeResult.downloaded}；'
              '五十音考試 上傳${kanaExamResult.uploaded}／下載${kanaExamResult.downloaded}；'
              '英文單字紀錄 上傳${englishResult.uploaded}／下載${englishResult.downloaded}',
        ),
      );
      stage = '同步紀錄／錯誤日誌';
      try {
        if (mounted) setState(() => _syncLogPhase = _FeaturePhase.downloading);
        final logDownloaded = await service.syncLog(
          ref.read(syncLogRepositoryProvider),
        );
        if (mounted) {
          setState(() {
            _syncLogPhase = _FeaturePhase.done;
            _results['同步紀錄'] = '↓$logDownloaded';
            _errorLogPhase = _FeaturePhase.downloading;
          });
        }
        final errorRepo = ref.read(errorLogRepositoryProvider);
        final errDownloaded = await service.syncErrorLog(errorRepo);
        if (mounted) {
          setState(() {
            _errorLogPhase = _FeaturePhase.done;
            _results['除錯錯誤日誌'] = '↓$errDownloaded';
          });
        }
        AppLog.restore(await errorRepo.loadAll());
      } catch (_) {
        // 紀錄上傳失敗不擋主流程：日記／健身已經同步成功。
      }
      widget.onLogged?.call();
      // 同步抓回來的資料要讓日記頁／健身頁（可能還留在導覽堆疊底下沒被
      // 重建）知道要重讀，不然使用者按返回時畫面還是同步前的舊資料
      // （2026-09-23 使用者回報）——跟練習紀錄頁那套「存檔完 bump 這個
      // provider」共用同一個機制，見 `dataRevisionProvider` 的其他用法。
      ref.read(dataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() {
        _lastSyncedAt = now;
        _syncing = false;
      });
      showAppNotice(context, '資料雲端同步完成');
    } catch (e, stack) {
      // 同步失敗要寫進除錯訊息（原本只跳通知，除錯頁是空的，2026-09-24
      // 使用者回報），連堆疊一起，才查得出是哪一步、為什麼。
      AppLog.add('[同步] $stage 失敗：$e\n$stack', isError: true);
      await ref.read(syncLogRepositoryProvider).add(
        SyncLogEntry(
          at: DateTime.now(),
          action: SyncLogAction.sync,
          success: false,
          device: currentDeviceLabel(),
          detail: '$stage：$e',
        ),
      );
      widget.onLogged?.call();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        if (_diaryPhase == _FeaturePhase.downloading || _diaryPhase == _FeaturePhase.uploading) {
          _diaryPhase = _FeaturePhase.error;
        }
        if (_fitnessPhase == _FeaturePhase.downloading || _fitnessPhase == _FeaturePhase.uploading) {
          _fitnessPhase = _FeaturePhase.error;
        }
      });
      showAppNotice(context, '同步失敗（$stage）：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credentials = ref.watch(r2CredentialsProvider);
    if (credentials == null) {
      return GlassCard(child: _buildInputCard());
    }
    // 「各功能同步狀況」卡片只有連上雲端之後才有意義顯示，跟輸入卡片
    // 分開放（2026-09-23 使用者要求：頁面底下再加一張卡片顯示同步
    // 進度）。
    return Column(
      children: [
        GlassCard(child: _buildConnectedCard(credentials)),
        const SizedBox(height: Gap.sm),
        GlassCard(child: _buildStatusCard()),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '各功能同步狀況',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: Gap.sm),
        _FeatureStatusRow(label: '日記', phase: _diaryPhase, result: _results['日記']),
        _FeatureStatusRow(label: '健身', phase: _fitnessPhase, result: _results['健身']),
        _FeatureStatusRow(label: 'YT 頻道追蹤', phase: _ytPhase, result: _results['YT 頻道追蹤']),
        _FeatureStatusRow(label: '五十音練習', phase: _kanaPracticePhase, result: _results['五十音練習']),
        _FeatureStatusRow(label: '五十音考試', phase: _kanaExamPhase, result: _results['五十音考試']),
        _FeatureStatusRow(label: '英文單字紀錄', phase: _englishPhase, result: _results['英文單字紀錄']),
        // 同步紀錄、錯誤日誌本身也是要同步的資料，一樣列出來
        // （2026-09-24 使用者要求）。
        _FeatureStatusRow(label: '同步紀錄', phase: _syncLogPhase, result: _results['同步紀錄']),
        _FeatureStatusRow(label: '除錯錯誤日誌', phase: _errorLogPhase, result: _results['除錯錯誤日誌']),
      ],
    );
  }

  Widget _buildInputCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(
          label: 'Account ID / S3 API 網址',
          controller: _endpointController,
          hint: 'https://xxxxxxxx.r2.cloudflarestorage.com',
        ),
        _Field(
          label: 'Access Key ID',
          controller: _accessKeyController,
          hint: '貼上 Access Key ID',
        ),
        _Field(
          label: 'Secret Access Key',
          controller: _secretKeyController,
          hint: '貼上 Secret Access Key',
          obscure: true,
          hintNote: '只存在這台裝置的瀏覽器裡，不會進 Git、也不會顯示在畫面上。',
        ),
        const SizedBox(height: Gap.xs),
        _buildActionButton(),
        if (_phase == _Phase.error && _errorMessage != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 10.5, color: AppColors.bad),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton() {
    switch (_phase) {
      case _Phase.testing:
        return _StaticButton(
          color: AppColors.glassFill,
          textColor: AppColors.ink2,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('連線測試中…'),
            ],
          ),
        );
      case _Phase.success:
        return _StaticButton(
          color: AppColors.ok,
          textColor: const Color(0xFF062B16),
          child: const Text('✓ 連線成功'),
        );
      case _Phase.error:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _saveAndTestConnection,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bad,
              side: const BorderSide(color: AppColors.bad),
            ),
            child: const Text('連線失敗，再試一次'),
          ),
        );
      case _Phase.idle:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saveAndTestConnection,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bgDeep,
            ),
            child: const Text('儲存並測試連線'),
          ),
        );
    }
  }

  Widget _buildConnectedCard(R2Credentials credentials) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 8, color: AppColors.ok),
            const SizedBox(width: Gap.xs),
            const Text(
              '已連接雲端',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const Spacer(),
            TextButton(
              onPressed: _clearCredentials,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.bad,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
              ),
              child: const Text('取消連接', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        Text(
          _lastSyncedAt == null ? '還沒同步過' : '上次同步：${_relativeTime(_lastSyncedAt!)}',
          style: AppText.note,
        ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _syncing ? null : _syncNow,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bgDeep,
            ),
            child: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('立即同步'),
          ),
        ),
      ],
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.hintNote,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final String? hintNote;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: AppText.note),
          const SizedBox(height: 4),
          TextField(
            controller: widget.controller,
            obscureText: _obscured,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: widget.obscure
                  ? IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      color: AppColors.ink3,
                    )
                  : null,
            ),
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
          if (widget.hintNote != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.hintNote!,
              style: const TextStyle(fontSize: 9.5, color: AppColors.ink3, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// 同步狀況卡片裡的一行：功能名稱＋目前狀態（閒置／下載中／上傳中／
/// 完成打勾／失敗）。
class _FeatureStatusRow extends StatelessWidget {
  const _FeatureStatusRow({
    required this.label,
    required this.phase,
    this.result,
  });

  final String label;
  final _FeaturePhase phase;

  /// 這次同步的結果（↑上傳 ↓下載筆數），沒有就不顯示。
  final String? result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (result != null && phase == _FeaturePhase.done) ...[
            Text(
              result!,
              style: const TextStyle(fontSize: 11, color: AppColors.ink2),
            ),
            const SizedBox(width: 8),
          ],
          _buildStatus(),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    switch (phase) {
      case _FeaturePhase.idle:
        return const Text('待同步', style: TextStyle(fontSize: 11, color: AppColors.ink3));
      case _FeaturePhase.downloading:
        return const _StatusSpinnerLabel(label: '下載中…');
      case _FeaturePhase.uploading:
        return const _StatusSpinnerLabel(label: '上傳中…');
      case _FeaturePhase.done:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: AppColors.ok),
            SizedBox(width: 4),
            Text('完成', style: TextStyle(fontSize: 11, color: AppColors.ok)),
          ],
        );
      case _FeaturePhase.error:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: AppColors.bad),
            SizedBox(width: 4),
            Text('失敗', style: TextStyle(fontSize: 11, color: AppColors.bad)),
          ],
        );
    }
  }
}

class _StatusSpinnerLabel extends StatelessWidget {
  const _StatusSpinnerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.accent),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
      ],
    );
  }
}

class _StaticButton extends StatelessWidget {
  const _StaticButton({
    required this.color,
    required this.textColor,
    required this.child,
  });

  final Color color;
  final Color textColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor),
        child: Center(child: child),
      ),
    );
  }
}
