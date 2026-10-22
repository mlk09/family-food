import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai_service.dart';
import '../../core/services/offline_chef.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/id.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../data/recipe_library.dart';
import '../../models/ingredient.dart';
import '../../models/meal_plan.dart';
import '../../models/recipe.dart';
import '../ai/ai_providers.dart';

class PlannerState {
  const PlannerState({this.draft, this.request = const MealPlanRequest(), this.loading = false, this.message, this.usedAi = false});

  /// Unsaved plan being edited; null means "show the saved plan".
  final MealPlan? draft;
  final MealPlanRequest request;
  final bool loading;
  final String? message;
  final bool usedAi;

  PlannerState copyWith({MealPlan? draft, bool clearDraft = false, MealPlanRequest? request, bool? loading, String? message, bool clearMessage = false, bool? usedAi}) =>
      PlannerState(
        draft: clearDraft ? null : (draft ?? this.draft),
        request: request ?? this.request,
        loading: loading ?? this.loading,
        message: clearMessage ? null : (message ?? this.message),
        usedAi: usedAi ?? this.usedAi,
      );
}

class PlannerNotifier extends Notifier<PlannerState> {
  @override
  PlannerState build() {
    final p = ref.read(profileProvider).value;
    return PlannerState(request: MealPlanRequest(diet: p?.diet ?? 'vegetarian'));
  }

  MealPlan? get current => state.draft ?? ref.read(mealPlanProvider).value;

  Future<void> generate(MealPlanRequest req) async {
    state = state.copyWith(request: req, loading: true, clearMessage: true);
    final ctx = ref.read(aiContextProvider);
    final allergies = ctx.profile?.allergies ?? const <String>[];
    List<MealPlanItem> items;
    var usedAi = false;
    String? message;
    final ai = ref.read(aiServiceProvider);
    if (ai.isAvailable) {
      try {
        items = await ai.generateMealPlan(req, ctx);
        usedAi = true;
      } catch (e) {
        message = '${friendlyError(e)} Made a plan from our recipe book instead.';
        items = OfflineChef.mealPlan(req, ctx.ingredients, allergies: allergies, seed: DateTime.now().millisecond);
      }
    } else {
      items = OfflineChef.mealPlan(req, ctx.ingredients, allergies: allergies, seed: DateTime.now().millisecond);
    }
    // Link AI meals to library recipes when names match (instant detail view).
    items = [for (final i in items) i.recipeId != null ? i : _linkLibrary(i)];
    final plan = MealPlan(
      id: current?.id ?? newId(),
      weekStart: weekStartOf(DateTime.now()),
      people: req.people,
      budget: req.budget,
      diet: req.diet,
      mealsPerDay: req.mealsPerDay,
      items: items,
    );
    state = state.copyWith(draft: plan, loading: false, message: message, usedAi: usedAi);
  }

  MealPlanItem _linkLibrary(MealPlanItem i) {
    final lib = RecipeLibrary.byName(i.recipeName);
    return lib == null
        ? i
        : MealPlanItem(
            id: i.id, day: i.day, mealType: i.mealType, recipeName: i.recipeName, emoji: lib.emoji,
            description: i.description, ingredients: i.ingredients, recipeId: lib.id);
  }

  /// Library alternatives for swapping a meal (instant).
  List<Recipe> alternativesFor(MealPlanItem item) {
    final plan = current;
    final used = plan?.items.map((e) => e.recipeName).toSet() ?? {};
    final pantry = ref.read(ingredientsProvider).value ?? const <Ingredient>[];
    final allergies = ref.read(profileProvider).value?.allergies ?? const <String>[];
    final diet = plan?.diet;
    final pool = RecipeLibrary.all
        .where((r) =>
            r.tags.contains(item.mealType) &&
            !used.contains(r.name) &&
            IngredientMatcher.dietAllows(r, diet) &&
            !IngredientMatcher.containsAllergen(r, allergies))
        .toList();
    int overlap(Recipe r) => r.ingredients.where((i) => pantry.any((p) => IngredientNames.matches(p.name, i.name))).length;
    pool.sort((a, b) => overlap(b).compareTo(overlap(a)));
    return pool.take(6).toList();
  }

  void swap(MealPlanItem old, Recipe replacement) {
    final plan = current;
    if (plan == null) return;
    final next = OfflineChef.itemFromRecipe(replacement, old.day, old.mealType);
    state = state.copyWith(draft: plan.copyWith(items: [for (final i in plan.items) i.id == old.id ? next : i]));
  }

  void swapWithItem(MealPlanItem old, MealPlanItem replacement) {
    final plan = current;
    if (plan == null) return;
    state = state.copyWith(draft: plan.copyWith(items: [for (final i in plan.items) i.id == old.id ? replacement : i]));
  }

  /// One fresh AI idea for a single slot.
  Future<MealPlanItem?> aiSwap(MealPlanItem old) async {
    final ai = ref.read(aiServiceProvider);
    if (!ai.isAvailable) return null;
    final plan = current;
    final req = MealPlanRequest(
      people: plan?.people ?? 4,
      budget: plan?.budget,
      diet: plan?.diet ?? 'vegetarian',
      preferences: 'Suggest something different from: ${plan?.items.map((e) => e.recipeName).join(', ')}.',
      mealsPerDay: [old.mealType],
      days: 1,
    );
    final items = await ai.generateMealPlan(req, ref.read(aiContextProvider));
    if (items.isEmpty) return null;
    final i = items.first;
    return _linkLibrary(MealPlanItem(
        id: newId(), day: old.day, mealType: old.mealType, recipeName: i.recipeName, emoji: i.emoji,
        description: i.description, ingredients: i.ingredients));
  }

  Future<void> save() async {
    final d = state.draft;
    if (d == null) return;
    await ref.read(mealPlanProvider.notifier).save(d);
    state = state.copyWith(clearDraft: true, clearMessage: true);
  }

  void discard() => state = state.copyWith(clearDraft: true, clearMessage: true);

  /// Adds everything the plan needs that the kitchen doesn't have.
  Future<int> addPlanToShopping() async {
    final plan = current;
    if (plan == null) return 0;
    final pantry = ref.read(ingredientsProvider).value ?? const <Ingredient>[];
    final needed = <String>{};
    for (final item in plan.items) {
      final names = item.ingredients.isNotEmpty
          ? item.ingredients
          : (RecipeLibrary.byId(item.recipeId ?? '')?.ingredients.map((i) => i.name).toList() ?? const <String>[]);
      for (final n in names) {
        if (IngredientNames.isStaple(n)) continue;
        if (pantry.any((p) => IngredientNames.matches(p.name, n))) continue;
        needed.add(IngredientNames.normalize(n));
      }
    }
    return ref.read(shoppingProvider.notifier).addNames(needed.toList(), recipeName: 'Meal plan');
  }
}

final plannerProvider = NotifierProvider<PlannerNotifier, PlannerState>(PlannerNotifier.new);
