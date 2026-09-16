import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/quiz.dart';
import '../../domain/spell_judge.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/speaker_button.dart';
import 'quiz_controller.dart';

/// 測驗頁。
///
/// 版型 04 這頁沒有計時器：時間照樣在背後記，但不顯示，
/// 顯示秒數會讓人急著答，測出來的東西就不準了。
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key});

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  final _input = TextEditingController();

  /// 每打錯一次加一，題卡看到數字變了就閃紅抖一下。
  int _wrongCount = 0;

  /// 拼字題答對後自動跳下一題的倒數，答錯或提早離開要記得取消。
  Timer? _autoAdvance;

  @override
  void dispose() {
    _input.dispose();
    _autoAdvance?.cancel();
    super.dispose();
  }

  QuizController get _controller => ref.read(quizControllerProvider.notifier);

  Future<void> _answer(bool correct) async {
    _autoAdvance?.cancel();
    final done = await _controller.answer(correct);
    _input.clear();
    if (done && mounted) context.pushReplacement('/result');
  }

  /// 拼字題判定後的處理：答對不用按下一題，1 秒後自己跳；
  /// 答錯留給使用者自己看答案、自己按下一題，順便閃卡片抖一下。
  void _onJudged(bool? correct) {
    if (correct == null) return;
    if (correct) {
      _autoAdvance = Timer(
        const Duration(milliseconds: 1000),
        () => _answer(true),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _wrongCount++);
  }

  void _onTyped(String value) => _onJudged(_controller.updateInput(value));

  void _submit() => _onJudged(_controller.submitTyped());

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quizControllerProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) =>
                  Center(child: Text('出題失敗：$e', style: AppText.bodyDim)),
              data: (s) => Column(
                children: [
                  const SizedBox(height: Gap.md),
                  _ProgressBar(state: s),
                  // 題卡不用撐滿剩下的空間，內容多高就多高，
                  // 跟下面的按鈕一起置中，畫面才不會被一張空空的大卡片撐開。
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SwipeCard(
                            key: ValueKey(s.index),
                            onLeft: _swipeLeft(s),
                            onRight: _swipeRight(s),
                            advances: _swipeAdvances(s),
                            child: _WrongFlash(
                              trigger: _wrongCount,
                              child: s.current.mode == QuizMode.tap
                                  ? _TapCard(state: s)
                                  : _TypeCard(
                                      state: s,
                                      controller: _input,
                                      onChanged: _onTyped,
                                      onSubmit: _submit,
                                    ),
                            ),
                          ),
                          const SizedBox(height: Gap.lg),
                          _Actions(
                            state: s,
                            onAnswer: _answer,
                            onSubmit: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 左滑就是「不會」。打字題還沒判定時等於按不會，判完之後就是下一題。
  VoidCallback _swipeLeft(QuizState s) {
    if (s.current.mode == QuizMode.tap) return () => _answer(false);
    final judged = s.judged;
    if (judged == null) return () => _controller.giveUp();
    return () => _answer(judged);
  }

  /// 右滑就是「會」。打字題不能靠滑的說自己會，要打出來才算，
  /// 所以還沒判定時右滑沒有作用；判完之後左右滑都是下一題。
  VoidCallback? _swipeRight(QuizState s) {
    if (s.current.mode == QuizMode.tap) return () => _answer(true);
    final judged = s.judged;
    if (judged == null) return null;
    return () => _answer(judged);
  }

  /// 會換到下一題的滑動，卡片要飛出去；只是判定（打字題按不會）就彈回原位。
  bool _swipeAdvances(QuizState s) =>
      s.current.mode == QuizMode.tap || s.judged != null;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 考到一半要能走。答過的題目在作答當下就寫進紀錄了，離開不會掉。
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, size: 19),
          color: AppColors.ink3,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: '離開這輪',
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 4,
              backgroundColor: AppColors.glassEdge,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        Text(
          '${state.index + 1} / ${state.questions.length}',
          style: AppText.note,
        ),
      ],
    );
  }
}

const _cardRadius = 22.0;

/// 題卡的最小高度。點選題翻面前後內容高度不同，沒有下限卡片會跳。
const _cardMinHeight = 180.0;

/// 滑卡。右滑會、左滑不會，拖到一半會染上對應的顏色。
///
/// 按鈕照樣留著，滑卡只是多一種答法，不是取代。
class _SwipeCard extends StatefulWidget {
  const _SwipeCard({
    super.key,
    required this.child,
    required this.onLeft,
    required this.onRight,
    required this.advances,
  });

  final Widget child;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  /// 滑過去之後會不會換題。會就讓卡片飛出去，不會就彈回來。
  final bool advances;

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  double _dx = 0;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _anim =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(
          () => setState(
            () => _dx = lerpDouble(
              _from,
              _to,
              Curves.easeOut.transform(_anim.value),
            )!,
          ),
        );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double target) {
    _from = _dx;
    _to = target;
    return _anim.forward(from: 0);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_anim.isAnimating) return;
    var next = _dx + d.delta.dx;
    // 不能滑的方向只給一點點阻力感，讓人知道這邊滑不動。
    if (widget.onRight == null && next > 0) next = min(next, 16);
    if (widget.onLeft == null && next < 0) next = max(next, -16);
    setState(() => _dx = next);
  }

  Future<void> _onEnd(DragEndDetails d, double width) async {
    if (_anim.isAnimating) return;
    final velocity = d.primaryVelocity ?? 0;
    final threshold = width * 0.28;
    final VoidCallback? action = (_dx > threshold || velocity > 900)
        ? widget.onRight
        : (_dx < -threshold || velocity < -900)
        ? widget.onLeft
        : null;

    if (action == null) {
      await _animateTo(0);
      return;
    }
    if (widget.advances) {
      await _animateTo(_dx.sign * width * 1.4);
      if (!mounted) return;
      action();
    } else {
      action();
      await _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final progress = (_dx / (width * 0.28)).clamp(-1.0, 1.0);
        final tint = progress >= 0 ? AppColors.ok : AppColors.bad;

        return GestureDetector(
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: (d) => _onEnd(d, width),
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(
              angle: _dx / width * 0.12,
              child: Stack(
                children: [
                  widget.child,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_cardRadius),
                        child: ColoredBox(
                          color: tint.withValues(alpha: progress.abs() * 0.22),
                        ),
                      ),
                    ),
                  ),
                  if (progress.abs() > 0.15)
                    Positioned(
                      top: 14,
                      left: progress > 0 ? 18 : null,
                      right: progress < 0 ? 18 : null,
                      child: Opacity(
                        opacity: progress.abs(),
                        child: Text(
                          progress > 0 ? '會' : '不會',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: tint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 打錯時卡片閃一下紅、左右抖一下。
///
/// 看 [trigger] 有沒有變，變了就播一次。換題時整張卡片重建，不會殘留。
class _WrongFlash extends StatefulWidget {
  const _WrongFlash({required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<_WrongFlash> createState() => _WrongFlashState();
}

class _WrongFlashState extends State<_WrongFlash>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void didUpdateWidget(_WrongFlash old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        final t = _anim.value;
        final fade = _anim.isAnimating ? 1 - t : 0.0;
        return Transform.translate(
          offset: Offset(sin(t * pi * 6) * 9 * fade, 0),
          child: Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_cardRadius),
                    child: ColoredBox(
                      color: AppColors.bad.withValues(alpha: 0.3 * fade),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 英翻中：正面英文，點一下翻出中文。
class _TapCard extends ConsumerWidget {
  const _TapCard({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = state.current.word;
    return GlassCard(
      radius: _cardRadius,
      padding: const EdgeInsets.all(22),
      onTap: () => ref.read(quizControllerProvider.notifier).toggleReveal(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _cardMinHeight),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: state.revealed
                ? [
                    Text(word.zh, style: AppText.hero.copyWith(fontSize: 30)),
                    const SizedBox(height: Gap.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(word.pos, style: AppText.note),
                        SpeakerButton(text: word.word, size: 17),
                      ],
                    ),
                  ]
                : [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(word.word, style: AppText.hero),
                        SpeakerButton(text: word.word, size: 22),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(word.pos, style: AppText.note),
                    const SizedBox(height: Gap.md),
                    const Text('點卡片看答案・右滑會・左滑不會', style: AppText.note),
                  ],
          ),
        ),
      ),
    );
  }
}

/// 中翻英：看中文把英文打出來。唯一測得到拼寫的題型。
class _TypeCard extends StatefulWidget {
  const _TypeCard({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onSubmit,
  });

  final QuizState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  // 每題一個，換題時卡片整張重建，焦點不會卡在上一題的輸入欄。
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final word = state.current.word;
    final judged = state.judged;
    // 標點符號不算數，空格列跟輸入框都只看字母和空白，
    // 不然句型的句號、撇號會占掉一個格子，畫面跟判定就對不起來了。
    final answer = SpellJudge.stripPunctuation(word.word);

    return GlassCard(
      radius: _cardRadius,
      padding: const EdgeInsets.all(20),
      // 輸入欄是隱形的，點卡片任何地方都把鍵盤叫回來。
      onTap: judged == null ? _focus.requestFocus : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _cardMinHeight),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(word.zh, style: AppText.hero.copyWith(fontSize: 28)),
              const SizedBox(height: Gap.xl),
              Stack(
                children: [
                  _LetterBoxes(answer: answer, input: state.input),
                  // 真正接收輸入的欄位藏在空格底下，字只顯示在空格上。
                  // 不吃觸控，拖曳才會交給滑卡，不會被輸入欄搶去選字。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focus,
                          enabled: judged == null,
                          autofocus: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          showCursor: false,
                          textCapitalization: TextCapitalization.none,
                          inputFormatters: [
                            // 標點符號不算數，乾脆不讓打，不然打出來的字元
                            // 會占掉空格列的格子，跟拿掉標點符號後的答案對不齊。
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z\s]'),
                            ),
                            LengthLimitingTextInputFormatter(answer.length),
                          ],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: widget.onChanged,
                          onSubmitted: (_) => widget.onSubmit(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              SizedBox(
                height: 20,
                child: judged == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            judged
                                ? '對了'
                                : state.input.trim().isEmpty
                                ? '答案是 ${word.word}'
                                : '不對，答案是 ${word.word}',
                            style: TextStyle(
                              fontSize: 14,
                              color: judged ? AppColors.ok : AppColors.bad,
                            ),
                          ),
                          // 拼字題答對／答錯之前不給發音，不然聽音辨字
                          // 等於變相洩題，違背這題型「不給提示」的設計
                          // （使用者 2026-09-16 加發音功能時一併決定）。
                          SpeakerButton(text: word.word, size: 17),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打字題的空格列。答案有幾個字母就幾格，打到哪一格就補上那個字母。
///
/// 不給任何提示字母：看中文就要自己拼出來，露出第一個字母等於送一半分。
/// 格子照卡片寬度自動縮放，長的字也排得進一行，不會被折成兩段。
class _LetterBoxes extends StatelessWidget {
  const _LetterBoxes({required this.answer, required this.input});

  final String answer;
  final String input;

  static const _maxBox = 38.0;
  static const _spacing = 8.0;

  @override
  Widget build(BuildContext context) {
    final count = answer.length;
    return LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth - _spacing * (count - 1)) / count;
        final size = min(_maxBox, fit);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: _spacing),
              _LetterBox(
                char: i < input.length ? input[i] : '',
                size: size,
                active: i == input.length,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LetterBox extends StatelessWidget {
  const _LetterBox({
    required this.char,
    required this.size,
    required this.active,
  });

  final String char;
  final double size;

  /// 下一個要打的位置，底線亮一點，讓人知道打到哪了。
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: size * 1.2,
            child: Center(
              child: Text(
                char,
                style: TextStyle(
                  fontSize: size * 0.78,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 3,
            decoration: BoxDecoration(
              color: active ? AppColors.accent : AppColors.ink3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底下的按鈕。點選題是兩顆，打字題是一顆。
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.state,
    required this.onAnswer,
    required this.onSubmit,
  });

  final QuizState state;
  final Future<void> Function(bool) onAnswer;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.current.mode == QuizMode.type) {
      final judged = state.judged;

      // 答對了 1.5 秒後自動跳下一題，不用按鈕；佔位維持高度，畫面才不會跳動。
      if (judged == true) {
        return const SizedBox(height: 48);
      }

      // 答錯了留一顆「下一題」，答案要留給使用者自己看完再按。
      if (judged == false) {
        return GlassButton(label: '下一題', onPressed: () => onAnswer(false));
      }

      // 還沒判定：打不出來就按「不會」，不要逼人硬湊一個錯的上去。
      // 打滿格數會自動判定，送出是給想提早交的人用的。
      return Row(
        children: [
          Expanded(
            child: _GiveUpButton(
              onPressed: () =>
                  ref.read(quizControllerProvider.notifier).giveUp(),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: GlassButton(label: '送出', onPressed: onSubmit),
          ),
        ],
      );
    }

    // 兩顆都隨時能按（使用者 2026-09-11 決定）。
    // 不知道就是不知道，知道也不用先翻開才准說知道，
    // 翻不翻由自己決定，不要拿流程卡人。
    return Row(
      children: [
        Expanded(child: _GiveUpButton(onPressed: () => onAnswer(false))),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: GlassButton(label: '會', onPressed: () => onAnswer(true)),
        ),
      ],
    );
  }
}

class _GiveUpButton extends StatelessWidget {
  const _GiveUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.bad,
        side: const BorderSide(color: AppColors.glassEdge),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
        ),
      ),
      child: const Text('不會'),
    );
  }
}
