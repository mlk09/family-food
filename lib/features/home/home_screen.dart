import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/id.dart';
import '../../data/providers.dart';
import '../../data/recipe_library.dart';
import '../../data/session.dart';
import '../../models/ingredient.dart';
import '../../models/meal_plan.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import '../../widgets/recipe_widgets.dart';
import '../meal_plan/meal_plan_screen.dart' show openMealItem;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = ref.watch(profileProvider).value;
    final pantry = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    final plan = ref.watch(mealPlanProvider).value;
    final shopping = ref.watch(shoppingProvider).value ?? const [];
    final saved = ref.watch(savedRecipesProvider).value ?? const [];
    final recent = ref.watch(recentRecipesProvider);

    final now = DateTime.now();
    final expiring = pantry.where((i) => i.freshness() == Freshness.expiringSoon).toList()
      ..sort((a, b) => (a.daysLeft() ?? 99).compareTo(b.daysLeft() ?? 99));
    final expired = pantry.where((i) => i.freshness() == Freshness.expired).length;
    final freshPct = pantry.isEmpty ? 0.0 : (pantry.length - expired - expiring.length) / pantry.length;
    final todayIdx = now.weekday - 1;
    final todayMeals = plan?.itemsForDay(todayIdx) ?? const <MealPlanItem>[];
    final streak = profile?.currentStreak() ?? 0;
    final pendingShopping = shopping.where((s) => !s.checked).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.saffron,
          onRefresh: () async {
            await Future.wait([
              ref.read(ingredientsProvider.notifier).refresh(),
              ref.read(mealPlanProvider.notifier).refresh(),
              ref.read(shoppingProvider.notifier).refresh(),
              ref.read(profileProvider.notifier).refresh(),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
            children: [
              // ── Top bar ──
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go(Routes.profile),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.saffron,
                      backgroundImage: profile?.avatarUrl != null ? NetworkImage(profile!.avatarUrl!) : null,
                      child: profile?.avatarUrl == null
                          ? Text(
                              (profile?.firstName ?? 'C')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (session.isDemo) const DemoBadge(),
                  const Spacer(),
                  _BellButton(count: expiring.length + expired, onTap: () => context.go(Routes.kitchen)),
                ],
              ),
              const SizedBox(height: 16),

              // ── Hero ──
              _HeroCard(
                date: DateFormat('EEEE d MMM').format(now),
                greeting: '${greetingFor(now)}, ${profile?.firstName ?? 'Chef'} 👋',
                freshPct: freshPct,
                itemCount: pantry.length,
                onCook: () => context.push(Routes.cook),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.add_rounded,
                      label: 'Add Ingredient',
                      color: AppColors.herb,
                      onTap: () => context.push(Routes.addIngredient),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.photo_camera_rounded,
                      label: 'Scan Ingredients',
                      color: AppColors.sky,
                      onTap: () => context.push(Routes.addIngredient, extra: 'scan'),
                    ),
                  ),
                ],
              ),

              // ── Expiring alert ──
              if (expiring.isNotEmpty) ...[
                const SizedBox(height: 14),
                AppCard(
                  onTap: () => context.push(Routes.cook),
                  borderColor: AppColors.expiring.withValues(alpha: 0.5),
                  color: AppColors.expiring.withValues(alpha: 0.10),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(foodEmoji(expiring.first.name, expiring.first.category), style: const TextStyle(fontSize: 30)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use soon: ${expiring.take(3).map((e) => e.name).join(', ')}',
                              style: context.text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('Tap to see recipes that use them first', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ],

              // ── My Kitchen ──
              const SizedBox(height: 18),
              SectionHeader('My Kitchen', emoji: '🧺', action: 'See all', onAction: () => context.go(Routes.kitchen)),
              if (pantry.isEmpty)
                AppCard(
                  onTap: () => context.push(Routes.addIngredient),
                  child: Row(
                    children: [
                      const IconChip(emoji: '🥕', color: AppColors.herb),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Your kitchen is empty. Add what you have at home to get recipe ideas.',
                          style: context.text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 20 + MediaQuery.textScalerOf(context).scale(92),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pantry.length.clamp(0, 12),
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final ing = pantry[i];
                      return SizedBox(
                        width: 100,
                        child: AppCard(
                          padding: const EdgeInsets.all(10),
                          onTap: () => context.push(Routes.addIngredient, extra: ing),
                          // Scales down instead of clipping with very large system fonts.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: 78,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Text(foodEmoji(ing.name, ing.category), style: const TextStyle(fontSize: 30)),
                                      Positioned(right: -6, top: -2, child: FreshnessBadge(ing, compact: true)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ing.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(ing.quantityLabel, style: context.text.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // ── Today's meals ──
              const SizedBox(height: 18),
              SectionHeader("Today's Meals", emoji: '🍽️', action: 'Plan', onAction: () => context.go(Routes.plan)),
              Row(
                children: [
                  for (final type in AppConstants.mealTypes) ...[
                    Expanded(
                      child: _MealTile(type: type, item: todayMeals.where((m) => m.mealType == type).firstOrNull),
                    ),
                    if (type != 'dinner') const SizedBox(width: 10),
                  ],
                ],
              ),

              // ── Stats grid ──
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  StatTile(
                    emoji: '🔥',
                    color: AppColors.saffron,
                    label: 'Family Cooking Streak',
                    value: '$streak day${streak == 1 ? '' : 's'}',
                    hint: streak == 0 ? 'Cook today to start!' : 'Keep it going!',
                    progress: (streak % 7) / 7,
                  ),
                  StatTile(
                    emoji: '🤖',
                    color: AppColors.berry,
                    label: 'Ask Chef AI',
                    value: 'Chat',
                    hint: '"I have 20 minutes…"',
                    onTap: () => context.push(Routes.chef),
                  ),
                  StatTile(
                    emoji: '🛒',
                    color: AppColors.herb,
                    label: 'Shopping',
                    value: '$pendingShopping item${pendingShopping == 1 ? '' : 's'}',
                    hint: pendingShopping == 0 ? 'All stocked up' : 'Tap to view list',
                    onTap: () => context.go(Routes.shopping),
                  ),
                  StatTile(
                    emoji: '❤️',
                    color: AppColors.tomato,
                    label: 'Saved Recipes',
                    value: '${saved.length}',
                    hint: 'Family favourites',
                    onTap: () => context.push(Routes.saved),
                  ),
                ],
              ),

              // ── Recently viewed ──
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionHeader('Recently Viewed', emoji: '🕘'),
                SizedBox(
                  height: 168,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(
                      width: 150,
                      child: GestureDetector(
                        onTap: () => context.push(Routes.recipe, extra: recent[i]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RecipeArt(recipe: recent[i], height: 118, radius: 18, emojiSize: 40),
                            const SizedBox(height: 8),
                            Text(recent[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                            Text('${recent[i].totalTime} min · ${recent[i].difficulty}', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.date, required this.greeting, required this.freshPct, required this.itemCount, required this.onCook});
  final String date, greeting;
  final double freshPct;
  final int itemCount;
  final VoidCallback onCook;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: dark ? const Color(0xFF4A2A35) : const Color(0xFFFFD2B8)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF2B1720), Color(0xFF1D1426), Color(0xFF16111E)]
              : const [Color(0xFFFFE8D6), Color(0xFFFFF4EA), Colors.white],
        ),
        boxShadow: [BoxShadow(color: context.palette.glow, blurRadius: 40, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🗓️ $date', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(greeting, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('What are you cooking today?', style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ProgressRing(
                value: freshPct,
                center: itemCount == 0 ? '—' : '${(freshPct * 100).round()}%',
                caption: 'fresh',
                size: 84,
                color: AppColors.herb,
              ),
            ],
          ),
          const SizedBox(height: 18),
          GradientButton(label: 'What Can I Cook?', icon: Icons.auto_awesome_rounded, onPressed: onCook, gradient: AppColors.aiGradient),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    radius: 20,
    child: Row(
      children: [
        IconChip(icon: icon, color: color, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: context.text.titleMedium?.copyWith(fontSize: 15.5, height: 1.15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: count == 0 ? 'No alerts' : '$count ingredient alerts',
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.palette.card,
              border: Border.all(color: context.palette.border),
            ),
            child: const Icon(Icons.notifications_none_rounded),
          ),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: const BoxDecoration(color: AppColors.tomato, shape: BoxShape.circle),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MealTile extends ConsumerWidget {
  const _MealTile({required this.type, required this.item});
  final String type;
  final MealPlanItem? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = type[0].toUpperCase() + type.substring(1);
    final lib = item?.recipeId == null ? null : RecipeLibrary.byId(item!.recipeId!);
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => item == null ? context.go(Routes.plan) : openMealItem(context, ref, item!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppConstants.mealEmoji[type]!, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(label, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            item?.recipeName ?? 'Not planned',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: item == null ? context.palette.muted : null),
          ),
          if (lib != null) Text('${lib.totalTime} min', style: context.text.bodySmall),
        ],
      ),
    );
  }
}
