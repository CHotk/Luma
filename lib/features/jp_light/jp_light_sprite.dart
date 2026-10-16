import 'package:flutter/material.dart';

import '../kana_practice/gojuon_data.dart';
import 'jp_bloom_celebration.dart' show jpBloomStage;
import 'jp_light_data.dart';

/// 櫻花樹頁上面的「咲き進度條」跟「小精靈對話」（2026-10-16 使用者要求，
/// 照設計稿 `design-history/2026-10-16_日文櫻花點亮重新設計五版.html`
/// 第 7 版）。

/// 咲き進度條：日本賞櫻講開了幾成，到了就點亮那個節點。
class JpBloomStageBar extends StatelessWidget {
  const JpBloomStageBar({super.key, required this.lit, required this.total});

  final int lit;
  final int total;

  static const _marks = [
    (1, '咲き始め'),
    (3, '三分'),
    (5, '五分'),
    (8, '八分'),
    (10, '満開'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0x99140E1C),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    width: w * lit / total,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFC2D4), Color(0xFFFF7FA3)],
                      ),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(color: Color(0xB3FF7FA3), blurRadius: 10),
                      ],
                    ),
                  ),
                  for (final (k, _) in _marks)
                    Positioned(
                      left: w * k / 10 - 9,
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: lit >= k
                              ? const Color(0xFFFF7FA3)
                              : const Color(0xFF2A1E30),
                          border: Border.all(
                            color: lit >= k
                                ? Colors.white
                                : const Color(0xFF5A4458),
                            width: 1.5,
                          ),
                        ),
                        child: lit >= k
                            ? const Text('🌸', style: TextStyle(fontSize: 9))
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (k, label) in _marks)
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: lit >= k ? FontWeight.w800 : FontWeight.w400,
                      color: lit >= k
                          ? const Color(0xFFFFD3E0)
                          : const Color(0x8CFFF0F6),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// 拼詞用的小字典：只用清音（點亮的 10 行就寫得出來），片假名的「ー」不算字。
const _words = [
  ('さくら', '櫻花'),
  ('あか', '紅色'),
  ('あさ', '早上'),
  ('いす', '椅子'),
  ('うし', '牛'),
  ('えき', '車站'),
  ('かさ', '雨傘'),
  ('くつ', '鞋子'),
  ('すし', '壽司'),
  ('あし', '腳'),
  ('いけ', '池塘'),
  ('きた', '北邊'),
  ('した', '下面'),
  ('たけ', '竹子'),
  ('つくえ', '書桌'),
  ('おかし', '點心'),
  ('せかい', '世界'),
  ('あいさつ', '打招呼'),
  ('ねこ', '貓'),
  ('いぬ', '狗'),
  ('はな', '花'),
  ('なつ', '夏天'),
  ('ふね', '船'),
  ('ほし', '星星'),
  ('ひと', '人'),
  ('やま', '山'),
  ('うみ', '海'),
  ('ゆき', '雪'),
  ('はる', '春天'),
  ('よる', '晚上'),
  ('もり', '森林'),
  ('くるま', '車子'),
  ('てら', '寺廟'),
  ('ほん', '書'),
  ('わたし', '我'),
  ('おはよう', '早安'),
  ('こんにちは', '你好'),
  ('さようなら', '再見'),
  ('カメラ', '相機'),
  ('ケーキ', '蛋糕'),
  ('スキー', '滑雪'),
  ('タクシー', '計程車'),
  ('ホテル', '飯店'),
  ('トマト', '番茄'),
  ('メロン', '哈密瓜'),
  ('アニメ', '動畫'),
  ('ラーメン', '拉麵'),
];

/// 這個字在哪一行（あ／か…）；「ー」回 ''（不算）；不在 10 行裡回 null。
String? _rowOf(String ch) {
  if (ch == 'ー') return '';
  for (final e in gojuonRows.entries) {
    if (e.value.any((k) => k.$1 == ch)) return e.key;
  }
  for (final e in gojuonRowsKatakana.entries) {
    if (e.value.any((k) => k.$1 == ch)) return e.key;
  }
  return null;
}

/// 這個詞還差哪幾行沒開（有不在 10 行裡的字就回 null＝寫不出來）。
Set<String>? _needRows(String word, Set<String> lit) {
  final need = <String>{};
  for (final ch in word.split('')) {
    final r = _rowOf(ch);
    if (r == null) return null;
    if (r.isNotEmpty && !lit.contains(r)) need.add(r);
  }
  return need;
}

/// 小精靈一句話：主句、小字、（可選）詞卡、（可選）「看那一行」。
class _Tip {
  const _Tip(this.say, this.sub, {this.words, this.lockWord, this.row});

  final String say;
  final String sub;
  final List<(String, String)>? words;
  final String? lockWord;
  final String? row;
}

List<_Tip> _tips(List<JpRowLight> lights, int k) {
  final n = lights.where((l) => l.lit).length;
  final lit = {
    for (final l in lights)
      if (l.lit) l.row,
  };
  final out = <_Tip>[];
  if (n == lights.length) {
    out.add(const _Tip('滿開了！每一朵都是你自己寫出來的。', '想維持手感，偶爾點一朵再考一次就好'));
  }
  // 用開了的字能拼出什麼詞
  final can = [
    for (final w in _words)
      if (_needRows(w.$1, lit)?.isEmpty ?? false) w,
  ];
  final near = [
    for (final w in _words)
      if (_needRows(w.$1, lit)?.length == 1) w,
  ]..sort((a, b) => (b.$1 == 'さくら' ? 1 : 0) - (a.$1 == 'さくら' ? 1 : 0));
  final lock = near.isEmpty ? null : near[k % near.length];
  if (can.isEmpty) {
    if (lock != null) {
      out.add(
        _Tip(
          '開了花的字就能拼詞！再開 ${_needRows(lock.$1, lit)!.first}行，'
              '就能寫「${lock.$1}」（${lock.$2}）。',
          '先點亮一行試試',
        ),
      );
    }
  } else {
    out.add(
      _Tip(
        '你開花的字，已經能拼出 ${can.length} 個詞：',
        lock != null
            ? '再開 ${_needRows(lock.$1, lit)!.first}行，就能寫「${lock.$1}」${lock.$2}'
            : '10 行全開，清音的詞都寫得出來了',
        words: [
          for (var j = 0; j < 3 && j < can.length; j++)
            can[(k * 3 + j) % can.length],
        ],
        lockWord: lock?.$1,
      ),
    );
  }
  // 輪到的那一行（只能照順序點亮）
  final next = jpNextLightRow(lights);
  final nl = lights.where((l) => l.row == next).firstOrNull;
  if (nl != null && nl.attempts > 0) {
    out.add(
      _Tip(
        '${nl.row}行嘗試點亮 ${nl.attempts} 次'
            '${nl.lastWrong.isEmpty ? '' : '，上次錯在「${nl.lastWrong.join()}」'}'
            '——再考一次就可能開花！',
        '差一點點',
        row: nl.row,
      ),
    );
  } else if (nl != null) {
    out.add(_Tip('輪到 ${nl.row}行了。先手寫練幾次，再來點亮。', '慢慢來，一次一行就好', row: nl.row));
  }
  if (n > 0 && n < lights.length) {
    final st = jpBloomStage(n);
    out.add(_Tip('現在是「${st.$1}」，${st.$2}。', '離滿開還差 ${lights.length - n} 朵'));
  }
  return out;
}

/// 小精靈：粉色圓臉＋對話框，點一下換下一句；講到某一行時有「看 X行 →」。
/// 對話框固定高度，句子長短不會把下面的樹推來推去。
class JpLightSprite extends StatefulWidget {
  const JpLightSprite({super.key, required this.lights, required this.onRow});

  final List<JpRowLight> lights;

  /// 點「看 X行 →」：打開那一行的明細。
  final void Function(JpRowLight) onRow;

  @override
  State<JpLightSprite> createState() => _JpLightSpriteState();
}

class _JpLightSpriteState extends State<JpLightSprite>
    with SingleTickerProviderStateMixin {
  // 一打開不要每次都講同一種：照日期輪。
  int _k = DateTime.now().day;
  late final _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tips = _tips(widget.lights, _k);
    if (tips.isEmpty) return const SizedBox.shrink();
    final t = tips[_k % tips.length];
    const ink = Color(0xFFFFF4F8);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _k++),
      child: SizedBox(
        height: 104,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _bob,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -3 * _bob.value),
                  child: Transform.rotate(
                    angle: -0.07 * _bob.value,
                    child: child,
                  ),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.4),
                      colors: [
                        Colors.white,
                        Color(0xFFFFC2D4),
                        Color(0xFFFF7FA3),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                    boxShadow: [
                      BoxShadow(color: Color(0x73FF5A8C), blurRadius: 14),
                    ],
                  ),
                  child: const Text('🌸', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(t.say),
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 104),
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
                    decoration: BoxDecoration(
                      color: const Color(0x29FFF0F6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    // 萬一內容比框高，裁掉不要跑版。
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.say,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: ink,
                            ),
                          ),
                          if (t.words != null) ...[
                            const SizedBox(height: 5),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                children: [
                                  for (final (w, m) in t.words!) _word(w, m),
                                  if (t.lockWord != null)
                                    _word(t.lockWord!, '🔒', locked: true),
                                ],
                              ),
                            ),
                          ],
                          if (t.row != null) ...[
                            const SizedBox(height: 5),
                            GestureDetector(
                              onTap: () => widget.onRow(
                                widget.lights.firstWhere((l) => l.row == t.row),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF7FA3),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '看 ${t.row}行 →',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            '${t.sub}・點我換一句',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0x99FFF0F6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _word(String w, String m, {bool locked = false}) => Container(
    margin: const EdgeInsets.only(right: 5),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: locked
          ? const Color(0x73140E1C)
          : Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10),
      border: locked
          ? Border.all(color: Colors.white.withValues(alpha: 0.35))
          : null,
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: w,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: locked ? const Color(0x8CFFFFFF) : Colors.white,
            ),
          ),
          TextSpan(
            text: ' $m',
            style: const TextStyle(fontSize: 10, color: Color(0xBFFFF0F6)),
          ),
        ],
      ),
    ),
  );
}
