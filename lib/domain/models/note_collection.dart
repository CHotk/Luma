/// 筆記分成幾本。
///
/// 兩本的格式完全一樣，只是內容主題不同，所以共用同一套剖析與排版。
/// 要加第三本就在這裡加一個值，再放一個同格式的 md 進 assets，畫面不用改。
enum NoteCollection {
  /// 講錯會失禮或被誤會的字，例如 fat、napkin。
  traps(
    label: '用法地雷',
    subtitle: '字典查得到意思，查不到會不會失禮',
    asset: 'assets/data/usage-notes.md',
  ),

  /// 意思相近但用的場合不同的字，例如 quiz、test、exam。
  choices(
    label: '近義字',
    subtitle: '長得像、意思也像，但用的場合不一樣',
    asset: 'assets/data/word-choices.md',
  ),

  /// 多義字的義項拆解，例如 back、hot、run 到底有哪些意思。
  senses(
    label: '義項解析',
    subtitle: '多義、極多義的字，常見的意思一次看完',
    asset: 'assets/data/sense-notes.md',
  );

  const NoteCollection({
    required this.label,
    required this.subtitle,
    required this.asset,
  });

  final String label;
  final String subtitle;
  final String asset;

  static NoteCollection parse(String? raw) {
    for (final c in values) {
      if (c.name == raw) return c;
    }
    return NoteCollection.traps;
  }
}
