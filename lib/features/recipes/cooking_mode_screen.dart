import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/safety.dart';
import '../../data/providers.dart';
import '../../models/recipe.dart';
import '../../widgets/common.dart';

/// Big-text, step-by-step cooking mode. Keeps the screen awake.
class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  final _page = PageController();
  int _step = 0;
  Timer? _timer;
  Duration? _remaining;
  int? _timerStep;

  List<String> get _steps => widget.recipe.instructions;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _go(int i) {
    HapticFeedback.selectionClick();
    _page.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _startTimer(Duration d) {
    _timer?.cancel();
    setState(() {
      _remaining = d;
      _timerStep = _step;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _remaining! - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() => _remaining = Duration.zero);
        if (mounted) showSnack(context, '⏰ Timer done for step ${_timerStep! + 1}!');
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  Future<void> _finish() async {
    await ref.read(profileProvider.notifier).recordCooked();
    if (!mounted) return;
    final streak = ref.read(profileProvider).value?.currentStreak() ?? 1;
    final saved = ref.read(savedRecipesProvider.notifier).isSaved(widget.recipe);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🎉 Delicious work!', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.recipe.emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 10),
          Text('You cooked ${widget.recipe.name}.', textAlign: TextAlign.center, style: c.text.bodyLarge),
          const SizedBox(height: 10),
          Text('🔥 Family streak: $streak day${streak == 1 ? '' : 's'}', style: c.text.titleMedium),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!saved)
            TextButton.icon(
              onPressed: () {
                ref.read(savedRecipesProvider.notifier).toggle(widget.recipe);
                Navigator.pop(c);
              },
              icon: const Icon(Icons.favorite_rounded, color: AppColors.tomato),
              label: const Text('Save recipe'),
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
    if (mounted) context.pop();
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isChild = ref.watch(profileProvider).value?.isChild ?? false;
    final last = _step == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded, size: 28), tooltip: 'Exit cooking mode', onPressed: () => context.pop()),
        title: Text(widget.recipe.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ingredients',
            icon: const Icon(Icons.list_alt_rounded, size: 28),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (c) => SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(22, 0, 22, 22), children: [
                    Text('Ingredients', style: c.text.titleLarge),
                    const SizedBox(height: 10),
                    for (final i in widget.recipe.ingredients)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('•  ${i.quantity} ${i.name}'.replaceAll('  ', ' '), style: const TextStyle(fontSize: 20)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
              child: Column(children: [
                Text('STEP ${_step + 1} OF ${_steps.length}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: AppColors.saffron)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (_step + 1) / _steps.length),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 10, backgroundColor: context.palette.border),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _step = i),
                itemBuilder: (_, i) {
                  final step = _steps[i];
                  final tip = Safety.tipFor(step);
                  final timer = Safety.timerFor(step);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 30, 26, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(step, style: const TextStyle(fontSize: 30, height: 1.35, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 28),
                      if (timer != null)
                        _TimerCard(
                          label: _timerStep == i && _remaining != null ? _fmt(_remaining!) : _fmt(timer),
                          running: _timerStep == i && _remaining != null && _remaining! > Duration.zero,
                          onStart: () => _startTimer(timer),
                          onStop: () {
                            _timer?.cancel();
                            setState(() => _remaining = null);
                          },
                        ),
                      if (tip != null) ...[
                        const SizedBox(height: 16),
                        SafetyBanner(isChild ? '$tip\n👨‍👩‍👧 Ask a grown-up to help with this step.' : tip, big: true),
                      ],
                    ]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 68,
                    child: OutlinedButton.icon(
                      onPressed: _step == 0 ? null : () => _go(_step - 1),
                      icon: const Icon(Icons.arrow_back_rounded, size: 26),
                      label: const Text('Back', style: TextStyle(fontSize: 19)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    height: 68,
                    label: last ? 'Finish 🎉' : 'Next',
                    icon: last ? null : Icons.arrow_forward_rounded,
                    onPressed: last ? _finish : () => _go(_step + 1),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.label, required this.running, required this.onStart, required this.onStop});
  final String label;
  final bool running;
  final VoidCallback onStart, onStop;

  @override
  Widget build(BuildContext context) => AppCard(
        color: AppColors.sky.withValues(alpha: 0.10),
        borderColor: AppColors.sky.withValues(alpha: 0.4),
        child: Row(children: [
          const Text('⏲️', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: running ? AppColors.expired : AppColors.sky, minimumSize: const Size(100, 56)),
            onPressed: running ? onStop : onStart,
            child: Text(running ? 'Stop' : 'Start', style: const TextStyle(fontSize: 18)),
          ),
        ]),
      );
}
