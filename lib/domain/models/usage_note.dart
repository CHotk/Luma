/// 一則用法地雷。
///
/// 這些是字典查不到、但講錯會失禮的用法，
/// 例如說人胖不要用 fat、說自己無聊不能講 I'm boring。
class UsageNote {
  const UsageNote({
    required this.no,
    required this.title,
    required this.status,
    required this.blocks,
    this.date = '',
    this.relatedWords = const [],
  });

  /// 編號，從 001 起跳。保留字串形式，前面的零有意義。
  final String no;
  final String title;

  /// 查證結果：✅ 正確、⚠️ 部分正確、❌ 有誤。
  final String status;
  final String date;

  /// 內容。已經拆成段落、清單、對照表，畫面直接照型別排版，
  /// 不用在畫面裡再解析一次 Markdown。
  final List<NoteBlock> blocks;

  /// 這則牽涉到的單字，列在最後面當索引。
  final List<String> relatedWords;

  /// 清單頁要的一句話預覽：取第一段文字。
  String get preview {
    for (final b in blocks) {
      if (b is NoteParagraph) return b.text;
    }
    return '';
  }
}

/// 內容區塊。用 sealed 是為了讓畫面的 switch 漏掉任何一種時編譯就會擋下來。
sealed class NoteBlock {
  const NoteBlock();
}

/// 一般段落。
class NoteParagraph extends NoteBlock {
  const NoteParagraph(this.text);
  final String text;
}

/// 小標題，原本是 Markdown 的 ###。
class NoteHeading extends NoteBlock {
  const NoteHeading(this.text);
  final String text;
}

/// 條列。
class NoteBullets extends NoteBlock {
  const NoteBullets(this.items);
  final List<String> items;
}

/// 對照表。
///
/// 原始資料是 Markdown 表格，但表格在手機上一定會擠成一團，
/// 所以在畫面上會拆成一列一張小卡：第一欄當標題，其餘欄當說明。
class NoteTable extends NoteBlock {
  const NoteTable({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
}
