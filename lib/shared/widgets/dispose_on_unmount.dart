import 'package:flutter/widgets.dart';

/// 對話框裡用的 [TextEditingController] 這類東西，等對話框真的從畫面上
/// 移除（關閉動畫播完）才釋放（2026-10-06 效能檢查：原本開一次對話框就
/// 留一組沒釋放的輸入欄）。不能在 `await showDialog` 回來的當下直接
/// dispose——那時關閉動畫還在播、輸入欄還在畫，會丟「用了已釋放的
/// controller」的錯。呼叫端照樣可以在對話框回傳後讀 `.text`。
class DisposeOnUnmount extends StatefulWidget {
  const DisposeOnUnmount({
    super.key,
    required this.notifiers,
    required this.child,
  });

  final List<ChangeNotifier> notifiers;
  final Widget child;

  @override
  State<DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<DisposeOnUnmount> {
  @override
  void dispose() {
    for (final n in widget.notifiers) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
