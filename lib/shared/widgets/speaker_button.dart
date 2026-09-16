import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';

/// 發音按鈕。點一下用 TTS 唸出 [text]，全 App 共用同一顆，
/// 不要每個畫面各自刻一顆長得不一樣的。
class SpeakerButton extends ConsumerWidget {
  const SpeakerButton({super.key, required this.text, this.size = 20});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () => ref.read(ttsServiceProvider).speak(text),
      icon: Icon(Icons.volume_up_rounded, size: size),
      color: AppColors.accent,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 14, minHeight: size + 14),
      tooltip: '播放發音',
    );
  }
}
