import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/cloud/r2_client.dart';
import '../../data/cloud/r2_credentials_store.dart';
import '../../data/cloud/r2_sync_service.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/glass_card.dart';

const _lastSyncedKey = 'r2_sync.last_synced_at.v1';

enum _Phase { idle, testing, success, error }

/// 設定頁「多裝置同步」區塊，照設計稿
/// `design-history/雲端同步設計/01_簡潔卡片式.html` 做：沒設定過就是
/// 輸入卡片（Account ID／Access Key ID／Secret Access Key 三欄＋
/// 「儲存並測試連線」），設定完成後換成「已連接雲端」狀態卡＋「立即
/// 同步」——第一階段（打地基）「立即同步」只做下載，還沒有上傳
/// （2026-09-23 使用者決定分階段開發，先驗證連線/簽章/資料格式）。
class R2SyncSection extends ConsumerStatefulWidget {
  const R2SyncSection({super.key});

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

  Future<void> _syncNow() async {
    final credentials = ref.read(r2CredentialsProvider);
    if (credentials == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final client = R2Client(
        credentials: credentials,
        bucket: ref.read(r2BucketNameProvider),
      );
      final service = R2SyncService(client);
      final count = await service.pullDiary(ref.read(diaryRepositoryProvider));
      final now = DateTime.now();
      await ref
          .read(keyValueStoreProvider)
          .write(_lastSyncedKey, now.toIso8601String());
      if (!mounted) return;
      setState(() {
        _lastSyncedAt = now;
        _syncing = false;
      });
      showAppNotice(context, '日記 同步成功 $count 筆');
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      showAppNotice(context, '日記同步失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credentials = ref.watch(r2CredentialsProvider);
    return GlassCard(
      child: credentials == null ? _buildInputCard() : _buildConnectedCard(credentials),
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
