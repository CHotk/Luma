import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import 'yt_tracker_home_page.dart' show YtCategoryCard;

/// 垃圾桶首頁：跟 YT 首頁一樣的分類格子，只是每張卡片數的是「這個分類裡
/// 被刪除的頻道」，不是還在用的（2026-09-29 使用者要求：垃圾桶其實也是
/// 一個 YT 管理入口，只是專門裝被刪除的頻道，長相要跟原本的分類格子
/// 一樣，不是一份自己刻的名單）。點卡片進 [YtTrashBrowsePage] 看該分類
/// 被刪除的頻道，可以還原／永久刪除——跟「YT 首頁點分類卡進 browse 頁」
/// 是同一種兩層結構，只是資料來源換成 `loadDeletedChannels()`。
class YtTrashPage extends ConsumerStatefulWidget {
  const YtTrashPage({super.key});

  @override
  ConsumerState<YtTrashPage> createState() => _YtTrashPageState();
}

class _YtTrashPageState extends ConsumerState<YtTrashPage> {
  late Future<({List<YtCategory> categories, List<YtChannel> deleted})>
  _future = _load();

  Future<({List<YtCategory> categories, List<YtChannel> deleted})>
  _load() async {
    final repo = ref.read(ytTrackerRepositoryProvider);
    final categories = await repo.loadCategories();
    final deleted = await repo.loadDeletedChannels();
    return (categories: categories, deleted: deleted);
  }

  void _reload() => setState(() => _future = _load());

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
                const AppTopBar(
                  title: '垃圾桶',
                  titleIcon: Icons.delete_outline_rounded,
                  showSettings: false,
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child:
                      FutureBuilder<
                        ({List<YtCategory> categories, List<YtChannel> deleted})
                      >(
                        future: _future,
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          final categories = snap.data!.categories;
                          final deleted = snap.data!.deleted;
                          if (deleted.isEmpty) {
                            return Center(
                              child: Text('垃圾桶是空的', style: AppText.bodyDim),
                            );
                          }
                          final unassigned = deleted
                              .where((c) => c.categoryId == null)
                              .toList();
                          final uncategorized = unassigned.isEmpty
                              ? null
                              : const YtCategory(
                                  id: ytUncategorizedId,
                                  name: '未分類',
                                  colorValue: 0xFF74738A,
                                  imageUrl:
                                      'assets/images/yt_tracker/uncategorized.png',
                                );
                          // 跟 YT 首頁同一組分類格子順序：一般分類→未分類→
                          // 「看過但不喜歡」，只是每張卡數的是被刪除的頻道。
                          final gridCats = [
                            ...categories.where(
                              (c) => c.id != ytDislikedCategoryId,
                            ),
                            ?uncategorized,
                            ...categories.where(
                              (c) => c.id == ytDislikedCategoryId,
                            ),
                          ];
                          return CustomScrollView(
                            slivers: [
                              // 「全部」獨佔整行，跟首頁同一個慣例
                              // （2026-09-24 使用者要求那邊定案，這裡沿用）。
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: AspectRatio(
                                    aspectRatio: 3,
                                    child: YtCategoryCard(
                                      category: const YtCategory(
                                        id: '__all__',
                                        name: '全部',
                                        colorValue: 0xFF7EA6FF,
                                        imageUrl:
                                            'assets/images/yt_tracker/all.png',
                                      ),
                                      channels: deleted,
                                      maxAvatars: 7,
                                      count: deleted.length,
                                      onTap: () => context
                                          .push(
                                            '/yt-tracker/trash/browse',
                                            extra: <String>{},
                                          )
                                          .then((_) => _reload()),
                                      onLongPress: null,
                                    ),
                                  ),
                                ),
                              ),
                              SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 1.5,
                                    ),
                                delegate: SliverChildBuilderDelegate(
                                  childCount: gridCats.length,
                                  (_, i) {
                                    final cat = gridCats[i];
                                    final isUncategorized =
                                        cat.id == ytUncategorizedId;
                                    final catChannels = isUncategorized
                                        ? unassigned
                                        : deleted
                                              .where(
                                                (c) => c.categoryId == cat.id,
                                              )
                                              .toList();
                                    return YtCategoryCard(
                                      category: cat,
                                      channels: catChannels,
                                      maxAvatars: 3,
                                      count: catChannels.length,
                                      onTap: () => context
                                          .push(
                                            '/yt-tracker/trash/browse',
                                            extra: {cat.id},
                                          )
                                          .then((_) => _reload()),
                                      onLongPress: null,
                                    );
                                  },
                                ),
                              ),
                            ],
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
