import 'package:flutter/material.dart';

import 'jp_light_data.dart';

/// 明細裡的「開花紀錄」（2026-10-16 使用者要求）：開花的時間、從第一天練
/// 到開花多久，跟到那一刻為止累加的手寫練習、普通考試、點亮通關次數。
/// 原本版（深色底）跟 GPT 版（粉色毛玻璃）共用，顏色由外面給。
class JpBloomRecordView extends StatelessWidget {
  const JpBloomRecordView({
    super.key,
    required this.record,
    required this.ink,
    required this.dim,
    required this.fill,
  });

  final JpBloomRecord record;
  final Color ink;
  final Color dim;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final r = record;
    String two(int n) => n.toString().padLeft(2, '0');
    final at = r.at;
    final when =
        '${at.year}/${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
    final d = r.span;
    final span = d.inDays > 0
        ? '${d.inDays} 天 ${d.inHours % 24} 小時'
        : d.inHours > 0
        ? '${d.inHours} 小時 ${d.inMinutes % 60} 分'
        : '${d.inMinutes} 分';
    final since = '${r.since.month}/${r.since.day}';
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(fontSize: 13, color: dim)),
          ),
          Text(
            v,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🌸 開花紀錄（到開花為止的累計）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: dim,
            ),
          ),
          const SizedBox(height: 4),
          line('開花時間', when),
          line('從第一天（$since）練到開花', span),
          line('手寫練習', '${r.practiceCount} 次'),
          line('普通考試', '${r.examRounds} 輪'),
          line('點亮通關', '${r.lightPasses} 次'),
        ],
      ),
    );
  }
}
