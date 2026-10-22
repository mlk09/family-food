import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/id.dart';
import '../../core/utils/quick_add_parser.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../models/ingredient.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';

/// Simple dashboard: 1) tell us what you have, 2) ask what to cook, 3) talk to Chef.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const chefQuestions = [
    'Mere paas jo hai usse kya banau?',
    '20 minute mein kya ban sakta hai?',
    'Bachchon ke liye kya banau?',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = ref.watch(profileProvider).value;
    final pantry = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    final expiring = pantry.where((i) => i.freshness() == Freshness.expiringSoon).toList()
      ..sort((a, b) => (a.daysLeft() ?? 99).compareTo(b.daysLeft() ?? 99));
    final streak = profile?.currentStreak() ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.saffron,
          onRefresh: () async {
            await Future.wait([
              ref.read(ingredientsProvider.notifier).refresh(),
              ref.read(profileProvider.notifier).refresh(),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
            children: [
              // ── Top bar ──
              Row(children: [
                GestureDetector(
                  onTap: () => context.go(Routes.profile),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.saffron,
                    backgroundImage: profile?.avatarUrl != null ? NetworkImage(profile!.avatarUrl!) : null,
                    child: profile?.avatarUrl == null
                        ? Text((profile?.firstName ?? 'C')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                if (session.isDemo) const DemoBadge(),
                const Spacer(),
                if (streak > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('🔥 $streak', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
              ]),
              const SizedBox(height: 18),

              // ── 1. Greeting + main button ──
              Text('${greetingFor(DateTime.now())}, ${profile?.firstName ?? 'Chef'} 👋', style: context.text.headlineSmall),
              const SizedBox(height: 4),
              Text('Aaj kya banayein? 🍳', style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 16),
              GradientButton(
                label: 'What Can I Cook?',
                icon: Icons.auto_awesome_rounded,
                gradient: AppColors.aiGradient,
                height: 66,
                onPressed: () => context.push(Routes.cook),
              ),

              // ── 2. Tell us what you have ──
              const SizedBox(height: 22),
              const _QuickAddCard(),

              if (expiring.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  onTap: () => context.push(Routes.cook),
                  borderColor: AppColors.expiring.withValues(alpha: 0.5),
                  color: AppColors.expiring.withValues(alpha: 0.10),
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Text(foodEmoji(expiring.first.name, expiring.first.category), style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Jaldi use karo: ${expiring.take(3).map((e) => e.name).join(', ')}',
                          style: context.text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ],

              // ── Kitchen at a glance ──
              const SizedBox(height: 22),
              SectionHeader('My Kitchen (${pantry.length})', emoji: '🧺', action: 'See all', onAction: () => context.go(Routes.kitchen)),
              if (pantry.isEmpty)
                Text('Abhi khaali hai — upar box mein likho kya-kya hai.', style: context.text.bodyMedium?.copyWith(color: context.palette.muted))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final ing in pantry.take(14))
                    ActionChip(
                      avatar: Text(foodEmoji(ing.name, ing.category)),
                      label: Text(ing.name),
                      side: BorderSide(color: FreshnessBadge.info(ing).$1.withValues(alpha: 0.6)),
                      onPressed: () => context.push(Routes.addIngredient, extra: ing),
                    ),
                  if (pantry.length > 14)
                    ActionChip(label: Text('+${pantry.length - 14} more'), onPressed: () => context.go(Routes.kitchen)),
                ]),

              // ── 3. Talk to Chef ──
              const SizedBox(height: 26),
              AppCard(
                gradient: LinearGradient(colors: [AppColors.berry.withValues(alpha: 0.18), AppColors.tomato.withValues(alpha: 0.10)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('🤖', style: TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Chef AI se baat karo', style: context.text.titleLarge),
                        Text('Hindi, Hinglish ya English — kuch bhi poocho', style: context.text.bodySmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  for (final q in chefQuestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        radius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () => context.push(Routes.chef, extra: q),
                        child: Row(children: [
                          Expanded(child: Text(q, style: context.text.bodyLarge)),
                          const Icon(Icons.send_rounded, size: 18, color: AppColors.berry),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(Routes.chef),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Apna sawaal likho'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One text box to add many ingredients at once, plus photo scan.
class _QuickAddCard extends ConsumerStatefulWidget {
  const _QuickAddCard();

  @override
  ConsumerState<_QuickAddCard> createState() => _QuickAddCardState();
}

class _QuickAddCardState extends ConsumerState<_QuickAddCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final items = QuickAddParser.parse(_text.text);
    if (items.isEmpty) {
      showSnack(context, 'Items likho, jaise: aloo, pyaz, tamatar, 1 kg chawal');
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(ingredientsProvider.notifier).addOrMerge(items);
    _text.clear();
    if (mounted) {
      showSnack(context, '✅ ${items.length} item${items.length == 1 ? '' : 's'} added: ${items.map((e) => e.name).take(5).join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kitchen mein kya hai?', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text('Ek saath sab likho, comma se alag karke', style: context.text.bodySmall),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(hintText: 'aloo, pyaz, tamatar, 1 kg chawal, 6 ande'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.herb),
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add to Kitchen'),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => context.push(Routes.addIngredient, extra: 'scan'),
              icon: const Icon(Icons.photo_camera_rounded, color: AppColors.sky),
              label: const Text('Photo'),
            ),
          ),
        ]),
      ]),
    );
  }
}
