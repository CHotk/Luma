import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../data/services/yt_video_type_scanner.dart';
import '../../shared/widgets/app_notice.dart';

/// 目前有沒有一輪「補齊影片類型」在背景跑（同時只跑一輪）。
bool _backfillRunning = false;

/// 一次把所有頻道快取裡還沒標類型的影片補上（一般影片／Shorts／直播）。
/// 2026-10-05 使用者要求：先一次補齊目前快取有的全部影片，之後就只要
/// 打開頻道時背景補新抓到的影片（見 [YtVideoTypeScanner]）。標過的不會
/// 再碰，所以中途配額用完再按一次，已經補好的頻道直接跳過。
///
/// 在背景跑（2026-10-06 使用者要求：不要擋著整個 App 乾等，點別的地方
/// 照樣能用，進度用像通知的方式顯示在最上面）：進度條插在最上層的
/// Overlay，換頁也還在；讀寫資料用整個 App 共用的 ProviderContainer，
/// 不是設定頁自己的 ref——使用者離開設定頁，頁面的 ref 就失效了。
Future<void> runYtTypeBackfill(BuildContext context, WidgetRef ref) async {
  if (_backfillRunning) {
    showAppNotice(context, '已經在補了，進度在畫面最上面');
    return;
  }
  final apiKey = ref.read(ytApiKeyProvider);
  if (apiKey == null || apiKey.isEmpty) {
    showAppNotice(context, '還沒設定 API 金鑰，無法補類型', isError: true);
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final overlay = Overlay.of(context, rootOverlay: true);
  final status = ValueNotifier<_BackfillStatus>(
    const _BackfillStatus(done: 0, total: 0, text: '準備中…'),
  );
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
    status.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => _BackfillBanner(status: status, onDismiss: remove),
  );
  overlay.insert(entry);
  _backfillRunning = true;

  var tagged = 0;
  var scanned = 0;
  String? error;
  try {
    final channels = await container
        .read(ytTrackerRepositoryProvider)
        .loadChannels();
    final kv = container.read(keyValueStoreProvider);
    final cache = YtVideoCacheStore(kv);
    final scanner = YtVideoTypeScanner(YoutubeApiService(apiKey), kv);
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      status.value = _BackfillStatus(
        done: i,
        total: channels.length,
        text: c.name,
      );
      var uploadsId = c.uploadsPlaylistId;
      if (uploadsId.isEmpty && c.youtubeChannelId.startsWith('UC')) {
        uploadsId = 'UU${c.youtubeChannelId.substring(2)}';
      }
      if (uploadsId.isEmpty || (await cache.load(c.id)).isEmpty) continue;
      try {
        tagged += await scanner.tagUntagged(
          channelId: c.id,
          uploadsId: uploadsId,
        );
        scanned++;
      } catch (e) {
        // 多半是配額用完：停下來，已經補好的會留著，明天再按接著補剩下的。
        error = '$e';
        break;
      }
    }
  } catch (e) {
    error = '$e';
  } finally {
    _backfillRunning = false;
  }
  // 讓開著的頻道頁重新讀快取，標籤馬上出現。
  container.read(dataRevisionProvider.notifier).state++;
  if (removed) return;
  status.value = _BackfillStatus(
    done: 1,
    total: 1,
    text: error == null
        ? '補好了：$scanned 個頻道、$tagged 部影片標上類型'
        : '補到一半停下來了（$error）。已完成 $scanned 個頻道，之後再按會接著補',
    finished: true,
    failed: error != null,
  );
  // 結果停留幾秒自己收掉；點一下也能馬上收。
  Timer(Duration(seconds: error == null ? 4 : 8), remove);
}

class _BackfillStatus {
  const _BackfillStatus({
    required this.done,
    required this.total,
    required this.text,
    this.finished = false,
    this.failed = false,
  });

  final int done;
  final int total;
  final String text;
  final bool finished;
  final bool failed;
}

/// 畫面最上面的進度條，樣子跟 [showAppNotice] 的毛玻璃提示一致。
class _BackfillBanner extends StatelessWidget {
  const _BackfillBanner({required this.status, required this.onDismiss});

  final ValueNotifier<_BackfillStatus> status;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(16);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.screenSide,
            10,
            Gap.screenSide,
            0,
          ),
          child: Material(
            color: Colors.transparent,
            child: ValueListenableBuilder<_BackfillStatus>(
              valueListenable: status,
              builder: (context, s, _) => GestureDetector(
                // 跑完之後點一下收掉；還在跑的時候不給關（關了就看不到進度）。
                onTap: s.finished ? onDismiss : null,
                child: ClipRRect(
                  borderRadius: shape,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                      decoration: BoxDecoration(
                        color: const Color(0xE0141220),
                        borderRadius: shape,
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (s.finished)
                                Icon(
                                  s.failed
                                      ? Icons.error_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 18,
                                  color: s.failed
                                      ? AppColors.bad
                                      : AppColors.ok,
                                )
                              else
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Text(
                                  s.finished
                                      ? s.text
                                      : s.total == 0
                                      ? '補影片類型：${s.text}'
                                      : '補影片類型中 ${s.done + 1}/${s.total}・${s.text}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!s.finished && s.total > 0) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: LinearProgressIndicator(
                                value: s.done / s.total,
                                minHeight: 4,
                                backgroundColor: AppColors.glassEdge,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('可以先去別的地方，跑完會在這裡告訴你', style: AppText.note),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// YT 設定頁上的那一列。
class YtTypeBackfillRow extends ConsumerWidget {
  const YtTypeBackfillRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Icon(Icons.category_outlined, size: 18, color: AppColors.ink2),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '補齊影片類型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text('把快取裡所有影片標上一般／Shorts／直播', style: AppText.note),
            ],
          ),
        ),
        TextButton(
          onPressed: () => runYtTypeBackfill(context, ref),
          child: const Text('開始'),
        ),
      ],
    );
  }
}
