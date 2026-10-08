import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/diary_password_store.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import 'debt_ui.dart';

/// 負債管理解鎖了沒。autoDispose：離開負債管理（主畫面跟月曆都關掉）就
/// 自動回到上鎖，下次進來要重新輸入；從主畫面點進月曆不用再輸入一次。
final debtUnlockedProvider = StateProvider.autoDispose<bool>((ref) => false);

/// 負債管理的密碼鎖（2026-10-08 使用者要求：債務也要密碼才能開，密碼跟
/// 日記用同一組、共用同一個變數，改一個就一起改）。所以這裡**不另外存
/// 密碼**，直接讀日記那份 [DiaryPasswordStore]（同一個儲存 key、同一個
/// 預設值 [DiaryPasswordStore.defaultPassword]，也跟著同一套同步），在
/// 日記設定裡改密碼，負債也跟著變。
class DebtLockGate extends ConsumerStatefulWidget {
  const DebtLockGate({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  ConsumerState<DebtLockGate> createState() => _DebtLockGateState();
}

class _DebtLockGateState extends ConsumerState<DebtLockGate> {
  String? _correct;
  String? _error;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    DiaryPasswordStore(ref.read(keyValueStoreProvider)).loadPassword().then((
      pw,
    ) {
      if (mounted) setState(() => _correct = pw);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_correct == null) return;
    if (_ctrl.text == _correct) {
      ref.read(debtUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = '密碼錯誤');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(debtUnlockedProvider)) return widget.child;
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: widget.title,
                  titleIcon: Icons.account_balance_wallet_outlined,
                  showBack: Navigator.of(context).canPop(),
                  showSettings: false,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Gap.md),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      debtAccent.withValues(alpha: 0.35),
                                      debtAccent.withValues(alpha: 0.12),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 28,
                                  color: debtAccent,
                                ),
                              ),
                              const SizedBox(height: Gap.md),
                              const Text(
                                '負債管理上了鎖',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('密碼跟日記同一組', style: AppText.note),
                              const SizedBox(height: Gap.lg),
                              TextField(
                                controller: _ctrl,
                                obscureText: true,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onSubmitted: (_) => _unlock(),
                                onChanged: (_) {
                                  if (_error != null) {
                                    setState(() => _error = null);
                                  }
                                },
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 10,
                                ),
                                decoration: InputDecoration(
                                  hintText: '● ● ● ●',
                                  hintStyle: const TextStyle(
                                    color: AppColors.ink3,
                                    letterSpacing: 10,
                                  ),
                                  errorText: _error,
                                  filled: true,
                                  fillColor: AppColors.glassFill,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      Radii.button,
                                    ),
                                    borderSide: const BorderSide(
                                      color: AppColors.glassEdge,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      Radii.button,
                                    ),
                                    borderSide: const BorderSide(
                                      color: debtAccent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Gap.md),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: FilledButton(
                                  onPressed: _correct == null ? null : _unlock,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        Radii.button,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    '解鎖',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
