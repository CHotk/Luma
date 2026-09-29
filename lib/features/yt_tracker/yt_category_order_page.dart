import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_category_order_store.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';

/// YT 分類顯示順序：長按拖曳排序（2026-09-29 使用者要求，且不是第一次
/// 提——之前只做了 [YtCategoryOrderStore] 但沒接 UI，這頁才是真的能用的
/// 入口）。拖完放開就直接存檔生效，不用另外按儲存（2026-09-29 使用者
/// 要求：「那邊不用特別儲存 也自動有改動就生效」——跟同一頁面「訂閱
/// 人數更新頻率」那種需要草稿＋按鈕確認的設定是不同哲學，這裡排序本身
/// 就是「拖到哪就是哪」，沒有中間狀態需要保留）。「看過但不喜歡」固定
/// 排最後，不放進可拖動的清單裡，維持既有規則
/// （[YtTrackerRepository.loadCategories] 的說明）。
class YtCategoryOrderPage extends ConsumerStatefulWidget {
  const YtCategoryOrderPage({super.key});

  @override
  ConsumerState<YtCategoryOrderPage> createState() =>
      _YtCategoryOrderPageState();
}

class _YtCategoryOrderPageState extends ConsumerState<YtCategoryOrderPage> {
  List<YtCategory>? _categories;
  YtCategory? _disliked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await ref.read(ytTrackerRepositoryProvider).loadCategories();
    if (!mounted) return;
    YtCategory? disliked;
    final ordered = <YtCategory>[];
    for (final c in all) {
      if (c.id == ytDislikedCategoryId) {
        disliked = c;
      } else {
        ordered.add(c);
      }
    }
    setState(() {
      _categories = ordered;
      _disliked = disliked;
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final categories = _categories!;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = categories.removeAt(oldIndex);
      categories.insert(newIndex, item);
    });
    // 放開就直接存檔，沒有儲存按鈕。
    await YtCategoryOrderStore(
      ref.read(keyValueStoreProvider),
    ).save([for (final c in categories) c.id]);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
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
                  title: '分類顯示順序',
                  titleIcon: Icons.reorder_rounded,
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '長按拖曳排序，放開就自動儲存生效，不用另外按儲存；'
                  '「看過但不喜歡」固定排最後不能拖動；「垃圾桶」排在比它'
                  '更後面、永遠是最後一個，也不在這份清單裡',
                  style: AppText.note,
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: categories == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ReorderableListView.builder(
                                itemCount: categories.length,
                                onReorder: _onReorder,
                                itemBuilder: (context, i) {
                                  final c = categories[i];
                                  return Container(
                                    key: ValueKey(c.id),
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.glassFill,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.glassEdge,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: c.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      title: Text(
                                        c.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.drag_handle_rounded,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_disliked != null) ...[
                              const SizedBox(height: Gap.sm),
                              const Divider(
                                height: 1,
                                color: AppColors.glassEdge,
                              ),
                              const SizedBox(height: Gap.sm),
                              Opacity(
                                opacity: 0.6,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.thumb_down_outlined,
                                    size: 18,
                                    color: AppColors.ink3,
                                  ),
                                  title: Text(
                                    _disliked!.name,
                                    style: AppText.bodyDim,
                                  ),
                                  trailing: Text('固定最後', style: AppText.note),
                                ),
                              ),
                            ],
                          ],
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
