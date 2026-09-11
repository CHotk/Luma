import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/daily_limit.dart';
import '../quiz/quiz_controller.dart';
import 'terminal_theme.dart';

/// 偽裝模式：整頁假裝成 Windows 的命令提示字元。
///
/// 用途是上班時間偷背單字，所以規則跟一般測驗不同：
///   1. 只出英文，不顯示中文。畫面上出現中文就穿幫了。
///   2. 不出打字題，因為跳出中文輸入法很顯眼。
///   3. 沒有翻面，看到字直接按會或不會。
///
/// 答錯的字照樣會記錄，中文清單在離開後的結果頁看得到。
class StealthPage extends ConsumerStatefulWidget {
  const StealthPage({super.key});

  @override
  ConsumerState<StealthPage> createState() => _StealthPageState();
}

class _StealthPageState extends ConsumerState<StealthPage> {
  /// 假的時間戳從這一輪開始那一刻起算，每行加兩秒，看起來才像真的在跑。
  DateTime _base = DateTime.now();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _finished = false;

  /// 今天的份量用完了。偽裝模式一樣受每日上限管，
  /// 不然它就變成繞過限制的後門，跟整支 App 的主張相反。
  bool _quotaReached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _refreshQuota();
  }

  /// 問一次今天還能不能做。回傳 true 代表已經到量。
  Future<bool> _refreshQuota() async {
    final settings = ref.read(settingsRepositoryProvider);
    final now = ref.read(clockProvider)();
    final rules = await settings.loadRules();
    final usage = await settings.loadUsage(now);
    final reached = DailyLimit.reached(usage, rules);
    if (mounted && reached != _quotaReached) {
      setState(() => _quotaReached = reached);
    }
    return reached;
  }

  /// 再來一輪，而且不離開偽裝模式。
  ///
  /// 上班時間關掉這頁再重開很顯眼，所以續做要能原地進行。
  Future<void> _again() async {
    if (await _refreshQuota()) return;
    ref.invalidate(quizControllerProvider);
    if (!mounted) return;
    setState(() {
      _finished = false;
      _base = DateTime.now();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _stamp(int step) {
    final t = _base.add(Duration(seconds: step * 2));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _answer(bool correct) async {
    if (_finished) return;
    final done = await ref.read(quizControllerProvider.notifier).answer(correct);
    if (done) {
      setState(() => _finished = true);
      // 這一輪剛計入用量，順便看看是不是已經到量。
      await _refreshQuota();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _exit() {
    ref.read(stealthModeProvider.notifier).state = false;
    context.pushReplacement('/result');
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_finished) {
      if (event.logicalKey == LogicalKeyboardKey.keyR && !_quotaReached) {
        _again();
      }
      if (event.logicalKey == LogicalKeyboardKey.keyE ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _exit();
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) _answer(true);
    if (event.logicalKey == LogicalKeyboardKey.keyN) _answer(false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quizControllerProvider);

    return Scaffold(
      backgroundColor: TerminalTheme.background,
      body: KeyboardListener(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              _TitleBar(onClose: _exit),
              Expanded(
                child: async.when(
                  loading: () => const _Console(lines: ['loading modules...']),
                  error: (e, _) => _Console(lines: ['fatal: $e']),
                  data: (s) => _Console(
                    scroll: _scroll,
                    lines: _finished ? _finishedLines() : _runningLines(s),
                  ),
                ),
              ),
              if (!_finished)
                _Prompt(onYes: () => _answer(true), onNo: () => _answer(false))
              else
                _DonePrompt(
                  canRepeat: !_quotaReached,
                  onAgain: _again,
                  onExit: _exit,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 進行中的畫面：開頭幾行固定，接著每答一題就多一行編譯紀錄。
  List<String> _runningLines(QuizState s) {
    final lines = <String>[
      'Microsoft Windows [Version 10.0.26100.2033]',
      '(c) Microsoft Corporation. All rights reserved.',
      '',
      r'C:\Users\temp9>npm run build --watch',
      '',
      '> lume@0.1.0 build',
      '> node scripts/build.js --watch',
      '',
      '[${_stamp(0)}] compiling ${s.questions.length} modules...',
    ];

    for (var i = 0; i < s.answers.length; i++) {
      final a = s.answers[i];
      final tag = a.correct ? '  ok ' : '  !! ';
      final verb = a.correct ? 'resolved' : 'unresolved';
      lines.add(
        "[${_stamp(i + 1)}]$tag $verb '${a.question.word.word}'",
      );
    }

    lines
      ..add('')
      ..add(
        "[${_stamp(s.answers.length + 1)}]  ?   checking "
        "'${s.current.word.word}'",
      );
    return lines;
  }

  /// 結束畫面：只列出英文，中文留到離開之後的結果頁。
  List<String> _finishedLines() {
    final result = ref.read(lastRoundProvider);
    final missed = result?.missed ?? const [];
    final total = result?.total ?? 0;
    final ok = result?.rightCount ?? 0;

    final lines = <String>[
      '[${_stamp(total + 2)}] build finished',
      '[${_stamp(total + 2)}] $ok passed, ${missed.length} failed',
    ];
    if (missed.isNotEmpty) {
      lines.add('[${_stamp(total + 3)}] unresolved modules:');
      for (final a in missed) {
        lines.add("               ${a.question.word.word}");
      }
    }

    // 到量的時候用終端機的口氣講，不要跳中文彈窗。
    if (_quotaReached) {
      lines
        ..add('')
        ..add('[${_stamp(total + 4)}] daily quota reached, queue closed')
        ..add('[${_stamp(total + 4)}] next build window: tomorrow');
    }

    return lines..addAll(['', r'C:\Users\temp9>']);
  }
}

/// 假的視窗標題列。沒有它就只是一片黑底綠字，不像 CMD。
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: TerminalTheme.titleBar,
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          const Text(
            r'C:\WINDOWS\system32\cmd.exe',
            style: TextStyle(
              fontSize: 12,
              color: TerminalTheme.titleText,
              fontFamily: TerminalTheme.fontFamily,
            ),
          ),
          const Spacer(),
          const _WindowButton('\u2014'),
          const _WindowButton('\u25A1'),
          // 只有關閉鈕是真的，按了就離開偽裝模式。
          _WindowButton('\u2715', onTap: onClose, hover: true),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton(this.glyph, {this.onTap, this.hover = false});

  final String glyph;
  final VoidCallback? onTap;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 30,
        alignment: Alignment.center,
        color: hover ? TerminalTheme.closeTint : null,
        child: Text(
          glyph,
          style: const TextStyle(
            fontSize: 12,
            color: TerminalTheme.titleText,
            fontFamily: TerminalTheme.fontFamily,
          ),
        ),
      ),
    );
  }
}

/// 終端機本體。等寬字、左上對齊、可捲動。
class _Console extends StatelessWidget {
  const _Console({required this.lines, this.scroll});

  final List<String> lines;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          lines.join('\n'),
          style: TerminalTheme.body,
        ),
      ),
    );
  }
}

/// 作答列。做成終端機提示字的樣子，點文字就等於按鍵。
class _Prompt extends StatelessWidget {
  const _Prompt({required this.onYes, required this.onNo});

  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          const Text('resolve? ', style: TerminalTheme.body),
          Expanded(
            child: InkWell(
              onTap: onYes,
              child: const Text('[y] yes', style: TerminalTheme.bodyBright),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onNo,
              child: const Text('[n] skip', style: TerminalTheme.bodyBright),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一輪跑完之後的提示列。
///
/// 續做要能原地進行，因為上班時關掉再開很顯眼。
/// 到量之後只剩 exit，偽裝模式不是繞過每日上限的後門。
class _DonePrompt extends StatelessWidget {
  const _DonePrompt({
    required this.canRepeat,
    required this.onAgain,
    required this.onExit,
  });

  final bool canRepeat;
  final VoidCallback onAgain;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          if (canRepeat) ...[
            Expanded(
              child: InkWell(
                onTap: onAgain,
                child: const Text(
                  '[r] rebuild',
                  style: TerminalTheme.bodyBright,
                ),
              ),
            ),
          ] else
            const Expanded(
              child: Text('queue closed', style: TerminalTheme.body),
            ),
          Expanded(
            child: InkWell(
              onTap: onExit,
              child: const Text('[e] exit', style: TerminalTheme.bodyBright),
            ),
          ),
        ],
      ),
    );
  }
}
