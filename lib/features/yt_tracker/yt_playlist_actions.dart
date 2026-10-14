import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_display_prefs_store.dart';
import '../../data/repositories/yt_playlist_store.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/app_notice.dart';
import 'yt_channel_avatar.dart';

/// 改播放清單：先更新畫面上的那份（[ytPlaylistsProvider]），再寫回本機。
/// 每次改都蓋上這份清單的 updatedAt，同步時才知道誰比較新。
class YtPlaylistActions {
  YtPlaylistActions(this.ref);

  final WidgetRef ref;

  List<YtPlaylist> get _all => ref.read(ytPlaylistsProvider);

  YtPlaylist? byId(String id) {
    for (final p in _all) {
      if (p.id == id && p.deletedAt == null) return p;
    }
    return null;
  }

  Future<void> _commit(List<YtPlaylist> next) async {
    ref.read(ytPlaylistsProvider.notifier).state = next;
    await YtPlaylistStore(ref.read(keyValueStoreProvider)).saveAll(next);
  }

  Future<void> _replace(String id, YtPlaylist Function(YtPlaylist) change) {
    final now = DateTime.now();
    return _commit([
      for (final p in _all)
        if (p.id == id) change(p).copyWith(updatedAt: now) else p,
    ]);
  }

  /// 加到最前面；已經在了回 false。
  Future<bool> add(String id, YtPlaylistItem item) async {
    final p = byId(id);
    if (p == null || p.contains(item.videoId)) return false;
    await _replace(id, (p) => p.copyWith(items: [item, ...p.items]));
    return true;
  }

  /// 拿掉，回傳原本在第幾個（復原用）；不在回 -1。
  Future<int> remove(String id, String videoId) async {
    final p = byId(id);
    final at = p?.items.indexWhere((i) => i.videoId == videoId) ?? -1;
    if (at < 0) return -1;
    await _replace(
      id,
      (p) => p.copyWith(
        items: [
          for (final i in p.items)
            if (i.videoId != videoId) i,
        ],
      ),
    );
    return at;
  }

  Future<void> insertAt(String id, YtPlaylistItem item, int index) =>
      _replace(id, (p) {
        if (p.contains(item.videoId)) return p;
        final items = [...p.items];
        items.insert(index.clamp(0, items.length), item);
        return p.copyWith(items: items);
      });

  Future<void> moveToTop(String id, String videoId) => _replace(id, (p) {
    final hit = p.items.where((i) => i.videoId == videoId).toList();
    if (hit.isEmpty) return p;
    return p.copyWith(
      items: [
        hit.first,
        for (final i in p.items)
          if (i.videoId != videoId) i,
      ],
    );
  });

  Future<String> create(String name, {YtPlaylistItem? first}) async {
    final now = DateTime.now();
    final id = 'pl-${now.microsecondsSinceEpoch}';
    await _commit([
      ..._all,
      YtPlaylist(
        id: id,
        name: name.trim(),
        items: [if (first != null) first],
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    return id;
  }

  Future<void> rename(String id, String name) =>
      _replace(id, (p) => p.copyWith(name: name.trim()));

  /// 刪掉留墓碑（同步用）；「稍後觀看」不能刪。
  Future<void> delete(String id) async {
    if (id == YtPlaylist.laterId) return;
    await _replace(
      id,
      (p) => p.copyWith(items: const [], deletedAt: DateTime.now()),
    );
  }
}

/// 「存到稍後觀看」：一鍵存，已經在了就說一聲。
Future<void> saveToWatchLater(
  BuildContext context,
  WidgetRef ref,
  YtPlaylistItem item,
) async {
  final actions = YtPlaylistActions(ref);
  final added = await actions.add(YtPlaylist.laterId, item);
  if (!context.mounted) return;
  if (!added) {
    showAppNotice(context, '已經在「稍後觀看」了');
    return;
  }
  showAppNotice(
    context,
    '已存到「稍後觀看」',
    actionLabel: '復原',
    onAction: () => actions.remove(YtPlaylist.laterId, item.videoId),
  );
}

/// 「存到…」（設計稿第 1 版）：每份清單一行打勾，可以勾好幾個，最下面
/// 直接打名字新建（新建的會順便存進去）。
Future<void> showSaveToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  YtPlaylistItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C29),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _SaveSheet(item: item),
  );
}

class _SaveSheet extends ConsumerStatefulWidget {
  const _SaveSheet({required this.item});

  final YtPlaylistItem item;

  @override
  ConsumerState<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends ConsumerState<_SaveSheet> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await YtPlaylistActions(ref).create(name, first: widget.item);
    if (!mounted) return;
    setState(() {
      _creating = false;
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlists = YtPlaylistStore.visible(ref.watch(ytPlaylistsProvider));
    final actions = YtPlaylistActions(ref);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 9, bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            Row(
              children: [
                const Text(
                  '添加到播放清單',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                Text('可以勾好幾個', style: AppText.note),
              ],
            ),
            const SizedBox(height: Gap.xs),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in playlists)
                    CheckboxListTile(
                      value: p.contains(widget.item.videoId),
                      onChanged: (v) => v == true
                          ? actions.add(p.id, widget.item)
                          : actions.remove(p.id, widget.item.videoId),
                      title: Text(
                        p.name,
                        style: const TextStyle(color: AppColors.ink),
                      ),
                      secondary: Text('${p.items.length}', style: AppText.note),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF0A84FF),
                    ),
                ],
              ),
            ),
            if (_creating)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      onSubmitted: (_) => _create(),
                      style: const TextStyle(color: AppColors.ink),
                      decoration: const InputDecoration(
                        hintText: '新清單的名字',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  FilledButton(onPressed: _create, child: const Text('建立')),
                ],
              )
            else
              ListTile(
                onTap: () => setState(() => _creating = true),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFF0A84FF),
                ),
                title: const Text(
                  '新增播放清單',
                  style: TextStyle(color: Color(0xFF0A84FF)),
                ),
              ),
            const SizedBox(height: Gap.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打一個名字（新增／改名播放清單用）。
Future<String?> askPlaylistName(
  BuildContext context, {
  String title = '新增播放清單',
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C29),
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: '名字'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
          child: const Text('好'),
        ),
      ],
    ),
  ).then((v) => v == null || v.isEmpty ? null : v);
}

/// 選 YT 底部分頁列「影片」那格要開哪個頻道（2026-10-14 使用者要求：
/// 當快捷，設定裡也能換，跨裝置同步）。選了就存進 [YtDisplayPrefs]，
/// 回傳頻道 id；沒選回 null。
Future<String?> pickVideoTabChannel(BuildContext context, WidgetRef ref) async {
  final channels = await ref.read(ytTrackerRepositoryProvider).loadChannels();
  if (!context.mounted) return null;
  channels.sort((a, b) => a.name.compareTo(b.name));
  final current = ref.read(ytDisplayPrefsProvider).videoTabChannelId;
  final picked = await showModalBottomSheet<YtChannel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C29),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text(
                '「影片」分頁要開哪個頻道',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('之後可以在設定換', style: AppText.note),
            ),
            if (channels.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '還沒有頻道，先到「頻道」新增',
                  style: AppText.bodyDim,
                  textAlign: TextAlign.center,
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in channels)
                    ListTile(
                      onTap: () => Navigator.of(context).pop(c),
                      leading: YtChannelAvatar(channel: c, radius: 18),
                      title: Text(
                        c.name,
                        style: const TextStyle(color: AppColors.ink),
                      ),
                      trailing: c.id == current
                          ? const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF0A84FF),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return null;
  final next = ref
      .read(ytDisplayPrefsProvider)
      .copyWith(videoTabChannelId: picked.id);
  ref.read(ytDisplayPrefsProvider.notifier).state = next;
  final saved = await YtDisplayPrefsStore(
    ref.read(keyValueStoreProvider),
  ).save(next);
  ref.read(ytDisplayPrefsProvider.notifier).state = saved;
  return picked.id;
}
