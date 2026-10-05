import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/storage/key_value_store.dart';
import '../../data/storage/platform_store.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'local_storage_groups.dart';

/// 本機儲存檢視：這台裝置（瀏覽器 IndexedDB）裡存了哪些資料、各佔多少。
///
/// 2026-10-05 使用者從 `design-history/已選擇完成/本機儲存檢視設計/` 挑了 04「排行榜」
/// 但不要清理建議，另外要「點一下能像 01 那樣看 JSON 內容」：
/// - 最上面總用量（瀏覽器問得到配額的話，加上配額跟用了幾 %）。
/// - 依功能分組的大小排行，點一組展開這組的 key 表格（key／大小／筆數，
///   跟 01 的 DevTools 表格一樣）。
/// - 點表格裡的一列，下面展開這個 key 的 JSON 內容（唯讀）。含金鑰、
///   密碼的 key 跟日記只顯示大小，不顯示內容（見 [isSensitiveStorageKey]）。
///
/// 只看不改：沒有刪除、清理按鈕。
class LocalStoragePage extends ConsumerStatefulWidget {
  const LocalStoragePage({super.key});

  @override
  ConsumerState<LocalStoragePage> createState() => _LocalStoragePageState();
}

class _LocalStoragePageState extends ConsumerState<LocalStoragePage> {
  Map<String, String>? _all;
  List<StorageGroup>? _groups;
  ({int? usage, int? quota})? _estimate;
  String? _error;
  String? _openGroup;
  String? _openKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(keyValueStoreProvider);
    if (store is! ListableKeyValueStore) {
      setState(() => _error = '這個平台的儲存方式不支援列出全部資料');
      return;
    }
    final all = await store.readAll();
    final estimate = await estimateStorage();
    if (!mounted) return;
    setState(() {
      _all = all;
      _groups = groupStorage(all);
      _estimate = estimate;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
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
                  title: '本機儲存',
                  titleIcon: Icons.storage_outlined,
                  showSettings: false,
                  actions: [
                    IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '重新整理',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: _error != null
                      ? Center(child: Text(_error!, style: AppText.bodyDim))
                      : groups == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ListView(
                          children: [
                            _TotalCard(groups: groups, estimate: _estimate),
                            const SizedBox(height: Gap.md),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 2,
                                bottom: Gap.xs,
                              ),
                              child: Text(
                                '大小排行・點一列看裡面的資料',
                                style: AppText.note,
                              ),
                            ),
                            for (var i = 0; i < groups.length; i++) ...[
                              _GroupCard(
                                rank: i + 1,
                                group: groups[i],
                                total: groups.fold(0, (s, g) => s + g.bytes),
                                open: _openGroup == groups[i].label,
                                openKey: _openKey,
                                values: _all!,
                                onTapGroup: () => setState(() {
                                  final label = groups[i].label;
                                  _openGroup = _openGroup == label
                                      ? null
                                      : label;
                                  _openKey = null;
                                }),
                                onTapKey: (key) => setState(
                                  () => _openKey = _openKey == key ? null : key,
                                ),
                              ),
                              const SizedBox(height: Gap.sm),
                            ],
                            const SizedBox(height: Gap.lg),
                          ],
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.groups, required this.estimate});

  final List<StorageGroup> groups;
  final ({int? usage, int? quota})? estimate;

  @override
  Widget build(BuildContext context) {
    final total = groups.fold(0, (s, g) => s + g.bytes);
    final keyCount = groups.fold(0, (s, g) => s + g.keys.length);
    final quota = estimate?.quota;
    final usage = estimate?.usage;
    final ratio = quota != null && quota > 0 && usage != null
        ? usage / quota
        : null;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatBytes(total),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (quota != null)
                Text('瀏覽器配額約 ${formatBytes(quota)}', style: AppText.note),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: Gap.sm),
            _Bar(fraction: ratio, color: AppColors.accent),
          ],
          const SizedBox(height: Gap.xs),
          Text(
            [
              if (ratio != null) '整個網站已用 ${(ratio * 100).toStringAsFixed(1)}%',
              '共 $keyCount 筆資料',
            ].join('・'),
            style: AppText.note,
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.rank,
    required this.group,
    required this.total,
    required this.open,
    required this.openKey,
    required this.values,
    required this.onTapGroup,
    required this.onTapKey,
  });

  final int rank;
  final StorageGroup group;
  final int total;
  final bool open;
  final String? openKey;
  final Map<String, String> values;
  final VoidCallback onTapGroup;
  final void Function(String key) onTapKey;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTapGroup,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$rank. ${group.label}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(formatBytes(group.bytes), style: AppText.note),
                      const SizedBox(width: 4),
                      Icon(
                        open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Bar(
                    fraction: total == 0 ? 0 : group.bytes / total,
                    color: group.color,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: _KeyTable(
                      group: group,
                      openKey: openKey,
                      values: values,
                      onTapKey: onTapKey,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 一組底下的 key 表格（設計稿 01 的 DevTools 樣子）：key／大小／筆數，
/// 點一列在它下面展開 JSON。
class _KeyTable extends StatelessWidget {
  const _KeyTable({
    required this.group,
    required this.openKey,
    required this.values,
    required this.onTapKey,
  });

  final StorageGroup group;
  final String? openKey;
  final Map<String, String> values;
  final void Function(String key) onTapKey;

  @override
  Widget build(BuildContext context) {
    const headStyle = TextStyle(fontSize: 11, color: AppColors.ink3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: AppColors.glassEdge),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text('Key', style: headStyle)),
              SizedBox(
                width: 64,
                child: Text('大小', style: headStyle, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 48,
                child: Text('筆數', style: headStyle, textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        for (final k in group.keys) ...[
          const Divider(height: 1, color: AppColors.glassEdge),
          InkWell(
            onTap: () => onTapKey(k.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k.key,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'Consolas',
                        color: openKey == k.key
                            ? AppColors.accent
                            : AppColors.ink2,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatBytes(k.bytes),
                      style: AppText.note,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      k.count == null ? '—' : '${k.count}',
                      style: AppText.note,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (openKey == k.key)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: _JsonView(storageKey: k.key, value: values[k.key] ?? ''),
            ),
        ],
      ],
    );
  }
}

/// 一個 key 的內容（唯讀）。
class _JsonView extends StatelessWidget {
  const _JsonView({required this.storageKey, required this.value});

  final String storageKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (isSensitiveStorageKey(storageKey)) {
      body = Text(
        storageKey.startsWith('diary.')
            ? '日記有密碼鎖，內容請到日記頁解鎖後看'
            : '這筆含金鑰或密碼，不在這裡顯示內容',
        style: AppText.note,
      );
    } else {
      final preview = previewStorageValue(value);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            preview.text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.6,
              fontFamily: 'Consolas',
              color: Color(0xFFB9C7FF),
            ),
          ),
          if (preview.truncated) ...[
            const SizedBox(height: Gap.xs),
            Text(
              '內容很長，只顯示前 $storagePreviewChars 字'
              '（全部 ${preview.totalChars} 字）',
              style: AppText.note,
            ),
          ],
        ],
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: SingleChildScrollView(child: body),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 7,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF1E1E2E))),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(
                constraints: const BoxConstraints(minWidth: 3),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
