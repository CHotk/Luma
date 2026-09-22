import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../domain/models/yt_tracker.dart';

/// 頻道頭像：[YtChannel.avatarImageUrl] 有填就顯示真的圖片，沒填、或
/// 圖片載入失敗（網址失效、被 CORS 擋掉）都退回 [YtChannel.avatarEmoji]
/// 佔位——不會整格空白或噴錯誤圖示（2026-09-22 使用者要求：要抓真的
/// 頭貼放上去）。首頁、瀏覽頁、頻道詳情頁共用同一顆，樣式才會一致。
class YtChannelAvatar extends StatelessWidget {
  const YtChannelAvatar({super.key, required this.channel, this.radius = 18});

  final YtChannel channel;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (channel.avatarImageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.bg,
        child: Text(
          channel.avatarEmoji,
          style: TextStyle(fontSize: radius * 0.9),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.bg,
      child: ClipOval(
        child: Image.network(
          channel.avatarImageUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Text(
            channel.avatarEmoji,
            style: TextStyle(fontSize: radius * 0.9),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: radius * 0.8,
              height: radius * 0.8,
              child: const CircularProgressIndicator(strokeWidth: 1.6),
            );
          },
        ),
      ),
    );
  }
}
