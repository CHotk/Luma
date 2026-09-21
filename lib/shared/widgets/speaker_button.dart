import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';

/// 發音按鈕。點一下用 TTS 唸出 [text]，全 App 共用同一顆，
/// 不要每個畫面各自刻一顆長得不一樣的。
class SpeakerButton extends ConsumerWidget {
  const SpeakerButton({
    super.key,
    required this.text,
    this.size = 20,
    this.color = AppColors.accent,
  });

  final String text;
  final double size;

  /// 圖示顏色。預設是英文軌道的藍色，日文軌道（櫻色）等場合要帶
  /// [AppColors.jpAccentInk] 之類跟自己底色搭的顏色進來，不要讓每個
  /// 畫面各自複製一份 IconButton 出來改色（2026-09-21）。
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () async {
        final tts = await ref.read(ttsServiceProvider.future);
        await tts.speak(text);
      },
      icon: Icon(Icons.volume_up_rounded, size: size),
      color: color,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 14, minHeight: size + 14),
      tooltip: '播放發音',
    );
  }
}
