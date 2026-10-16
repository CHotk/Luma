import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../data/export/file_download.dart';
import '../../shared/widgets/app_notice.dart';
import 'jp_light_data.dart';

/// 點亮考試全對、回到櫻花樹時跳出來的慶祝（2026-10-16 使用者要求，照設計稿
/// `design-history/已選擇完成/點亮/2026-10-16_日文櫻花點亮重新設計五版.html` 第 7 版）：
/// 一朵 → 畫面中間粉色毛玻璃鼓勵卡；10 朵全開 → 整頁「満開」。兩種都能
/// 「記錄」：畫成一張 1080×1920 的圖，手機叫分享（存照片）、電腦下載。
const _art = 'assets/images/jp_light';

/// 日本賞櫻講開了幾成：咲き始め → 三分咲き → 五分咲き → 八分咲き → 満開。
(String, String) jpBloomStage(int n) => n >= 10
    ? ('満開', '全部開花')
    : n >= 8
    ? ('八分咲き', '快滿開了')
    : n >= 5
    ? ('五分咲き', '開了一半')
    : n >= 3
    ? ('三分咲き', '開始有顏色')
    : n >= 1
    ? ('咲き始め', '剛開始開花')
    : ('つぼみ', '還是花苞');

/// 第幾朵花開的時候講的話（每一朵不一樣）。
const _cheer = {
  1: '第一朵花開了！萬事起頭難，你已經跨過最難的那一步。',
  2: '第二朵！節奏抓到了，照這樣一行一行來就好。',
  3: '三分咲き——樹開始有顏色了，遠遠看得出是櫻花樹囉。',
  4: '四朵了。回頭看第一朵，是不是覺得那時候好難？',
  5: '五分咲き！一半的五十音已經是你的了 🎉',
  6: '六朵。後面的行比較少人記得住，你正在超車。',
  7: '七朵！剩下三行，終點看得到了。',
  8: '八分咲き，整棵樹粉成一片，再兩朵就滿開。',
  9: '只差最後一朵，就是満開了！最後一哩路衝一波 💪',
};

String _speedLine(int? d) => d == null
    ? ''
    : d <= 3
    ? '只花 $d 天就開了，這行對你很友善！'
    : d <= 10
    ? '練了 $d 天開花，穩穩的。'
    : '磨了 $d 天終於開了，堅持真的有回報。';

/// 剛開花的那一行要不要慶祝：開過花、最後一次開花在幾分鐘內（從考試結束
/// 按「看櫻花樹」過來）。
bool jpShouldCelebrate(JpRowLight l) =>
    l.bloomTimes.isNotEmpty &&
    DateTime.now().difference(l.bloomTimes.last) < const Duration(minutes: 30);

Future<void> showBloomCelebration(
  BuildContext context,
  List<JpRowLight> lights,
  JpRowLight l,
) {
  final n = lights.where((x) => x.lit).length;
  final all = n == lights.length;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '關閉',
    barrierColor: all ? Colors.transparent : const Color(0x8C14060F),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.85,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
    pageBuilder: (dialog, _, _) => all
        ? _FullBloom(lights: lights, last: l)
        : _BloomCard(lights: lights, l: l),
  );
}

Future<void> _keep(
  BuildContext context,
  List<JpRowLight> lights,
  JpRowLight l,
) async {
  try {
    final png = await renderBloomKeepsake(lights, l);
    final all = lights.every((x) => x.lit);
    final d = DateTime.now();
    final name =
        '${all ? '満開' : '${l.row}行開花'}_${d.year}-${d.month}-${d.day}.png';
    final ok = await shareOrSaveImage(name, png);
    if (context.mounted) {
      showAppNotice(context, ok ? '📸 已存成圖片' : '這個裝置還不能存圖');
    }
  } catch (e) {
    if (context.mounted) showAppNotice(context, '存圖失敗：$e');
  }
}

class _BloomCard extends StatelessWidget {
  const _BloomCard({required this.lights, required this.l});

  final List<JpRowLight> lights;
  final JpRowLight l;

  @override
  Widget build(BuildContext context) {
    final n = lights.where((x) => x.lit).length;
    final st = jpBloomStage(n);
    final again = l.bloomTimes.length > 1;
    final next = jpNextLightRow(lights);
    const ink = Color(0xFFFFF4F8);
    Widget fact(String k, String v) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              k,
              style: const TextStyle(fontSize: 11, color: Color(0xBFFFF0F6)),
            ),
            Text(
              v,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
    Widget btn(String label, VoidCallback onTap, {bool main = false}) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: main
                    ? const Color(0xFFFF7FA3)
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 74, 20, 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x57FFC8DE), Color(0x33FF78A5)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              again ? '${l.row}行 又開了一次！' : '${l.row}行 開花！',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color(0x99FF5A8C),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                again
                                    ? '第 ${l.bloomTimes.length} 次開花・維持手感'
                                    : '第 $n 朵・${st.$1}（${st.$2}）',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              again ? '開過的花再考一次 100 分，記得更牢了。' : _cheer[n] ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: ink,
                              ),
                            ),
                            if (!again && l.daysToLight != null)
                              Text(
                                _speedLine(l.daysToLight),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xCCFFF4F8),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                fact('花了', '${l.daysToLight ?? 1} 天'),
                                const SizedBox(width: 8),
                                fact('手寫', '${l.practiceCount} 次'),
                                const SizedBox(width: 8),
                                fact('嘗試點亮', '${l.attempts} 次'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                btn('📸 記錄', () => _keep(context, lights, l)),
                                if (next != null) ...[
                                  const SizedBox(width: 8),
                                  btn('點亮 $next行 →', () {
                                    Navigator.of(context).pop();
                                    context.push(
                                      '/kana-exam/start',
                                      extra: next,
                                    );
                                  }, main: true),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -58,
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.2, end: 1),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) => Transform.rotate(
                        angle: (1 - v) * -1,
                        child: Transform.scale(scale: v, child: child),
                      ),
                      child: Image.asset(
                        '$_art/bloom${lights.indexOf(l) % 4 + 1}.png',
                        width: 130,
                        height: 130,
                      ),
                    ),
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

/// 10 朵全開：整頁金粉色「満開」＋花瓣暴風＋總結卡。
class _FullBloom extends StatefulWidget {
  const _FullBloom({required this.lights, required this.last});

  final List<JpRowLight> lights;
  final JpRowLight last;

  @override
  State<_FullBloom> createState() => _FullBloomState();
}

class _FullBloomState extends State<_FullBloom>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lights = widget.lights;
    final firsts = [for (final l in lights) l.firstAt].whereType<DateTime>();
    final firstAt = firsts.isEmpty
        ? null
        : firsts.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastAt = lights
        .map((l) => l.litAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final days = firstAt == null
        ? 1
        : math.max(1, (lastAt.difference(firstAt).inHours / 24).ceil());
    final practice = lights.fold(0, (s, l) => s + l.practiceCount);
    final attempts = lights.fold(0, (s, l) => s + l.attempts);
    Widget fact(String k, String v) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k,
              style: const TextStyle(fontSize: 11, color: Color(0xBFFFF0F6)),
            ),
            Text(
              v,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.3),
                  radius: 0.9,
                  colors: [Color(0x61FFD696), Color(0xE0320822)],
                ),
              ),
            ),
          ),
          // 花瓣暴風
          IgnorePointer(
            child: LayoutBuilder(
              builder: (context, box) => AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Stack(
                  children: [
                    for (var k = 0; k < 34; k++)
                      () {
                        final period = 3 + (k % 5) * 0.7;
                        final t = ((_c.value * 30 + k * 0.37) / period) % 1;
                        final size = 16.0 + (k % 4) * 6;
                        return Positioned(
                          left: (k * 37) % math.max(1, box.maxWidth) - 80 * t,
                          top: -30 + (box.maxHeight + 60) * t,
                          child: Opacity(
                            opacity: (t < 0.08 ? t / 0.08 : 1 - 0.8 * t).clamp(
                              0,
                              1,
                            ),
                            child: Transform.rotate(
                              angle: t * 4 * math.pi,
                              child: Image.asset(
                                '$_art/petal${k % 3 + 1}.png',
                                width: size,
                                height: size,
                              ),
                            ),
                          ),
                        );
                      }(),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '満開',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Color(0xE6FFC878), blurRadius: 30),
                            Shadow(color: Color(0xCCFF5A8C), blurRadius: 20),
                          ],
                        ),
                      ),
                      const Text(
                        '五十音 10 行，全部開花',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFE7B0),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '從「あ」第一筆開始，到最後一朵 ${widget.last.row}行開花。\n'
                        '這棵樹上的每一朵，都是你一個字一個字寫出來的。\n'
                        '辛苦了，也恭喜你 🌸',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.7,
                          color: Color(0xFFFFF4F8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0x24FFF0F6),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    fact('第一朵到滿開', '$days 天'),
                                    const SizedBox(width: 8),
                                    fact('嘗試點亮', '$attempts 次'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    fact('手寫練習', '$practice 次'),
                                    const SizedBox(width: 8),
                                    fact(
                                      '開花',
                                      '${lights.fold(0, (s, l) => s + l.bloomTimes.length)} 次',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    for (final l in lights) ...[
                                      if (l != lights.first)
                                        const SizedBox(width: 4),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xD9FF7FA3),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            l.row,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: const Text('回到樹下'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  _keep(context, lights, widget.last),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF7FA3),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: const Text('📸 留個紀念'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 存圖：直接用 Canvas 畫一張 1080×1920（跟設計稿同一套版面）──────────

/// 10 團花苞在 tree.png（原圖 1024×1536）上的位置，跟 GPT 版畫面同一組。
const _buds = [
  Offset(150, 1090),
  Offset(885, 1110),
  Offset(130, 870),
  Offset(935, 850),
  Offset(215, 610),
  Offset(805, 635),
  Offset(245, 355),
  Offset(775, 365),
  Offset(615, 320),
  Offset(490, 215),
];

Future<ui.Image> _img(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

void _text(
  Canvas c,
  String s,
  Offset at,
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w800,
  TextAlign align = TextAlign.center,
  double width = 1080,
  List<Shadow>? shadows,
}) {
  final p = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        shadows: shadows,
      ),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: width, maxWidth: width);
  p.paint(c, at);
}

Future<List<int>> renderBloomKeepsake(
  List<JpRowLight> lights,
  JpRowLight row,
) async {
  const w = 1080.0, h = 1920.0;
  final all = lights.every((l) => l.lit);
  final n = lights.where((l) => l.lit).length;
  final bg = await _img('$_art/bg.jpg');
  final tree = await _img('$_art/tree.png');
  final blooms = [for (var k = 1; k <= 4; k++) await _img('$_art/bloom$k.png')];
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  // 背景（cover）
  final sc = math.max(w / bg.width, h / bg.height);
  final bw = bg.width * sc, bh = bg.height * sc;
  paintImage(
    canvas: c,
    rect: Rect.fromLTWH((w - bw) / 2, (h - bh) / 2, bw, bh),
    image: bg,
  );
  // 樹＋開了的花
  const ty = 330.0, ts = w / 1024;
  paintImage(
    canvas: c,
    rect: const Rect.fromLTWH(0, ty, w, w * 1.5),
    image: tree,
  );
  const bs = 74 / 390 * w;
  for (var i = 0; i < lights.length && i < _buds.length; i++) {
    if (!lights[i].lit) continue;
    final b = _buds[i];
    paintImage(
      canvas: c,
      rect: Rect.fromCenter(
        center: Offset(b.dx * ts, ty + b.dy * ts - 9 / 390 * w),
        width: bs,
        height: bs,
      ),
      image: blooms[i % 4],
    );
  }
  // 上面壓暗＋金色光暈
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, 700),
    Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 700), [
        const Color(0xD91E081E),
        const Color(0x001E081E),
      ]),
  );
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, 800),
    Paint()
      ..shader = ui.Gradient.radial(const Offset(w / 2, 250), 520, [
        const Color(0x73FFD696),
        const Color(0x00FFD696),
      ]),
  );
  final st = jpBloomStage(n);
  _text(
    c,
    all ? '満開' : '${row.row}行 開花',
    const Offset(0, 120),
    all ? 210 : 160,
    weight: FontWeight.w900,
    shadows: const [Shadow(color: Color(0xE6FF78A0), blurRadius: 40)],
  );
  _text(
    c,
    all ? '五十音 10 行，全部開花' : '第 $n 朵・${st.$1}',
    const Offset(0, 380),
    46,
    color: const Color(0xFFFFE7B0),
  );
  // 下面總結卡
  c.drawRect(
    const Rect.fromLTWH(0, h - 620, w, 620),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, h - 620),
        const Offset(0, h),
        [
          const Color(0x00280A22),
          const Color(0xBF280A22),
          const Color(0xEB280A22),
        ],
        [0, 0.35, 1],
      ),
  );
  final d = DateTime.now();
  _text(
    c,
    'Lume・五十音櫻花樹・${d.year}/${d.month}/${d.day}',
    const Offset(0, h - 500),
    28,
    color: const Color(0x99FFF0F6),
    weight: FontWeight.w500,
  );
  final facts = all
      ? [
          ('嘗試點亮', '${lights.fold(0, (s, l) => s + l.attempts)} 次'),
          ('手寫練習', '${lights.fold(0, (s, l) => s + l.practiceCount)} 次'),
          ('開花', '${lights.fold(0, (s, l) => s + l.bloomTimes.length)} 次'),
          ('全部', '10 行'),
        ]
      : [
          ('從開始練到開花', '${row.daysToLight ?? 1} 天'),
          ('手寫練習', '${row.practiceCount} 次'),
          ('嘗試點亮', '${row.attempts} 次'),
          ('開花', '${row.bloomTimes.length} 次'),
        ];
  for (var j = 0; j < facts.length; j++) {
    final x = 70.0 + (j % 2) * 480, y = h - 430 + (j ~/ 2) * 150;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 460, 130),
        const Radius.circular(28),
      ),
      Paint()..color = const Color(0x24FFFFFF),
    );
    _text(
      c,
      facts[j].$1,
      Offset(x + 32, y + 22),
      32,
      color: const Color(0xBFFFF0F6),
      weight: FontWeight.w500,
      align: TextAlign.left,
      width: 400,
    );
    _text(
      c,
      facts[j].$2,
      Offset(x + 32, y + 62),
      48,
      weight: FontWeight.w900,
      align: TextAlign.left,
      width: 400,
    );
  }
  for (var i = 0; i < lights.length; i++) {
    const cw = 86.0;
    final x = 70 + i * (cw + 9.5), y = h - 140;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, cw, 64),
        const Radius.circular(16),
      ),
      Paint()
        ..color = lights[i].lit
            ? const Color(0xE6FF7FA3)
            : const Color(0x99140E1C),
    );
    _text(
      c,
      lights[i].row,
      Offset(x, y + 8),
      36,
      weight: FontWeight.w900,
      width: cw,
    );
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
