import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 只處理兩種行內語法的文字：**粗體** 和 `程式碼`。
///
/// 用法地雷那份文件只用到這兩種，所以不值得為它拉一個 Markdown 套件進來。
/// 需要更多語法時再擴充這裡，畫面不用改。
class InlineText extends StatelessWidget {
  const InlineText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(style: style, children: _spans()),
    );
  }

  List<InlineSpan> _spans() {
    final pattern = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
    final spans = <InlineSpan>[];
    var index = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final bold = match.group(1);
      if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: ['Courier New', 'monospace'],
              color: AppColors.accent,
            ),
          ),
        );
      }
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }
}
