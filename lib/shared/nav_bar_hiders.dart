import 'package:flutter/foundation.dart';

/// 現在有幾個東西要底部分頁列先藏起來（不是 route 的那種，例如左邊選單）。
/// 2026-10-15 使用者回報左邊選單滑到底被分頁列擋住：主流 App（Gmail、
/// YouTube）打開側邊選單都是蓋住整個畫面、分頁列不見，所以照做。
final navBarHiders = ValueNotifier<int>(0);
