import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/session.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import 'widgets/brand.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _pages = [
    ('🥔🍅🧅', 'Tell us what\'s in your kitchen', 'Add the ingredients you have at home — or snap a photo and let Chef AI spot them.'),
    ('✨🍳', 'Get recipes instantly', 'Tap "What Can I Cook?" and get dishes that use what you already have. No waste, no stress.'),
    ('👨‍👩‍👧‍👦🛒', 'Cook together as a family', 'Share your kitchen, meal plan and shopping list with everyone at home.'),
  ];

  Future<void> _finish() async {
    await ref.read(sharedPrefsProvider).setBool(onboardingSeenKey, true);
    if (mounted) context.go(Routes.login);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _finish, child: const Text('Skip')),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    final p = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 200,
                            height: 200,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.gradientFor(p.$2),
                              boxShadow: [BoxShadow(color: AppColors.saffron.withValues(alpha: 0.35), blurRadius: 50)],
                            ),
                            child: Text(p.$1, style: const TextStyle(fontSize: 54)),
                          ),
                          const SizedBox(height: 44),
                          Text(p.$2, textAlign: TextAlign.center, style: context.text.headlineMedium),
                          const SizedBox(height: 14),
                          Text(p.$3, textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.saffron : context.palette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: GradientButton(
                  label: last ? "Let's start cooking" : 'Next',
                  icon: last ? Icons.restaurant_rounded : Icons.arrow_forward_rounded,
                  onPressed: () => last
                      ? _finish()
                      : _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
