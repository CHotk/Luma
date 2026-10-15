import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/glass_card.dart';
import 'yt_channel_avatar.dart';

/// 頻道詳情頁「編輯中」的頭部（2026-10-12 使用者挑了編輯頻道設計稿第 5 版
/// 「頻道頁本身直接點著改」，最終版見 `design-history/已選擇完成/
/// 2026-10-12_YT編輯頻道最終版（頁面上直接改）.html`）。
///
/// 版面跟平常的頭部一樣（頭像、名稱、分類・訂閱、連結、簡介），每個能改
/// 的地方圍一圈藍色虛線＋右上角小鉛筆，點哪改哪；改過的那個虛線變實線。
/// 名稱、連結、簡介點了原地變輸入框，分類點了下面展開一排色塊。頭像要
/// 開底部表單、可能要打 API，交給頁面處理（[onTapAvatar]）。
///
/// 只改 [draft]，每次改都透過 [onChanged] 交回頁面；存不存、還原由頁面的
/// 儲存列決定。[base] 是進編輯時的樣子，拿來判斷哪些欄位改過。
class YtChannelEditHeader extends StatefulWidget {
  const YtChannelEditHeader({
    super.key,
    required this.draft,
    required this.base,
    required this.categories,
    required this.originalName,
    required this.onChanged,
    required this.onTapAvatar,
  });

  final YtChannel draft;
  final YtChannel base;
  final List<YtCategory> categories;

  /// 原本的名稱：頻道紀錄裡最早那次改名之前的名字，沒改過名就是進編輯時
  /// 的名字（2026-10-12 使用者要求：改過名也要知道原本叫啥）。
  final String originalName;
  final ValueChanged<YtChannel> onChanged;
  final VoidCallback onTapAvatar;

  @override
  State<YtChannelEditHeader> createState() => _YtChannelEditHeaderState();
}

enum _Field { name, category, url, description }

class _YtChannelEditHeaderState extends State<YtChannelEditHeader> {
  _Field? _field;
  late final _name = TextEditingController(text: widget.draft.name);
  late final _url = TextEditingController(text: widget.draft.url);
  late final _description = TextEditingController(
    text: widget.draft.description,
  );

  @override
  void didUpdateWidget(YtChannelEditHeader old) {
    super.didUpdateWidget(old);
    // 頁面按了「還原」：輸入框跟著變回去。
    void sync(TextEditingController c, String v) {
      if (c.text != v) c.text = v;
    }

    sync(_name, widget.draft.name);
    sync(_url, widget.draft.url);
    sync(_description, widget.draft.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _description.dispose();
    super.dispose();
  }

  void _open(_Field f) => setState(() => _field = _field == f ? null : f);
  void _close() => setState(() => _field = null);

  YtChannel get _d => widget.draft;
  YtChannel get _b => widget.base;

  @override
  Widget build(BuildContext context) {
    final category = widget.categories
        .where((c) => c.id == _d.categoryId)
        .firstOrNull;
    final categoryColor = category?.color ?? AppColors.ink3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditTarget(
              changed: _d.avatarImageUrl != _b.avatarImageUrl,
              circle: true,
              onTap: () {
                _close();
                widget.onTapAvatar();
              },
              badge: Icons.photo_camera_rounded,
              child: YtChannelAvatar(channel: _d, radius: 28),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_field == _Field.name)
                    _nameInput()
                  else
                    _EditTarget(
                      changed: _d.name != _b.name,
                      onTap: () => _open(_Field.name),
                      child: Text(
                        _d.name.isEmpty ? '（沒有名稱）' : _d.name,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _EditTarget(
                        changed: _d.categoryId != _b.categoryId,
                        onTap: () => _open(_Field.category),
                        child: Text(
                          '● ${category?.name ?? '未分類'}',
                          style: AppText.note.copyWith(color: categoryColor),
                        ),
                      ),
                      if (_d.subscriberLabel != null)
                        Flexible(
                          child: Text(
                            '・${_d.subscriberLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.note,
                          ),
                        ),
                    ],
                  ),
                  if (_field == _Field.category) ...[
                    const SizedBox(height: 6),
                    _categoryPicker(),
                  ],
                  const SizedBox(height: 6),
                  if (_field == _Field.url)
                    _urlInput()
                  else
                    _EditTarget(
                      changed: _d.url != _b.url,
                      onTap: () => _open(_Field.url),
                      child: Text(
                        _d.url.isEmpty ? '＋ 加頻道網址' : _d.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.note.copyWith(color: AppColors.accent),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        const PanelLabel('簡介'),
        const SizedBox(height: Gap.xs),
        if (_field == _Field.description)
          _descriptionInput()
        else
          _EditTarget(
            changed: _d.description != _b.description,
            onTap: () => _open(_Field.description),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                _d.description.isEmpty ? '＋ 加簡介' : _d.description,
                style: _d.description.isEmpty
                    ? AppText.bodyDim.copyWith(color: AppColors.accent)
                    : AppText.bodyDim,
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration({Widget? suffix, String? hint}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFF161622),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        counterText: '',
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(maxWidth: 210),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      );

  Widget _doneButton() => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: TextButton(
      onPressed: _close,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: const Text('好'),
    ),
  );

  Widget _nameInput() {
    final showOriginal = _name.text.trim() != widget.originalName;
    return TextField(
      controller: _name,
      autofocus: true,
      maxLength: 30,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(_d.copyWith(name: v));
      },
      onSubmitted: (_) => _close(),
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      decoration: _inputDecoration(
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showOriginal)
              Flexible(
                child: _OriginalNameChip(
                  name: widget.originalName,
                  onTap: () {
                    _name.text = widget.originalName;
                    setState(() {});
                    widget.onChanged(_d.copyWith(name: widget.originalName));
                  },
                ),
              ),
            _doneButton(),
          ],
        ),
      ),
    );
  }

  Widget _urlInput() => TextField(
    controller: _url,
    autofocus: true,
    onChanged: (v) => widget.onChanged(_d.copyWith(url: v)),
    onSubmitted: (_) => _close(),
    style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
    decoration: _inputDecoration(
      hint: 'https://www.youtube.com/@…',
      suffix: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 貼上鈕（2026-09-29 使用者要求：不用整段刪掉重打）。
          IconButton(
            tooltip: '貼上',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.content_paste_go_rounded, size: 18),
            onPressed: () async {
              String? text;
              try {
                text = (await Clipboard.getData(
                  Clipboard.kTextPlain,
                ))?.text?.trim();
              } catch (_) {
                // 權限被擋、瀏覽器不支援：當沒讀到，不影響再按一次。
              }
              if (text == null || text.isEmpty) return;
              _url.text = text;
              widget.onChanged(_d.copyWith(url: text));
            },
          ),
          _doneButton(),
        ],
      ),
    ),
  );

  Widget _descriptionInput() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _description,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: 300,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(_d.copyWith(description: v));
        },
        style: AppText.bodyDim.copyWith(color: AppColors.ink),
        decoration: _inputDecoration(hint: '寫點這個頻道在幹嘛'),
      ),
      Row(
        children: [
          Text('${_description.text.length}/300', style: AppText.note),
          const Spacer(),
          _doneButton(),
        ],
      ),
    ],
  );

  Widget _categoryPicker() {
    Widget chip(String? id, String label, Color color) {
      final selected = _d.categoryId == id;
      return InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          widget.onChanged(_d.copyWith(categoryId: id));
          _close();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? color : AppColors.glassEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.ink : AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF34344C)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          chip(null, '未分類', AppColors.ink3),
          for (final c in widget.categories) chip(c.id, c.name, c.color),
        ],
      ),
    );
  }
}

/// 編輯中可以點的地方：一圈藍色虛線＋右上角小鉛筆；改過了變實線。
class _EditTarget extends StatelessWidget {
  const _EditTarget({
    required this.changed,
    required this.onTap,
    required this.child,
    this.circle = false,
    this.badge = Icons.edit_rounded,
  });

  final bool changed;
  final VoidCallback onTap;
  final Widget child;
  final bool circle;
  final IconData badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 長方形的右邊留 8 讓小鉛筆壓在框的角上、整顆都在自己範圍內：
          // 滿版的欄位（名稱很長、網址、簡介）小鉛筆才不會超出螢幕
          // （2026-10-15 使用者回報）。
          Padding(
            padding: EdgeInsets.only(right: circle ? 0 : 8),
            child: CustomPaint(
              foregroundPainter: _DashedOutline(solid: changed, circle: circle),
              child: Padding(
                padding: circle
                    ? const EdgeInsets.all(3)
                    : const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: child,
              ),
            ),
          ),
          Positioned(
            right: circle ? -2 : 0,
            top: circle ? null : -8,
            bottom: circle ? -2 : null,
            child: Container(
              width: circle ? 22 : 17,
              height: circle ? 22 : 17,
              decoration: BoxDecoration(
                color: AppColors.accentSolid,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF121219), width: 2),
              ),
              child: Icon(badge, size: circle ? 11 : 9, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.solid, required this.circle});

  final bool solid;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = solid
          ? AppColors.accent
          : AppColors.accent.withValues(alpha: 0.5);
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(circle ? size.shortestSide / 2 : 8),
        ),
      );
    if (solid) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.solid != solid || old.circle != circle;
}

/// 名稱輸入框右邊的「（原本：…）」（2026-10-12 使用者要求）。太長就
/// 「…」，滑過看完整名稱；點一下把名稱改回原本的。
class _OriginalNameChip extends StatelessWidget {
  const _OriginalNameChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '原本叫「$name」，點一下改回來',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            '（原本：$name）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.note.copyWith(color: AppColors.ink3),
          ),
        ),
      ),
    );
  }
}
