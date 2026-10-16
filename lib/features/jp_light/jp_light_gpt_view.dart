import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../kana_practice/gojuon_data.dart';
import 'jp_bloom_record_view.dart';
import 'jp_light_data.dart';

/// 五十音櫻花樹的 GPT 圖版（2026-10-16 使用者要求預設用這版，設計稿
/// `design-history/2026-10-16_日文櫻花點亮重新設計五版.html` 第 6 版）：
/// ChatGPT 產的黃昏背景＋光禿的樹，開了的行在那一團花苞疊上盛開的花，
/// 每團花掛行名牌子，下面一排對照表，點花從畫面正中間跳出粉色毛玻璃卡片。
///
/// 圖在 `assets/images/jp_light/app/`（原圖縮小過；原圖留在
/// `assets/images/jp_light/` 跟 `design-history/assets/jp_light/`）。
const _art = 'assets/images/jp_light/app';

/// 背景，整頁鋪滿（給 [JpLightPage] 墊在最底下）。
class JpLightGptBackground extends StatelessWidget {
  const JpLightGptBackground({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1838), Color(0xFF4A2448), Color(0xFF2A1A24)],
          ),
        ),
      ),
      Image.asset('$_art/bg.jpg', fit: BoxFit.cover),
      // 上面壓暗一點，標題跟數字才看得清楚。
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Color(0x99140A1C), Color(0x00140A1C)],
          ),
        ),
      ),
    ],
  );
}

/// 10 團花苞在 tree.png 上的位置（原圖 1024×1536 的座標，設計稿對位模式
/// 量的）。順序 あ か さ た な は ま や ら わ。
const _buds = [
  Offset(490, 215),
  Offset(245, 355),
  Offset(615, 320),
  Offset(775, 365),
  Offset(215, 610),
  Offset(805, 635),
  Offset(130, 870),
  Offset(935, 850),
  Offset(150, 1090),
  Offset(885, 1110),
];

/// 牌子相對花苞中心放哪（設計稿 390 寬時的 px）：預設正下方；あ行在最
/// 上面、下面緊貼著さ行，牌子改放上面。
const _tagOff = [
  Offset(0, -64),
  Offset(0, 34),
  Offset(0, 34),
  Offset(8, 34),
  Offset(0, 34),
  Offset(0, 34),
  Offset(0, 34),
  Offset(-6, 34),
  Offset(0, 34),
  Offset(0, 34),
];

class JpLightGptBody extends StatefulWidget {
  const JpLightGptBody({super.key, required this.lights});

  final List<JpRowLight> lights;

  @override
  State<JpLightGptBody> createState() => _JpLightGptBodyState();
}

class _JpLightGptBodyState extends State<JpLightGptBody> {
  /// 對照表點到的那一行（樹上那一團閃）；再點一次開明細。
  int? _hl;

  @override
  Widget build(BuildContext context) {
    final lights = widget.lights;
    final lit = lights.where((l) => l.lit).length;
    return Stack(
      children: [
        Positioned.fill(child: _PetalRain(count: 3 + lit * 2)),
        ListView(
          padding: EdgeInsets.only(
            bottom: FloatingNavInset.of(context) + Gap.lg,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$lit',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFFD3E0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '/ ${lights.length} 朵開花',
                    style: const TextStyle(fontSize: 14, color: _ink2),
                  ),
                  const Spacer(),
                  const JpExamTimeText(
                    style: TextStyle(fontSize: 12, color: _ink2),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 2 / 3,
              child: LayoutBuilder(
                builder: (context, box) => _tree(box.maxWidth, lights),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < lights.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(child: _legendChip(i, lights[i])),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '點花或下面的字看那一行',
                style: TextStyle(fontSize: 12, color: _ink2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tree(double w, List<JpRowLight> lights) {
    final s = w / 1024; // 原圖座標 → 畫面
    final u = w / 390; // 設計稿 px → 畫面
    final n = math.min(lights.length, _buds.length);
    final bloom = 74 * u, tap = 54 * u;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: Image.asset('$_art/tree.png')),
        for (var i = 0; i < n; i++) ...[
          if (lights[i].lit)
            Positioned(
              left: _buds[i].dx * s - bloom / 2,
              top: _buds[i].dy * s - 9 * u - bloom / 2,
              width: bloom,
              height: bloom,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Image.asset('$_art/bloom${i % 4 + 1}.png'),
                ),
              ),
            ),
          if (_hl == i)
            Positioned(
              left: _buds[i].dx * s - 40 * u,
              top: _buds[i].dy * s - 40 * u,
              width: 80 * u,
              height: 80 * u,
              child: const IgnorePointer(child: _Ping()),
            ),
          Positioned(
            left: _buds[i].dx * s - tap / 2,
            top: _buds[i].dy * s - tap / 2,
            width: tap,
            height: tap,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(lights[i]),
            ),
          ),
        ],
        // 牌子另外一層畫在所有花團上面，花再大也蓋不到。
        for (var i = 0; i < n; i++)
          Positioned(
            left: _buds[i].dx * s + _tagOff[i].dx * u,
            top: _buds[i].dy * s + _tagOff[i].dy * u,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: GestureDetector(
                onTap: () => _open(lights[i]),
                child: _Tag(light: lights[i], highlighted: _hl == i),
              ),
            ),
          ),
      ],
    );
  }

  Widget _legendChip(int i, JpRowLight l) {
    final hl = _hl == i;
    return GestureDetector(
      onTap: () {
        if (_hl == i) {
          setState(() => _hl = null);
          _open(l);
        } else {
          setState(() => _hl = i);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: l.lit ? const Color(0xD9FF7FA3) : const Color(0x99140E1C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hl
                ? const Color(0xFFFFE08A)
                : Colors.white.withValues(alpha: l.lit ? 0.5 : 0.12),
            width: hl ? 2 : 1,
          ),
        ),
        child: Text(
          l.row,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: l.lit ? Colors.white : const Color(0xFF8A7F96),
          ),
        ),
      ),
    );
  }

  void _open(JpRowLight l) {
    setState(() => _hl = null);
    _showRowGlass(context, l, widget.lights);
  }
}

const _ink2 = Color(0xFFE6D6E2);

class _Tag extends StatelessWidget {
  const _Tag({required this.light, required this.highlighted});

  final JpRowLight light;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final lit = light.lit;
    final Color bg, fg, edge;
    if (highlighted) {
      (bg, fg, edge) = (
        const Color(0xFFFFE08A),
        const Color(0xFF3A2400),
        Colors.white,
      );
    } else if (lit) {
      (bg, fg, edge) = (
        const Color(0xEBFF7FA3),
        Colors.white,
        Colors.white.withValues(alpha: 0.6),
      );
    } else {
      (bg, fg, edge) = (
        const Color(0xB8140E1C),
        const Color(0xFFB9AFC4),
        Colors.white.withValues(alpha: 0.18),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: edge),
        boxShadow: lit && !highlighted
            ? [
                BoxShadow(
                  color: const Color(0xFFFF5A8C).withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        '${lit ? '🌸 ' : ''}${light.row}行',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// 對照表點到的那一團：一圈黃色往外擴散。
class _Ping extends StatefulWidget {
  const _Ping();

  @override
  State<_Ping> createState() => _PingState();
}

class _PingState extends State<_Ping> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Transform.scale(
      scale: 0.6 + _c.value * 1.2,
      child: Opacity(
        opacity: 0.9 * (1 - _c.value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFE08A), width: 3),
          ),
        ),
      ),
    ),
  );
}

/// 飄的花瓣：開越多朵飄越多（三張花瓣圖輪流）。
class _PetalRain extends StatefulWidget {
  const _PetalRain({required this.count});

  final int count;

  @override
  State<_PetalRain> createState() => _PetalRainState();
}

class _PetalRainState extends State<_PetalRain>
    with SingleTickerProviderStateMixin {
  // 一圈 60 秒，每片花瓣用自己的速度在裡面繞好幾趟。
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          children: [for (var k = 0; k < widget.count; k++) _petal(k, box)],
        ),
      ),
    ),
  );

  Widget _petal(int k, BoxConstraints box) {
    final period = 6.0 + k % 5; // 秒，掉一趟
    final t = ((_c.value * 60 + k * 1.3) / period) % 1;
    final x = (k * 47) % math.max(1, box.maxWidth - 20) + 60 * t;
    final y = -20 + (box.maxHeight + 40) * t;
    final opacity = t < 0.1 ? t * 9 : 0.9 * (1 - (t - 0.1) / 0.9);
    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.rotate(
          angle: t * 3 * math.pi,
          child: Image.asset(
            '$_art/petal${k % 3 + 1}.png',
            width: 22,
            height: 22,
          ),
        ),
      ),
    );
  }
}

/// 一行的明細，從畫面正中間跳出粉色毛玻璃卡片（2026-10-16 使用者要求：
/// 不要從底部跳出）。內容跟原本版的明細一樣，最下面直接「開始點亮」。
void _showRowGlass(
  BuildContext context,
  JpRowLight l,
  List<JpRowLight> lights,
) {
  String md(DateTime d) => '${d.month}/${d.day}';
  // 只能照順序點亮（2026-10-16），還沒輪到的按鈕鎖住。
  final lockedBy = jpCanLight(lights, l.row) ? null : jpNextLightRow(lights);
  final kana = gojuonRows[l.row]!.map((k) => k.$1).join(' ');
  const ink = Color(0xFFFFF4F8);
  const dim = Color(0xC7FFF0F6);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '關閉',
    barrierColor: const Color(0x59140814),
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.86,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
    pageBuilder: (dialog, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x4DFFBED6), Color(0x2EFF78A5)],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                l.row,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${l.row}行',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                    Text(
                                      kana,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: dim,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(dialog).pop(),
                                tooltip: '關閉',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: ink,
                                ),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          Row(
                            children: [
                              _GlassFact('手寫練習', '${l.practiceCount} 次'),
                              const SizedBox(width: 8),
                              _GlassFact('考試寫了多久', fmtPracticeTime(l.examTime)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _GlassFact('嘗試點亮', '${l.attempts} 次'),
                              const SizedBox(width: 8),
                              _GlassFact(
                                '開花次數',
                                l.bloomTimes.isEmpty
                                    ? '還沒開過'
                                    : '${l.bloomTimes.length} 次',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _GlassFact(
                                '全部次數（手寫＋考試，寫一次算一次）',
                                '${l.totalCount} 次',
                              ),
                            ],
                          ),
                          if (l.record != null) ...[
                            const SizedBox(height: Gap.md),
                            JpBloomRecordView(
                              record: l.record!,
                              ink: ink,
                              dim: dim,
                              fill: Colors.white.withValues(alpha: 0.12),
                            ),
                          ],
                          if (l.lastWrong.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            const Text(
                              '上次還錯的字',
                              style: TextStyle(fontSize: 12, color: dim),
                            ),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFFF8A8A),
                                      ),
                                    ),
                                    child: Text(
                                      k,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        color: ink,
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
                                    Navigator.of(dialog).pop();
                                    context.push(
                                      '/kana-exam/start',
                                      extra: l.row,
                                    );
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
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlassFact extends StatelessWidget {
  const _GlassFact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xC7FFF0F6)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFF4F8),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 右上角「考試寫了 N 分」：50 音、詞彙、點亮考試每題第一筆到按提交的時間
/// 加總（2026-10-16 使用者要求，手寫練習時間不算）。
class JpExamTimeText extends ConsumerWidget {
  const JpExamTimeText({super.key, required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(jpExamTimeProvider).valueOrNull ?? Duration.zero;
    return Text('考試寫了 ${fmtPracticeTime(t)}', style: style);
  }
}
