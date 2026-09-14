import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/usage_note.dart';

/// 把用法地雷那份 Markdown 讀進來，拆成結構化的資料。
///
/// 只支援這份檔案實際用到的語法，不做通用的 Markdown 剖析：
///   ## 001　標題          一則的開頭
///   **日期：… 狀態：…**   每則的第二行
///   ### 小標
///   | 表格 |
///   - 條列
///   相關單字：a、b、c
///
/// 之所以自己拆而不用 Markdown 套件，是因為表格在手機上要改成一列一張卡，
/// 通用渲染器做不到這件事。
class NoteLoader {
  const NoteLoader(this.asset);

  /// 要讀哪一本。兩本格式一樣，只是內容主題不同。
  final String asset;

  Future<List<UsageNote>> load() async {
    final raw = await rootBundle.loadString(asset);
    final notes = <UsageNote>[];

    // 以 "## " 切成一則一則，第一段是整份檔案的前言，丟掉。
    final chunks = raw.split(RegExp(r'^## ', multiLine: true));
    for (final chunk in chunks.skip(1)) {
      final note = _parseNote(chunk);
      if (note != null) notes.add(note);
    }
    return notes;
  }

  UsageNote? _parseNote(String chunk) {
    final lines = chunk.split('\n');
    if (lines.isEmpty) return null;

    // 標題長這樣：001　說人胖不要用 fat（中間是全形空白）
    final head = lines.first.trim();
    final headMatch = RegExp(r'^(\S+)\s+(.*)$').firstMatch(head);
    final no = headMatch?.group(1) ?? '';
    final title = headMatch?.group(2) ?? head;

    var date = '';
    var status = '';
    final related = <String>[];
    final blocks = <NoteBlock>[];

    final bullets = <String>[];
    final tableLines = <String>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      if (text.isNotEmpty) blocks.add(NoteParagraph(text));
      paragraph.clear();
    }

    void flushBullets() {
      if (bullets.isEmpty) return;
      blocks.add(NoteBullets(List.of(bullets)));
      bullets.clear();
    }

    void flushTable() {
      if (tableLines.isEmpty) return;
      final parsed = _parseTable(tableLines);
      if (parsed != null) blocks.add(parsed);
      tableLines.clear();
    }

    void flushAll() {
      flushParagraph();
      flushBullets();
      flushTable();
    }

    for (final rawLine in lines.skip(1)) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();

      // 分隔線代表這一則結束。
      if (trimmed == '---') break;

      if (trimmed.isEmpty) {
        flushAll();
        continue;
      }

      // 第二行的日期與狀態。
      final meta = RegExp(r'\*\*日期：(.*?)\s*　*狀態：(.*?)\*\*').firstMatch(trimmed);
      if (meta != null) {
        date = meta.group(1)?.trim() ?? '';
        status = meta.group(2)?.trim() ?? '';
        continue;
      }

      if (trimmed.startsWith('相關單字')) {
        flushAll();
        related.addAll(
          trimmed
              .replaceFirst(RegExp(r'^相關單字[：:]\s*'), '')
              .split(RegExp(r'[、,，]'))
              .map((w) => w.trim())
              .where((w) => w.isNotEmpty),
        );
        continue;
      }

      if (trimmed.startsWith('###')) {
        flushAll();
        blocks.add(NoteHeading(trimmed.replaceFirst(RegExp(r'^#+\s*'), '')));
        continue;
      }

      if (trimmed.startsWith('|')) {
        flushParagraph();
        flushBullets();
        tableLines.add(trimmed);
        continue;
      }

      if (trimmed.startsWith('> ')) {
        flushAll();
        blocks.add(NoteQuote(trimmed.substring(2).trim()));
        continue;
      }

      if (trimmed.startsWith('- ')) {
        flushParagraph();
        flushTable();
        bullets.add(trimmed.substring(2).trim());
        continue;
      }

      flushBullets();
      flushTable();
      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(trimmed);
    }

    flushAll();
    if (title.isEmpty && blocks.isEmpty) return null;

    return UsageNote(
      no: no,
      title: title,
      status: status,
      date: date,
      blocks: blocks,
      relatedWords: related,
    );
  }

  /// Markdown 表格：第一列是表頭，第二列是分隔線，其餘是內容。
  NoteTable? _parseTable(List<String> lines) {
    List<String> cells(String line) => line
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (lines.length < 2) return null;
    final headers = cells(lines.first);
    final rows = [
      for (final line in lines.skip(2))
        if (cells(line).isNotEmpty) cells(line),
    ];
    if (rows.isEmpty) return null;
    return NoteTable(headers: headers, rows: rows);
  }
}
