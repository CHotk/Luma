import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../data/repositories/jp_light_style_store.dart';
import '../kana_practice/gojuon_data.dart';
import 'jp_bloom_record_view.dart';
import 'jp_light_data.dart';
import 'jp_light_gpt_view.dart';

/// 五十音櫻花樹（2026-10-15 使用者選設計稿
/// `design-history/已選擇完成/2026-10-15_日文點亮進度五種設計.html` 第 4 版）：
/// 一棵樹、樹枝上 10 個花苞（あ～わ行），點亮一行開一朵。點花看那一行的
/// 數字，「開始點亮」直接進那一行的點亮考試。
///
/// 2026-10-16 起預設是 GPT 圖版（[JpLightGptBody]），原本這版保留，右上
/// 角或設定裡可以切回來（[JpLightStyle]）。
class JpLightPage extends ConsumerWidget {
  const JpLightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jpLightProvider);
    final style = ref.watch(jpLightStyleProvider);
    final gpt = style == JpLightStyle.gpt;
    final swap = IconButton(
      onPressed: () async {
        final next = gpt ? JpLightStyle.classic : JpLightStyle.gpt;
        ref.read(jpLightStyleProvider.notifier).state = next;
        await JpLightStyleStore(ref.read(keyValueStoreProvider)).save(next);
      },
      icon: const Icon(Icons.swap_horiz_rounded, size: 22),
      color: AppColors.ink2,
      tooltip: gpt ? '換成原本的樹枝版' : '換成 GPT 圖版',
      visualDensity: VisualDensity.compact,
    );
    if (gpt) {
      return Scaffold(
        drawer: const AppSideDrawer(),
        backgroundColor: const Color(0xFF2A1838),
        body: Stack(
          children: [
            const Positioned.fill(child: JpLightGptBackground()),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.screenSide,
                    ),
                    child: AppTopBar(title: '🌸 五十音櫻花樹', actions: [swap]),
                  ),
                  Expanded(
                    child: switch (async) {
                      AsyncData(:final value) => JpLightGptBody(lights: value),
                      AsyncError(:final error) => Center(
                        child: Text('讀不到紀錄：$error', style: AppText.bodyDim),
                      ),
                      _ => const Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(title: '🌸 五十音櫻花樹', actions: [swap]),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: switch (async) {
                    AsyncData(:final value) => _Body(lights: value),
                    AsyncError(:final error) => Center(
                      child: Text('讀不到紀錄：$error', style: AppText.bodyDim),
                    ),
                    _ => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.lights});

  final List<JpRowLight> lights;

  @override
  Widget build(BuildContext context) {
    final lit = lights.where((l) => l.lit).length;
    final close = lights.where((l) => !l.lit && l.exams > 0).toList()
      ..sort((a, b) => b.best.compareTo(a.best));
    return ListView(
      padding: EdgeInsets.only(bottom: FloatingNavInset.of(context) + Gap.lg),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$lit',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: AppColors.jpAccent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('/ ${lights.length} 行開花', style: AppText.note),
                ],
              ),
              const SizedBox(height: Gap.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: lights.isEmpty ? 0 : lit / lights.length,
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: AppColors.jpAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        AspectRatio(
          aspectRatio: 362 / 430,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1222), Color(0xFF0F0F18)],
                ),
                border: Border.all(color: AppColors.glassEdge),
                borderRadius: BorderRadius.circular(22),
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final sx = box.maxWidth / 362, sy = box.maxHeight / 430;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _BranchPainter()),
                      ),
                      for (
                        var i = 0;
                        i < lights.length && i < _spots.length;
                        i++
                      )
                        Positioned(
                          left: _spots[i].dx * sx - 28,
                          top: _spots[i].dy * sy - 28,
                          child: _Bloom(
                            light: lights[i],
                            onTap: () => _showRow(context, lights[i], lights),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (close.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('快開花了', style: AppText.note),
          ),
          for (final l in close.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.card),
                  onTap: () => _showRow(context, l, lights),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          l.row,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 最好成績留在資料裡但不顯示（2026-10-16 使用者
                              // 要求：開花不難，不用秀）。
                              Text(
                                '考過 ${l.exams} 次'
                                '${l.lastWrong.isEmpty ? '' : '・還錯 ${l.lastWrong.join()}'}',
                                style: AppText.note,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.ink3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 10 個花苞在樹上的位置（設計稿 362×430 的座標，畫的時候照實際大小縮放）。
const _spots = [
  Offset(181, 52),
  Offset(112, 100),
  Offset(250, 104),
  Offset(62, 168),
  Offset(172, 158),
  Offset(292, 180),
  Offset(112, 232),
  Offset(232, 240),
  Offset(72, 306),
  Offset(282, 306),
];

class _BranchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 362, sy = size.height / 430;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    final paint = Paint()
      ..color = const Color(0xFF5A3A2A)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void curve(List<double> c) {
      final path = Path()..moveTo(p(c[0], c[1]).dx, p(c[0], c[1]).dy);
      path.cubicTo(
        p(c[2], c[3]).dx,
        p(c[2], c[3]).dy,
        p(c[4], c[5]).dx,
        p(c[4], c[5]).dy,
        p(c[6], c[7]).dx,
        p(c[6], c[7]).dy,
      );
      canvas.drawPath(path, paint);
    }

    // 樹幹
    curve([181, 430, 176, 370, 186, 300, 181, 260]);
    canvas.drawLine(p(181, 270), p(181, 52), paint..strokeWidth = 6);
    paint.strokeWidth = 5;
    // 樹枝：從樹幹接到每個花苞
    curve([181, 280, 140, 255, 100, 250, 72, 306]);
    curve([181, 280, 230, 262, 262, 270, 282, 306]);
    curve([181, 230, 140, 200, 110, 182, 62, 168]);
    curve([181, 220, 220, 205, 270, 195, 292, 180]);
    curve([181, 182, 160, 145, 140, 120, 112, 100]);
    curve([181, 172, 210, 140, 230, 120, 250, 104]);
    curve([181, 212, 200, 228, 220, 236, 232, 240]);
    curve([181, 222, 155, 226, 135, 230, 112, 232]);
    curve([181, 175, 178, 168, 175, 162, 172, 158]);
  }

  @override
  bool shouldRepaint(_BranchPainter oldDelegate) => false;
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.light, required this.onTap});

  final JpRowLight light;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lit = light.lit;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: lit ? 0.6 : 1, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: lit
                ? const RadialGradient(
                    colors: [
                      Colors.white,
                      Color(0xFFFFC2D4),
                      Color(0xFFFF8FB1),
                    ],
                    stops: [0.12, 0.55, 1],
                  )
                : null,
            color: lit ? null : const Color(0xFF2C2333),
            border: lit
                ? null
                : Border.all(color: const Color(0xFF4A3A50), width: 2),
            boxShadow: lit
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF8FB1).withValues(alpha: 0.6),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Text(
            light.row,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: lit ? const Color(0xFF6A1030) : const Color(0xFF7A6A80),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行的明細：開了沒、花了幾天、練幾次、寫多久、考幾次、最好幾 %、還錯
/// 哪幾個字，最下面直接「開始點亮」。
void _showRow(BuildContext context, JpRowLight l, List<JpRowLight> lights) {
  String md(DateTime d) => '${d.month}/${d.day}';
  // 只能照順序點亮（2026-10-16），還沒輪到的按鈕鎖住。
  final lockedBy = jpCanLight(lights, l.row) ? null : jpNextLightRow(lights);
  final kana = gojuonRows[l.row]!.map((k) => k.$1).join(' ');
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C29),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l.row,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: l.lit ? AppColors.jpAccent : AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.row}行',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(kana, style: AppText.note),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              l.lit
                  ? '🌸 ${md(l.litAt!)} 開花・從第一次練到開花花了 ${l.daysToLight} 天'
                  : l.firstAt == null
                  ? '還沒開始：先手寫練幾次，再用點亮考一次'
                  : '還沒開花・從 ${md(l.firstAt!)} 開始練'
                        '${l.exams > 0 ? '，考過 ${l.exams} 次' : ''}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: l.lit ? AppColors.jpAccent : AppColors.ink,
              ),
            ),
            const SizedBox(height: Gap.md),
            // 數字是第一次開花當下的快照（2026-10-16 使用者要求），還沒開花就
            // 沒有快照、先不顯示；嘗試點亮跟開花次數本來就算到現在。
            if (l.record != null) ...[
              Row(
                children: [
                  _Fact('手寫練習', '${l.record!.practiceCount} 次'),
                  const SizedBox(width: 8),
                  _Fact('普通考試', '${l.record!.examAnswers} 次'),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                _Fact('嘗試點亮', '${l.attempts} 次'),
                const SizedBox(width: 8),
                _Fact(
                  '開花次數',
                  l.bloomTimes.isEmpty ? '還沒開過' : '${l.bloomTimes.length} 次',
                ),
              ],
            ),
            if (l.record != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [_Fact('全部次數（手寫＋考試，寫一次算一次）', '${l.record!.total} 次')],
              ),
              const SizedBox(height: Gap.md),
              JpBloomRecordView(
                record: l.record!,
                ink: AppColors.ink,
                dim: AppColors.ink2,
                fill: Colors.white.withValues(alpha: 0.05),
              ),
            ],
            if (l.lastWrong.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              Text('上次還錯的字', style: AppText.note),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final k in l.lastWrong)
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFF6B6B)),
                      ),
                      child: Text(
                        k,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFFFF9A9A),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: lockedBy != null
                  ? null
                  : () {
                      Navigator.of(sheet).pop();
                      context.push('/kana-exam/start', extra: l.row);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.jpAccent,
                foregroundColor: AppColors.jpAccentInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                lockedBy != null
                    ? '🔒 先點亮 $lockedBy行'
                    : l.lit
                    ? '再考一次（${jpLightExamSize(l.row)} 題）'
                    : '開始點亮 ${l.row}行（${jpLightExamSize(l.row)} 題）',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.note),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}
