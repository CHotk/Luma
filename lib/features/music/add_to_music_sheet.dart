import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show appRouter;
import '../../app/theme/colors.dart';
import '../../domain/models/music.dart';
import '../../shared/widgets/app_notice.dart';
import 'music_actions.dart';
import 'music_widgets.dart';

/// 「加到音樂功能」（2026-10-19 使用者要求）：YT 管理任何分類的影片都能加。
/// 點下去先選歌手，歌名、種類從標題自動猜好（可以改），存的時候把影片資料
/// 抄一份到音樂裡——之後跟 YT 管理無關。已經在音樂裡的就直接開編輯。
Future<void> showAddToMusicSheet(
  BuildContext context,
  WidgetRef ref, {
  required String videoId,
  required String videoTitle,
  required String thumbnailUrl,
  required String channelName,
  String channelAvatarUrl = '',
  required DateTime publishedAt,
  int? durationSec,
  String? artistId,
}) async {
  final data = ref.read(musicDataProvider);
  if (data.hasVideo(videoId)) {
    await showMusicEditVersionSheet(context, ref, videoId);
    return;
  }
  final g = MusicGuess.from(
    data,
    videoTitle: videoTitle,
    channelName: channelName,
  );
  final titleC = TextEditingController(text: g.title);
  final noteC = TextEditingController();
  // 預設「演唱」（2026-10-21 使用者要求）；標題看得出是翻唱、Live、合唱、清唱的才照猜的
  var type = g.type == MusicVersionType.other ? MusicVersionType.sing : g.type;
  final yearC = TextEditingController(text: '${publishedAt.year}');
  // 從歌手頁加的：誰唱的就是那個歌手（還是可以再改）。
  var artists = artistId == null ? List<String>.of(g.artistIds) : [artistId];
  // 從歌手頁加的：原唱也預設是他（2026-10-21 使用者要求，可以改）
  var orig = artistId == null
      ? List<String>.of(g.originalArtistIds)
      : [artistId];
  final saved = await showMusicSheet<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final d = ref.read(musicDataProvider);
        final t = titleC.text.trim();
        final existing = d.works.where((w) => w.title == t).firstOrNull;
        final similar = t.isEmpty
            ? <MusicWork>[]
            : d.works
                  .where(
                    (w) =>
                        w.title != t &&
                        (w.title.contains(t) || t.contains(w.title)),
                  )
                  .take(4)
                  .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            musicSheetHandle(),
            const Text(
              '加到音樂功能',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const Text(
              '抄一份存到音樂裡，之後在 YT 管理刪掉也不影響',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
            const SizedBox(height: 8),
            musicVideoPreview(
              thumbnailUrl: thumbnailUrl,
              title: videoTitle,
              sub: '「$channelName」上傳・${publishedAt.year}',
            ),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0x1A7EA6FF),
                border: Border.all(color: const Color(0x407EA6FF)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '自動判斷：${g.why}。不對直接改',
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),
              ),
            ),
            musicFieldLabel('歌手（誰唱的，可以好幾個）'),
            MusicArtistPicker(
              selected: artists,
              onChanged: (x) => setS(() => artists = x),
            ),
            musicFieldLabel('歌名'),
            TextField(
              controller: titleC,
              onChanged: (_) => setS(() {}),
              style: const TextStyle(color: AppColors.ink, fontSize: 15),
              decoration: musicInputDecoration('例如：晴天'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                existing != null
                    ? '音樂裡已經有《${existing.title}》（${d.versionsOfWork(existing.id).length} 個版本）→ 加成它的新版本'
                    : '新的一首歌',
                style: TextStyle(
                  fontSize: 11.5,
                  color: existing != null
                      ? const Color(0xFF5FE08D)
                      : AppColors.ink3,
                ),
              ),
            ),
            if (similar.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final w in similar)
                    musicChoiceChip('是《${w.title}》？', false, () {
                      titleC.text = w.title;
                      setS(() {});
                    }, dashed: true),
                ],
              ),
            ],
            musicFieldLabel('發行年份（預設 YouTube 上傳那年，可以改）'),
            TextField(
              controller: yearC,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.ink),
              decoration: musicInputDecoration('例如：2003'),
            ),
            musicFieldLabel('備註（選填）'),
            TextField(
              controller: noteC,
              style: const TextStyle(color: AppColors.ink),
              decoration: musicInputDecoration('例如：2019 演唱會、鋼琴版'),
            ),
            musicFieldLabel('這一版是'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final x in MusicVersionType.values)
                  musicChoiceChip(
                    x.label,
                    type == x,
                    () => setS(() => type = x),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                type.hint,
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
            ),
            if (existing == null) ...[
              musicFieldLabel('原唱（新歌曲才要選，可以不選）'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in d.artists)
                    musicChoiceChip(
                      a.name,
                      orig.contains(a.id),
                      () => setS(
                        () => orig = orig.contains(a.id)
                            ? orig.where((x) => x != a.id).toList()
                            : [...orig, a.id],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                if (artists.isEmpty) {
                  showAppNotice(ctx, '先選是誰唱的', isError: true);
                  return;
                }
                if (titleC.text.trim().isEmpty) {
                  showAppNotice(ctx, '歌名不能空白', isError: true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: musicPink,
                foregroundColor: const Color(0xFF2A0614),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                existing != null ? '加到《${existing.title}》' : '加到音樂',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    ),
  );
  if (saved != true) return;
  final actions = MusicActions(ref);
  final ids = [...artists];
  final d = ref.read(musicDataProvider);
  final t = titleC.text.trim();
  final existing = d.works.where((w) => w.title == t).firstOrNull;
  final v = await actions.addVersion(
    videoId: videoId,
    videoTitle: videoTitle,
    thumbnailUrl: thumbnailUrl,
    uploaderName: channelName,
    durationSec: durationSec,
    publishedAt: publishedAt,
    workId: existing?.id,
    newWorkTitle: t,
    originalArtistIds: orig.isNotEmpty
        ? orig
        : (type == MusicVersionType.cover ? const [] : ids.take(1).toList()),
    type: type,
    artistIds: ids,
    note: noteC.text,
    releaseYear: int.tryParse(yearC.text.trim()) == publishedAt.year
        ? null
        : int.tryParse(yearC.text.trim()),
  );
  if (!context.mounted) return;
  final work = ref.read(musicDataProvider).work(v.workId);
  showAppNotice(
    context,
    '♫ 已加到音樂：${work?.title ?? t}（${type.label}）',
    actionLabel: '去看',
    onAction: () => appRouter.push('/music/work/${v.workId}'),
  );
}
