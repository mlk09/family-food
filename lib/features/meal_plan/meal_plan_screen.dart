import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/ai_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/id.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../data/recipe_library.dart';
import '../../data/session.dart';
import '../../models/meal_plan.dart';
import '../../models/recipe.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import '../ai/ai_providers.dart';
import 'meal_plan_controller.dart';

/// Opens the full recipe behind a meal-plan item: library recipe instantly,
/// otherwise asks Chef AI for the full recipe (with an offline fallback).
Future<void> openMealItem(BuildContext context, WidgetRef ref, MealPlanItem item) async {
  final lib = item.recipeId == null ? RecipeLibrary.byName(item.recipeName) : RecipeLibrary.byId(item.recipeId!);
  if (lib != null) {
    context.push(Routes.recipe, extra: lib);
    return;
  }
  final ai = ref.read(aiServiceProvider);
  Recipe recipe = Recipe(
    id: newId(),
    name: item.recipeName,
    emoji: item.emoji,
    description: item.description,
    ingredients: [for (final i in item.ingredients) RecipeIngredient(name: i)],
    instructions: const ['Ask Chef AI for step-by-step instructions using the 🤖 button below.'],
    source: 'ai',
  );
  if (ai.isAvailable) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: AppCard(child: Text('👩‍🍳 Chef AI is writing the recipe…'))),
    );
    try {
      recipe = await ai.recipeDetail(item.recipeName, ref.read(aiContextProvider));
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e));
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (context.mounted) context.push(Routes.recipe, extra: recipe);
}

class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planner = ref.watch(plannerProvider);
    final saved = ref.watch(mealPlanProvider).value;
    final plan = planner.draft ?? saved;
    final isDraft = planner.draft != null;
    final todayIdx = DateTime.now().weekday - 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Meal Plan'),
          const SizedBox(width: 10),
          if (ref.watch(sessionProvider).isDemo && !isDraft && plan != null) const DemoBadge(),
        ]),
        actions: [
          if (plan != null)
            IconButton(
              tooltip: 'Plan settings',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _openPlanner(context, ref),
            ),
        ],
      ),
      body: planner.loading
          ? const _Generating()
          : plan == null
              ? _EmptyPlan(onStart: () => _openPlanner(context, ref))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                  children: [
                    AppCard(
                      gradient: LinearGradient(colors: [AppColors.saffron.withValues(alpha: 0.16), AppColors.berry.withValues(alpha: 0.12)]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(isDraft ? (planner.usedAi ? '✨ New AI plan' : '📖 New plan') : '📅 This week', style: context.text.titleLarge),
                          const Spacer(),
                          if (isDraft)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.turmeric.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                              child: const Text('Not saved', style: TextStyle(color: AppColors.turmeric, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                        ]),
                        const SizedBox(height: 8),
                        Wrap(spacing: 14, runSpacing: 6, children: [
                          Text('👨‍👩‍👧 ${plan.people} people'),
                          Text('🥗 ${AppConstants.dietLabels[plan.diet] ?? plan.diet}'),
                          if (plan.budget != null) Text('💰 ₹${plan.budget}/week'),
                          Text('🍽️ ${plan.mealsPerDay.length} meal${plan.mealsPerDay.length == 1 ? '' : 's'}/day'),
                        ]),
                        if (planner.message != null) ...[
                          const SizedBox(height: 10),
                          Text(planner.message!, style: context.text.bodySmall),
                        ],
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (isDraft)
                            FilledButton.icon(
                              onPressed: () async {
                                await ref.read(plannerProvider.notifier).save();
                                if (context.mounted) showSnack(context, '✅ Meal plan saved for your family');
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Save plan'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => ref.read(plannerProvider.notifier).generate(planner.request),
                            icon: const Icon(Icons.autorenew_rounded),
                            label: const Text('Regenerate'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final n = await ref.read(plannerProvider.notifier).addPlanToShopping();
                              if (context.mounted) {
                                showSnack(context, n == 0 ? 'You already have everything 🎉' : '🛒 Added $n ingredients to shopping',
                                    action: 'VIEW', onAction: () => context.go(Routes.shopping));
                              }
                            },
                            icon: const Icon(Icons.add_shopping_cart_rounded),
                            label: const Text('Add to shopping'),
                          ),
                          if (isDraft)
                            TextButton(onPressed: () => ref.read(plannerProvider.notifier).discard(), child: const Text('Discard')),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    for (var d = 0; d < 7; d++)
                      if (plan.itemsForDay(d).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DayCard(day: d, isToday: d == todayIdx, items: plan.itemsForDay(d)),
                        ),
                  ],
                ),
    );
  }

  static void _openPlanner(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PlannerForm(),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              width: 160,
              height: 160,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.aiGradient),
              child: const Text('📅', style: TextStyle(fontSize: 70)),
            ),
            const SizedBox(height: 26),
            Text('Plan your week in seconds', style: context.text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Tell Chef AI your family size, budget and diet. Get a 7-day plan that uses what you already have.',
                textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 26),
            GradientButton(label: 'Create My Meal Plan', icon: Icons.auto_awesome_rounded, gradient: AppColors.aiGradient, onPressed: onStart),
          ]),
        ),
      );
}

class _Generating extends StatelessWidget {
  const _Generating();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AppCard(
            child: Row(children: [
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text('Chef AI is planning your week…', style: context.text.titleMedium)),
            ]),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 5; i++) ...[const Shimmer(height: 92), const SizedBox(height: 12)],
        ],
      );
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.isToday, required this.items});
  final int day;
  final bool isToday;
  final List<MealPlanItem> items;

  Future<void> _swap(BuildContext context, WidgetRef ref, MealPlanItem item) async {
    final ctl = ref.read(plannerProvider.notifier);
    final alts = ctl.alternativesFor(item);
    final aiAvailable = ref.read(aiServiceProvider).isAvailable;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Padding(padding: const EdgeInsets.all(6), child: Text('Swap ${item.recipeName}', style: c.text.titleLarge)),
            if (aiAvailable)
              ListTile(
                leading: const Text('✨', style: TextStyle(fontSize: 24)),
                title: const Text('Ask Chef AI for a new idea'),
                onTap: () => Navigator.pop(c, 'ai'),
              ),
            for (final r in alts)
              ListTile(
                leading: Text(r.emoji, style: const TextStyle(fontSize: 26)),
                title: Text(r.name),
                subtitle: Text('${r.totalTime} min · ${r.difficulty}'),
                onTap: () => Navigator.pop(c, r),
              ),
          ]),
        ),
      ),
    );
    if (choice is Recipe) {
      ctl.swap(item, choice);
    } else if (choice == 'ai') {
      if (context.mounted) showSnack(context, '✨ Asking Chef AI…');
      try {
        final next = await ctl.aiSwap(item);
        if (next != null) ctl.swapWithItem(item, next);
        if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      } catch (e) {
        if (context.mounted) showSnack(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pantry = ref.watch(ingredientsProvider).value ?? const [];
    return AppCard(
      borderColor: isToday ? AppColors.saffron.withValues(alpha: 0.7) : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(AppConstants.weekdays[day].toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.4, fontSize: 14, color: isToday ? AppColors.saffron : context.palette.muted)),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.saffron, borderRadius: BorderRadius.circular(8)),
              child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        for (final item in items)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => openMealItem(context, ref, item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Text(item.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.recipeName, style: context.text.titleMedium),
                    Text(
                      '${AppConstants.mealEmoji[item.mealType] ?? ''} ${item.mealType[0].toUpperCase()}${item.mealType.substring(1)}'
                      '${switch (_missingCount(item, pantry)) { 0 => ' · ✓ have all', 1 => ' · need 1 item', final n => ' · need $n items' }}',
                      style: context.text.bodySmall,
                    ),
                  ]),
                ),
                IconButton(tooltip: 'Swap meal', onPressed: () => _swap(context, ref, item), icon: const Icon(Icons.swap_horiz_rounded)),
              ]),
            ),
          ),
      ]),
    );
  }

  static int _missingCount(MealPlanItem item, List pantry) => item.ingredients
      .where((n) => !IngredientNames.isStaple(n) && !pantry.any((p) => IngredientNames.matches(p.name as String, n)))
      .length;
}

class _PlannerForm extends ConsumerStatefulWidget {
  const _PlannerForm();

  @override
  ConsumerState<_PlannerForm> createState() => _PlannerFormState();
}

class _PlannerFormState extends ConsumerState<_PlannerForm> {
  late MealPlanRequest r = ref.read(plannerProvider).request;
  late int _people = r.people;
  late final _budget = TextEditingController(text: r.budget?.toString() ?? '');
  late final _prefs = TextEditingController(text: r.preferences);
  late String _diet = r.diet;
  late Set<String> _meals = r.mealsPerDay.toSet();
  late bool _useKitchen = r.useKitchen;

  @override
  void dispose() {
    _budget.dispose();
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Plan your week', style: context.text.headlineSmall),
          const SizedBox(height: 18),
          Text('Number of people', style: context.text.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            IconButton.filledTonal(onPressed: _people > 1 ? () => setState(() => _people--) : null, icon: const Icon(Icons.remove_rounded)),
            Expanded(child: Text('👨‍👩‍👧 $_people', textAlign: TextAlign.center, style: context.text.headlineSmall)),
            IconButton.filledTonal(onPressed: _people < 20 ? () => setState(() => _people++) : null, icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 18),
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Weekly budget (optional)', prefixText: '₹ ', hintText: 'e.g. 2500'),
          ),
          const SizedBox(height: 18),
          Text('Diet', style: context.text.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in AppConstants.diets) ChoiceChip(label: Text(AppConstants.dietLabels[d]!), selected: _diet == d, onSelected: (_) => setState(() => _diet = d)),
          ]),
          const SizedBox(height: 18),
          Text('Meals per day', style: context.text.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final m in AppConstants.mealTypes)
              FilterChip(
                label: Text('${AppConstants.mealEmoji[m]} ${m[0].toUpperCase()}${m.substring(1)}'),
                selected: _meals.contains(m),
                onSelected: (v) => setState(() {
                  v ? _meals.add(m) : _meals.remove(m);
                  if (_meals.isEmpty) _meals = {'dinner'};
                }),
              ),
          ]),
          const SizedBox(height: 18),
          TextField(
            controller: _prefs,
            decoration: const InputDecoration(labelText: 'Food preferences (optional)', hintText: 'e.g. North Indian, no mushrooms, kid-friendly'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useKitchen,
            onChanged: (v) => setState(() => _useKitchen = v),
            title: const Text('Use ingredients from My Kitchen'),
            subtitle: const Text('Less shopping, less waste'),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Generate 7-Day Plan',
            icon: Icons.auto_awesome_rounded,
            gradient: AppColors.aiGradient,
            onPressed: () {
              final req = MealPlanRequest(
                people: _people,
                budget: int.tryParse(_budget.text.trim()),
                diet: _diet,
                preferences: _prefs.text.trim(),
                useKitchen: _useKitchen,
                mealsPerDay: AppConstants.mealTypes.where(_meals.contains).toList(),
              );
              Navigator.pop(context);
              ref.read(plannerProvider.notifier).generate(req);
            },
          ),
        ],
      ),
    );
  }
}
