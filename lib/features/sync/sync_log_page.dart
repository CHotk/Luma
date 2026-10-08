import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'sync_log_row.dart';

/// 全部同步紀錄（2026-10-08 使用者要求：同步頁主畫面最多 10 筆，其他從
/// 紀錄按鈕進來看）。紀錄一筆都不刪；這裡一次畫 20 筆，捲到底附近再多畫。
class SyncLogPage extends ConsumerStatefulWidget {
  const SyncLogPage({super.key});

  @override
  ConsumerState<SyncLogPage> createState() => _SyncLogPageState();
}

class _SyncLogPageState extends ConsumerState<SyncLogPage> {
  late final Future<List<SyncLogEntry>> _future = ref
      .read(syncLogRepositoryProvider)
      .loadAll();
  int _visible = 20;

  @override
  Widget build(BuildContext context) {
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
                const AppTopBar(title: '同步紀錄'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder(
                    future: _future,
                    builder: (context, snap) {
                      final log = snap.data;
                      if (log == null) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      if (log.isEmpty) {
                        return Text('還沒有同步或備份紀錄', style: AppText.bodyDim);
                      }
                      return NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >=
                                  n.metrics.maxScrollExtent - 300 &&
                              _visible < log.length) {
                            setState(() => _visible += 20);
                          }
                          return false;
                        },
                        child: ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: Text(
                                '共 ${log.length} 筆・一筆都不刪',
                                style: AppText.note,
                              ),
                            ),
                            for (final e in log.take(_visible))
                              SyncLogRow(entry: e),
                            const SizedBox(height: Gap.xl),
                          ],
                        ),
                      );
                    },
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
