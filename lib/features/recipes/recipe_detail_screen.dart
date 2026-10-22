import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/offline_chef.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../models/recipe.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import '../../widgets/recipe_widgets.dart';
import '../ai/ai_providers.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(recentRecipesProvider.notifier).add(widget.recipe));
  }

  Future<void> _addMissing(Recipe r) async {
    final added = await ref.read(shoppingProvider.notifier).addNames(
          r.missingIngredients,
          recipeName: r.name,
          quantities: {for (final i in r.ingredients) i.name: i.quantity},
        );
    if (!mounted) return;
    showSnack(
      context,
      added == 0 ? 'Already on your shopping list 👍' : '🛒 Added $added item${added == 1 ? '' : 's'} to your shopping list',
      action: 'VIEW',
      onAction: () => context.go(Routes.shopping),
    );
  }

  Future<void> _toggleSave(Recipe r) async {
    final saved = await ref.read(savedRecipesProvider.notifier).toggle(r);
    if (mounted) showSnack(context, saved ? '❤️ Saved to family favourites' : 'Removed from saved recipes');
  }

  Future<void> _askSubstitute(Recipe r) async {
    final ingredient = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
            Padding(padding: const EdgeInsets.all(8), child: Text('Which ingredient do you need to replace?', style: c.text.titleLarge)),
            for (final i in r.ingredients)
              ListTile(
                leading: Text(foodEmoji(i.name), style: const TextStyle(fontSize: 24)),
                title: Text(i.name),
                trailing: i.available ? null : const Text('missing', style: TextStyle(color: AppColors.expiring)),
                onTap: () => Navigator.pop(c, i.name),
              ),
          ]),
        ),
      ),
    );
    if (ingredient == null || !mounted) return;

    final ai = ref.read(aiServiceProvider);
    List<Substitution> subs = r.substitutions.where((s) => IngredientNames.matches(s.ingredient, ingredient)).toList();
    var fromAi = false;
    if (ai.isAvailable) {
      showSnack(context, '🤖 Asking Chef AI…');
      try {
        final res = await ai.suggestSubstitutions(ingredient, r.name, ref.read(aiContextProvider));
        if (res.isNotEmpty) {
          subs = res;
          fromAi = true;
        }
      } catch (_) {/* fall back to offline list */}
    }
    if (subs.isEmpty) {
      subs = (OfflineChef.substitutions[IngredientNames.normalize(ingredient)] ?? const [])
          .map((s) => Substitution(ingredient: ingredient, substitute: s))
          .toList();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Instead of $ingredient', style: c.text.titleLarge),
            const SizedBox(height: 12),
            if (subs.isEmpty)
              const Text("I don't have a good swap for that one. Try asking Chef AI in chat for ideas.")
            else
              for (final s in subs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🔄 ', style: TextStyle(fontSize: 18)),
                    Expanded(child: Text(s.substitute, style: c.text.bodyLarge)),
                  ]),
                ),
            if (fromAi) ...[
              const SizedBox(height: 6),
              Text('AI suggestion — check for allergies before using.', style: c.text.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pantry = ref.watch(ingredientsProvider).value ?? const [];
    final r = IngredientMatcher.annotate(widget.recipe, pantry);
    final profile = ref.watch(profileProvider).value;
    final isSaved = ref.watch(savedRecipesProvider.select((s) => (s.value ?? const []).any((e) => e.name == r.name)));
    final hasAllergies = profile?.allergies.isNotEmpty ?? false;
    final allergen = hasAllergies && IngredientMatcher.containsAllergen(r, profile!.allergies);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                child: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  child: IconButton(
                    tooltip: isSaved ? 'Unsave' : 'Save',
                    icon: Icon(isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isSaved ? AppColors.tomato : Colors.white),
                    onPressed: () => _toggleSave(r),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: RecipeArt(recipe: r, height: 360, radius: 0, emojiSize: 90, heroTag: 'art-${r.id}'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            sliver: SliverList.list(children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Tag(r.isAi ? '✨ AI-generated' : '📖 Family recipe book', r.isAi ? AppColors.berry : AppColors.herb),
                for (final t in r.tags.where((t) => const ['kids', 'quick', 'healthy', 'budget'].contains(t)))
                  _Tag(const {'kids': '🧒 Kid-friendly', 'quick': '⚡ Quick', 'healthy': '🥗 Healthy', 'budget': '💰 Budget'}[t]!, AppColors.saffron),
              ]),
              const SizedBox(height: 12),
              Text(r.name, style: context.text.headlineMedium),
              if (r.rating != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(i <= r.rating!.round() ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.turmeric, size: 20),
                  const SizedBox(width: 6),
                  Text(r.rating!.toStringAsFixed(1), style: context.text.bodySmall),
                ]),
              ],
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(r.description, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                _Stat('⏱️', '${r.prepTime}m', 'Prep'),
                _Stat('🔥', '${r.cookTime}m', 'Cook'),
                _Stat('⏰', '${r.totalTime}m', 'Total'),
                _Stat('🍽️', '${r.servings}', 'Serves'),
                _Stat('📶', r.difficulty, 'Level'),
              ]),
              if (allergen || r.isAi && hasAllergies) ...[
                const SizedBox(height: 16),
                SafetyBanner(allergen
                    ? '⚠️ This recipe may contain something on your allergy list (${profile.allergies.join(', ')}). ${AppConstants.allergyWarning}'
                    : AppConstants.allergyWarning),
              ],

              // Missing ingredients
              if (r.missingIngredients.isNotEmpty) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: AppColors.expiring.withValues(alpha: 0.08),
                  borderColor: AppColors.expiring.withValues(alpha: 0.4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('🛒 Missing ingredients', style: context.text.titleMedium),
                    const SizedBox(height: 8),
                    for (final m in r.missingIngredients)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text('☐  $m', style: context.text.bodyLarge),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _addMissing(r),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Add All to Shopping List'),
                      ),
                    ),
                  ]),
                ),
              ],

              // Ingredients
              const SizedBox(height: 22),
              SectionHeader('Ingredients', emoji: '🧺', action: 'Swap one', onAction: () => _askSubstitute(r)),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  for (final i in r.ingredients)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Icon(
                          i.available ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                          color: i.available ? AppColors.fresh : AppColors.expiring,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(foodEmoji(i.name), style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(i.name, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w500))),
                        Text(i.quantity, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                      ]),
                    ),
                ]),
              ),

              // Instructions
              const SizedBox(height: 22),
              const SectionHeader('Instructions', emoji: '👩‍🍳'),
              for (final (idx, step) in r.instructions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                      child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(step, style: context.text.bodyLarge))),
                  ]),
                ),

              // Nutrition
              if (r.nutrition != null) ...[
                const SizedBox(height: 12),
                const SectionHeader('Nutrition (per serving, approx.)', emoji: '📊'),
                Row(children: [
                  _Nutri('Calories', r.nutrition!.calories, 'kcal', AppColors.saffron),
                  _Nutri('Protein', r.nutrition!.protein, 'g', AppColors.herb),
                  _Nutri('Carbs', r.nutrition!.carbs, 'g', AppColors.sky),
                  _Nutri('Fat', r.nutrition!.fat, 'g', AppColors.berry),
                ]),
                const SizedBox(height: 6),
                Text('Estimates only — not medical or dietary advice.', style: context.text.bodySmall),
              ],

              // Substitutions
              if (r.substitutions.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionHeader('Substitutions', emoji: '🔄'),
                for (final s in r.substitutions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(style: context.text.bodyLarge, children: [
                      TextSpan(text: s.ingredient, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: '  →  '),
                      TextSpan(text: s.substitute),
                    ])),
                  ),
              ],

              // Safety
              if (r.safetyNotes.isNotEmpty) ...[
                const SizedBox(height: 18),
                for (final n in r.safetyNotes) Padding(padding: const EdgeInsets.only(bottom: 8), child: SafetyBanner(n)),
              ],
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: context.palette.border)),
          ),
          child: Row(children: [
            _RoundAction(
              icon: isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: AppColors.tomato,
              label: 'Save',
              onTap: () => _toggleSave(r),
            ),
            const SizedBox(width: 8),
            _RoundAction(icon: Icons.add_shopping_cart_rounded, color: AppColors.herb, label: 'Add missing', onTap: () => _addMissing(r)),
            const SizedBox(width: 8),
            _RoundAction(
              emoji: '🤖',
              color: AppColors.berry,
              label: 'Ask Chef AI',
              onTap: () => context.push(Routes.chef, extra: r),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Start Cooking',
                icon: Icons.play_arrow_rounded,
                height: 56,
                onPressed: () => context.push(Routes.cooking, extra: r),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.value, this.label);
  final String emoji, value, label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.border),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
          ]),
        ),
      );
}

class _Nutri extends StatelessWidget {
  const _Nutri(this.label, this.value, this.unit, this.color);
  final String label, unit;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(value?.toString() ?? '—', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            Text('$unit · $label', style: context.text.bodySmall?.copyWith(fontSize: 11)),
          ]),
        ),
      );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({this.icon, this.emoji, required this.color, required this.label, required this.onTap});
  final IconData? icon;
  final String? emoji;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(18)),
              child: emoji != null ? Text(emoji!, style: const TextStyle(fontSize: 24)) : Icon(icon, color: color, size: 26),
            ),
          ),
        ),
      );
}
