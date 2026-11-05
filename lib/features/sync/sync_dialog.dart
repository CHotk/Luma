import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../settings/r2_sync_section.dart';

/// 每個功能右上角那顆雲端同步按鈕點下去開的懸浮視窗（2026-11-04 使用者：
/// 每次都要點功能選單再點「多裝置同步」太麻煩）。裡面就是多裝置同步頁那一
/// 塊（[R2SyncSection]：連線狀態、立即同步、每個功能的進度），同步的進度是
/// 全 App 共用一份，所以關掉視窗同步照跑、再開還接得上。
Future<void> showSyncDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480, maxHeight: maxH),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF0141220),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassEdge),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        size: 19,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('多裝置同步', style: AppText.title)),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 22),
                        color: AppColors.ink2,
                        tooltip: '關閉',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: const R2SyncSection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
