import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/home_card_order_store.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';

/// 首頁卡片的 id 跟名稱。英文、日文首頁各自列自己有哪些卡片（見
/// `home_page.dart` 的 `enHomeCards`、`jp_home_page.dart` 的
/// `jpHomeCards`），順序就是沒排過時的預設順序。
typedef HomeCard = ({String id, String label});

/// 英文／日文首頁卡片順序：長按拖曳排序（2026-10-05 使用者要求：像 YT
/// 分類順序那樣）。跟 [YtCategoryOrderPage] 同一套：放開就直接存檔生效，
/// 不用按儲存；存檔會帶上時間，同步時兩台裝置比新舊，新的贏。
class HomeCardOrderPage extends ConsumerStatefulWidget {
  const HomeCardOrderPage({
    super.key,
    required this.track,
    required this.title,
    required this.cards,
  });

  /// `en` 或 `jp`。
  final String track;
  final String title;
  final List<HomeCard> cards;

  @override
  ConsumerState<HomeCardOrderPage> createState() => _HomeCardOrderPageState();
}

class _HomeCardOrderPageState extends ConsumerState<HomeCardOrderPage> {
  List<HomeCard>? _cards;

  HomeCardOrderStore get _store =>
      HomeCardOrderStore(ref.read(keyValueStoreProvider), widget.track);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _store.load();
    if (!mounted) return;
    final byId = {for (final c in widget.cards) c.id: c};
    final ids = applyHomeCardOrder([for (final c in widget.cards) c.id], saved);
    setState(() => _cards = [for (final id in ids) byId[id]!]);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final cards = _cards!;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = cards.removeAt(oldIndex);
      cards.insert(newIndex, item);
    });
    await _store.save([for (final c in cards) c.id]);
    // 首頁是疊在下面的，靠這個號碼通知它重排，退回去馬上看到新順序。
    ref.read(dataRevisionProvider.notifier).state++;
  }

  Future<void> _reset() async {
    await _store.save([for (final c in widget.cards) c.id]);
    ref.read(dataRevisionProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _cards = [...widget.cards]);
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
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
                AppTopBar(
                  title: widget.title,
                  titleIcon: Icons.reorder_rounded,
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '長按拖曳排序，放開就自動儲存生效；最上面的時間列跟最下面的'
                  '開始按鈕固定不動。按同步會跟其他裝置對齊，以最後調整的為準',
                  style: AppText.note,
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: cards == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : ReorderableListView.builder(
                          itemCount: cards.length,
                          onReorder: _onReorder,
                          itemBuilder: (context, i) {
                            final c = cards[i];
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
                                border: Border.all(color: AppColors.glassEdge),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Text('${i + 1}', style: AppText.note),
                                title: Text(
                                  c.label,
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
                TextButton(
                  onPressed: cards == null ? null : _reset,
                  child: const Text('恢復預設順序'),
                ),
                const SizedBox(height: Gap.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
