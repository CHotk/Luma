import 'dart:convert';

import '../../domain/models/history.dart';
import '../seed/seed_source.dart';
import '../storage/key_value_store.dart';

/// 總歷史紀錄，也是整套資料的權威。
///
/// 規矩只有一條：**只增不改**。
/// 單字上的對錯次數不再自己累加，一律從這裡加總算出來，
/// 所以兩邊（對話與 App）各自考完各自追加，合併時去重就不會有人的紀錄被吃掉。
class HistoryRepository {
  HistoryRepository(this._store, {SeedSource? seed}) : _seed = seed;

  static const _entriesKey = 'history.entries.v1';
  static const _roundsKey = 'history.rounds.v1';
  static const _syncedKey = 'history.synced.version';
  static const _formatVersionKey = 'history.format.version';

  /// 目前的資料格式版本。見 [_migrateFormatIfNeeded]。
  static const _currentFormatVersion = 3;

  final KeyValueStore _store;

  /// 打包資料來源。給 null 就不做合併，測試會這樣用。
  final SeedSource? _seed;

  Future<List<HistoryEntry>> entries() async {
    await _syncBundle();
    return _readEntries();
  }

  Future<List<RoundLog>> rounds() async {
    await _syncBundle();
    return _readRounds();
  }

  /// 匯出成跟 `history.txt` 同一種格式的文字，給使用者複製出去，
  /// 之後可以貼給人工整理、合併回題庫的紀錄檔裡。
  ///
  /// 欄位跟 `history.txt` 一樣：date / round / word / result / mode / input / seconds，
  /// 用兩個以上空白分隔（跟 `WordSeedLoader._separator` 同一套規則）。
  /// [HistoryEntry] 本身已經沒有 round 欄位了，這裡的 `R1`／`R2`……只是
  /// 匯出當下依 [at] 分組現算出來的顯示用序號，純粹是為了跟
  /// `history.txt` 的欄位格式對得起來、人眼看得懂分組，不代表任何存起來
  /// 的識別碼——同一輪（共用同一個 at）的題目才會拿到一樣的號碼。
  Future<String> exportText() async {
    final all = [...await entries()]..sort((a, b) => a.at.compareTo(b.at));
    final buffer = StringBuffer()
      ..writeln('# date        round  word  result  mode  input  seconds');

    DateTime? lastAt;
    var seq = 0;
    for (final e in all) {
      if (lastAt == null || e.at != lastAt) {
        seq++;
        lastAt = e.at;
      }
      final date =
          '${e.at.year.toString().padLeft(4, '0')}-'
          '${e.at.month.toString().padLeft(2, '0')}-'
          '${e.at.day.toString().padLeft(2, '0')}';
      final mode = e.typed ? 'type' : 'tap';
      final input = e.input.trim().isEmpty ? '-' : e.input.trim();
      buffer.writeln(
        '$date  R$seq  ${e.word}  ${e.correct ? 'O' : 'X'}  '
        '$mode  $input  ${e.seconds}',
      );
    }
    return buffer.toString();
  }

  /// 每個字的對錯次數與最後受測日期，一次算好給單字庫用。
  /// 鍵是小寫的單字。
  Future<Map<String, WordTally>> tally() async {
    final result = <String, WordTally>{};
    for (final e in await entries()) {
      final key = e.word.toLowerCase();
      final current = result[key] ?? const WordTally();
      result[key] = current.plus(correct: e.correct, at: e.at);
    }
    return result;
  }

  /// 每答完一題就寫一次。
  ///
  /// 不等整輪結束才寫，是因為中途關掉瀏覽器或被系統收掉的話，
  /// 那一輪的努力就全部不見了。寧可留下半輪，也不要留下空白。
  ///
  /// 同一輪的所有題目共用同一個 [HistoryEntry.at]（呼叫端——
  /// `quiz_controller.dart`——一輪開始時只取一次 `DateTime.now()`，之後
  /// 每題都沿用這個值），這裡直接拿 `entry.at` 當這一輪的識別碼分組，
  /// 不用再跟這個 repository 要一個獨立的輪次編號（使用者 2026-09-17
  /// 決定拿掉 round，全部改用 at 識別）。
  Future<void> appendAnswer(HistoryEntry entry, {required bool stealth}) async {
    final all = [...await entries(), entry];
    await _writeEntries(all);

    // 順手把這一輪的摘要更新到目前為止的狀態，半途中斷也看得出考到哪。
    final mine = all.where((e) => e.at == entry.at).toList();
    final summary = RoundLog(
      at: entry.at,
      seconds: mine.fold(0, (sum, e) => sum + e.seconds),
      total: mine.length,
      right: mine.where((e) => e.correct).length,
      stealth: stealth,
    );

    final rounds = await _readRounds();
    final index = rounds.indexWhere((r) => r.at == entry.at);
    if (index >= 0) {
      rounds[index] = summary;
    } else {
      rounds.add(summary);
    }
    await _writeRounds(rounds..sort((a, b) => a.at.compareTo(b.at)));
  }

  /// 一輪結束時把摘要補上真正的耗時。[at] 是那一輪共用的識別時戳，
  /// 呼叫端存著跟 [appendAnswer] 用的是同一個值。
  ///
  /// 每題累加的秒數只算「想的時間」，這裡改成整輪實際花的時間，
  /// 含翻卡片、看答案、發呆那些。
  Future<void> finishRound(DateTime at, Duration elapsed) async {
    final rounds = await _readRounds();
    final index = rounds.indexWhere((r) => r.at == at);
    if (index < 0) return;
    final current = rounds[index];
    rounds[index] = RoundLog(
      at: current.at,
      seconds: elapsed.inSeconds,
      total: current.total,
      right: current.right,
      stealth: current.stealth,
    );
    await _writeRounds(rounds);
  }

  /// 從第一天到現在的總計。即時算出來，不另外存一份。
  Future<LifetimeStats> lifetime() async {
    final all = await rounds();
    if (all.isEmpty) return LifetimeStats.empty;

    var questions = 0, right = 0, seconds = 0, stealth = 0;
    final days = <String>{};
    for (final r in all) {
      questions += r.total;
      right += r.right;
      seconds += r.seconds;
      if (r.stealth) stealth++;
      days.add('${r.at.year}-${r.at.month}-${r.at.day}');
    }

    return LifetimeStats(
      rounds: all.length,
      questions: questions,
      right: right,
      wrong: questions - right,
      seconds: seconds,
      activeDays: days.length,
      stealthRounds: stealth,
      since: all.first.at,
    );
  }

  /// 某一輪的所有題目，照作答順序。[at] 是那一輪共用的識別時戳。
  /// 總紀錄頁點某一輪進去就是看這個。
  ///
  /// 不在這裡另外排序：同一輪的題目全部共用同一個 [HistoryEntry.at]，
  /// 排序鍵會全部平手，直接照 [entries] 本身的儲存順序（新答案一律
  /// 附加在最後面，本來就是實際作答順序）回傳才不會被不保證穩定的
  /// 排序演算法打亂原本的答題先後。
  Future<List<HistoryEntry>> forRound(DateTime at) async {
    final all = await entries();
    return all.where((e) => e.at == at).toList();
  }

  /// 某個字的所有作答紀錄，新的排前面。
  Future<List<HistoryEntry>> forWord(String word) async {
    final key = word.toLowerCase();
    final all = await entries();
    return all.where((e) => e.word.toLowerCase() == key).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  /// 把打包進來的紀錄合併進本機。
  ///
  /// 每次打包版本變新就跑一次，不是只跑一次。
  /// 對話那邊考完也是往同一份 history.txt 追加，所以這裡要能反覆合併。
  ///
  /// 去重看的是內容：同一個時間點、同一個字、同樣對錯，就算是同一筆
  /// （見 [_fingerprint]）——不看任何編號，兩個獨立來源本來就幾乎不會
  /// 在完全同一時刻答對／答錯同一個字。
  Future<void> _syncBundle() async {
    final seed = _seed;
    if (seed == null) return;

    await _migrateFormatIfNeeded();

    final applied = int.tryParse(await _store.read(_syncedKey) ?? '') ?? 0;
    if (seed.bundleVersion <= applied) return;

    // 先插旗再合併。就算中途出錯也不要無限重試。
    await _store.write(_syncedKey, '${seed.bundleVersion}');

    final incoming = await seed.bundleHistory();
    if (incoming.isEmpty) return;

    final existing = await _readEntries();
    final seen = {for (final e in existing) _fingerprint(e)};
    final added = [
      for (final e in incoming)
        if (seen.add(_fingerprint(e))) e,
    ];
    if (added.isEmpty) return;

    final merged = [...existing, ...added]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _writeEntries(merged);
    await _writeRounds(_rebuildRounds(merged, await _readRounds()));
  }

  /// round 不進指紋：同一輪的所有題目本來就共用同一個 at 時間戳
  /// （對話端 grade_round.ps1 整批寫入時只蓋一次系統時間），at + word +
  /// correct 已經足夠唯一識別一筆紀錄，round 只是內部分組 id，混進來
  /// 是多餘的（使用者 2026-09-17 決定拿掉）。這個字串是即時算出來的，
  /// 不是存在本機的固定格式，改公式不用另外跑遷移版本號。
  static String _fingerprint(HistoryEntry e) =>
      '${e.at.toIso8601String()}|${e.word.toLowerCase()}|${e.correct}';

  /// 本機資料格式跟目前 bundle 的資料形狀對不上時，先整個清空重新
  /// 乾淨匯入一次，不走「只補差集」的增量比對邏輯——[_fingerprint]
  /// 是即時從 [HistoryEntry] 算出來的，如果本機存的欄位（例如舊的
  /// at 值、或舊的 round 欄位）跟現在的公式假設不一致，指紋會全部
  /// 對不上新 bundle，被誤判成「全新的」整批重複匯入，right/wrong
  /// 統計就灌水。已經發生過兩次：
  ///   - 版本 2（2026-09-17）：`history.txt` 的 round 欄位被重新編號
  ///     成全域唯一，本機存的舊指紋含著改編號前的 round，對不上新值。
  ///   - 版本 3（2026-09-17，同一天）：round 整個從識別機制裡拿掉，
  ///     改成完全靠 [HistoryEntry.at] 識別／分組一輪——`history.txt`
  ///     的 at 欄位同時被回填成全域唯一的合成時間，本機舊資料的 at
  ///     可能還是舊的（例如只精確到天、或撞在同一分鐘），也需要重新
  ///     乾淨匯入一次才能跟新公式對齊。
  ///
  /// 版本一致之後這段直接跳過，不是每次都要清一次——這是保護機制，
  /// 不是常態流程；只有資料形狀真的變了才需要再往上加一版。
  Future<void> _migrateFormatIfNeeded() async {
    final stored =
        int.tryParse(await _store.read(_formatVersionKey) ?? '') ?? 1;
    if (stored >= _currentFormatVersion) return;

    await _store.remove(_entriesKey);
    await _store.remove(_roundsKey);
    await _store.remove(_syncedKey);
    await _store.write(_formatVersionKey, '$_currentFormatVersion');
  }

  /// 依合併後的紀錄重建每輪摘要。分組鍵是 [HistoryEntry.at]：同一輪的
  /// 題目共用同一個 at，跨輪的 at 保證全域唯一（見 [_migrateFormatIfNeeded]
  /// 的說明），不會混到一起。
  ///
  /// App 自己跑出來的輪次有秒數與偽裝標記，那些要留著；
  /// 其餘從紀錄兜回來，秒數是 0，因為 history.txt 本來就沒有時間。
  List<RoundLog> _rebuildRounds(
    List<HistoryEntry> entries,
    List<RoundLog> known,
  ) {
    final byAt = <DateTime, List<HistoryEntry>>{};
    for (final e in entries) {
      byAt.putIfAbsent(e.at, () => []).add(e);
    }
    final keep = {for (final r in known) r.at: r};

    return [
      for (final group in byAt.entries)
        keep[group.key] ??
            RoundLog(
              at: group.key,
              seconds: 0,
              total: group.value.length,
              right: group.value.where((e) => e.correct).length,
              stealth: false,
            ),
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<List<HistoryEntry>> _readEntries() async {
    final raw = await _store.read(_entriesKey);
    // 給一個真的空清單，不是 const []：appendAnswer 會直接對這裡讀出來
    // 的清單呼叫 .add()，const 的不可變清單會炸掉（沒有 seed，或 seed
    // 的 bundleHistory() 剛好是空的情況下，_syncBundle 從沒寫過任何
    // 東西，第一次讀到的就是這裡的預設值）。
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(HistoryEntry.fromJson)
        .toList();
  }

  Future<List<RoundLog>> _readRounds() async {
    final raw = await _store.read(_roundsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(RoundLog.fromJson)
        .toList();
  }

  Future<void> _writeEntries(List<HistoryEntry> entries) => _store.write(
    _entriesKey,
    jsonEncode([for (final e in entries) e.toJson()]),
  );

  Future<void> _writeRounds(List<RoundLog> rounds) => _store.write(
    _roundsKey,
    jsonEncode([for (final r in rounds) r.toJson()]),
  );
}

/// 單一個字的加總結果。
class WordTally {
  const WordTally({this.right = 0, this.wrong = 0, this.lastTest});

  final int right;
  final int wrong;
  final DateTime? lastTest;

  WordTally plus({required bool correct, required DateTime at}) {
    final latest = lastTest == null || at.isAfter(lastTest!) ? at : lastTest;
    return WordTally(
      right: correct ? right + 1 : right,
      wrong: correct ? wrong : wrong + 1,
      lastTest: latest,
    );
  }
}
