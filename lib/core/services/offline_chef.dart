import 'dart:math';

import '../../data/recipe_library.dart';
import '../../models/ingredient.dart';
import '../../models/meal_plan.dart';
import '../../models/profile.dart';
import '../../models/recipe.dart';
import '../utils/id.dart';
import '../utils/ingredient_matcher.dart';
import 'ai_service.dart';

/// On-device fallback used when the AI backend is not configured, offline, or
/// busy. Keeps the core journey working everywhere with zero latency.
class OfflineChef {
  OfflineChef._();

  static const substitutions = <String, List<String>>{
    'onion': ['Spring onion', 'Cabbage (finely chopped) for crunch', 'A pinch of asafoetida (hing) for flavour'],
    'garlic': ['A pinch of asafoetida (hing)', 'Ginger', 'Garlic powder (¼ tsp per clove)'],
    'egg': ['2 tbsp curd per egg (baking)', 'Mashed banana (pancakes)', 'Crumbled paneer or tofu (scrambles)'],
    'tomato': ['Tomato puree or ketchup (less)', 'Curd + a squeeze of lemon for tang', 'Tamarind water'],
    'paneer': ['Tofu', 'Boiled potato cubes', 'Boiled chickpeas'],
    'cream': ['Milk + 1 tsp butter', 'Thick curd (add off the heat)', 'Cashew paste'],
    'curd': ['Buttermilk', 'Lemon juice in milk (for marinades)', 'Coconut milk'],
    'butter': ['Ghee', 'Any cooking oil'],
    'ghee': ['Butter', 'Any cooking oil'],
    'milk': ['Water + a little cream', 'Oat or soy milk', 'Coconut milk'],
    'rice': ['Broken wheat (dalia)', 'Quinoa', 'Poha (for quick dishes)'],
    'lemon': ['Amchur (dry mango powder)', 'Vinegar (a few drops)', 'Tamarind'],
    'green chilli': ['Red chilli powder (a pinch)', 'Black pepper (milder, kid-friendly)'],
    'spring onion': ['Coriander leaves', 'Regular onion, finely chopped'],
    'soy sauce': ['Salt + a few drops of lemon', 'Worcestershire sauce'],
    'coriander leaves': ['Mint leaves', 'Spring onion greens', 'Kasuri methi (dry)'],
    'chicken': ['Paneer', 'Boiled eggs', 'Soya chunks'],
    'wheat flour': ['Multigrain flour', 'Rice flour (for thin crepes)'],
    'sugar': ['Jaggery', 'Honey (not for babies under 1)'],
    'cheese': ['Paneer', 'Thick white sauce'],
  };

  static List<RecipeMatch> recipes(List<Ingredient> pantry, UserProfile? p, {MatchFilters? filters}) =>
      IngredientMatcher.match(
        pantry,
        filters: filters ?? MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const []),
      );

  /// Simple rotating plan from the library, preferring kitchen ingredients.
  static List<MealPlanItem> mealPlan(MealPlanRequest req, List<Ingredient> pantry, {List<String> allergies = const [], int seed = 0}) {
    final rnd = Random(seed);
    final items = <MealPlanItem>[];
    for (final meal in req.mealsPerDay) {
      final pool = RecipeLibrary.all
          .where((r) => r.tags.contains(meal) && IngredientMatcher.dietAllows(r, req.diet) && !IngredientMatcher.containsAllergen(r, allergies))
          .toList();
      if (pool.isEmpty) continue;
      // Rank by pantry overlap, then shuffle within the top so plans vary.
      final ranked = req.useKitchen
          ? (pool..sort((a, b) => _overlap(b, pantry).compareTo(_overlap(a, pantry))))
          : (pool..shuffle(rnd));
      final top = ranked.take(max(7, ranked.length ~/ 2)).toList()..shuffle(rnd);
      for (var d = 0; d < req.days.clamp(1, 7); d++) {
        final r = top[d % top.length];
        items.add(itemFromRecipe(r, d, meal));
      }
    }
    return items;
  }

  static MealPlanItem itemFromRecipe(Recipe r, int day, String meal) => MealPlanItem(
        id: newId(),
        day: day,
        mealType: meal,
        recipeName: r.name,
        emoji: r.emoji,
        description: r.description,
        ingredients: r.ingredients.where((i) => !IngredientNames.isStaple(i.name)).map((i) => i.name).toList(),
        recipeId: r.id,
      );

  static int _overlap(Recipe r, List<Ingredient> pantry) =>
      r.ingredients.where((i) => pantry.any((p) => IngredientNames.matches(p.name, i.name))).length;

  /// Rule-based Chef reply for offline / demo use.
  static String reply(String question, AIContext ctx, {Recipe? recipe}) {
    final q = question.toLowerCase();
    final pantry = ctx.ingredients;
    final p = ctx.profile;
    final filtersBase = MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const []);
    String list(List<RecipeMatch> m) => m.isEmpty
        ? 'I could not find a match in my offline recipe book — try adding a few more ingredients.'
        : m.take(3).map((e) => '• ${e.recipe.emoji} **${e.recipe.name}** — ${e.recipe.totalTime} min'
            '${e.missing.isEmpty ? '' : ' (need: ${e.missing.take(2).join(', ')})'}').join('\n');

    // Substitution questions: "I don't have onions", "without eggs", "instead of"
    final subMatch = RegExp(r"(?:don'?t have|do not have|no|without|instead of|out of|replace|substitute(?: for)?)\s+(?:any\s+)?([a-z ]{3,25})").firstMatch(q);
    if (subMatch != null) {
      final raw = subMatch.group(1)!.trim().split(RegExp(r'\s+(?:what|can|in|for|\?)')).first.trim();
      final key = IngredientNames.normalize(raw);
      final subs = substitutions[key];
      if (subs != null) {
        return 'No ${raw.trim()}? No problem! 🙌 Try:\n${subs.map((s) => '• $s').join('\n')}'
            '${recipe != null ? '\n\nFor **${recipe.name}**, add the substitute at the same step.' : ''}';
      }
    }

    final minutes = RegExp(r'(\d+)\s*(?:min|minute)').firstMatch(q);
    if (minutes != null || q.contains('quick') || q.contains('fast') || q.contains('hurry')) {
      final m = int.tryParse(minutes?.group(1) ?? '') ?? 25;
      final res = IngredientMatcher.match(pantry, filters: MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const [], maxMinutes: m));
      return 'Here is what you can make in about $m minutes with your kitchen ⏱️\n${list(res)}';
    }

    if (q.contains('child') || q.contains('kid') || q.contains('school') || q.contains('tiffin')) {
      final res = IngredientMatcher.match(pantry, filters: MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const [], kidsOnly: true));
      return 'Kid-friendly ideas 🧒 (mild spice, easy to eat):\n${list(res)}\n\n'
          '🛡️ Children should cook only with an adult nearby, especially around knives, hot oil and stoves.';
    }

    if (q.contains('spicy') || q.contains('spice') || q.contains('mild')) {
      return 'To make a dish less spicy 🌶️➡️🥛:\n• Skip or de-seed green chillies\n• Halve the red chilli powder and garam masala\n'
          '• Add a spoon of curd, cream or milk at the end\n• A pinch of sugar balances heat\n• Serve with plain rice or raita';
    }

    if (q.contains('healthy') || q.contains('light') || q.contains('diet')) {
      final healthy = IngredientMatcher.match(pantry, filters: filtersBase).where((e) => e.recipe.tags.contains('healthy')).toList();
      return 'Healthy picks from your kitchen 🥗:\n${list(healthy)}\n\nTip: add a bowl of salad or curd for extra protein and fibre.';
    }

    final budget = RegExp(r'(?:₹|rs\.?|inr|rupees?)\s*(\d+)|(\d+)\s*(?:₹|rs|rupees?)').firstMatch(q);
    if (budget != null || q.contains('budget') || q.contains('cheap')) {
      final amt = budget?.group(1) ?? budget?.group(2);
      final res = IngredientMatcher.match(pantry, filters: filtersBase).where((e) => e.recipe.tags.contains('budget')).toList();
      return 'Budget-friendly${amt != null ? ' meals under ₹$amt' : ' meals'} 💰\n${list(res)}\n\n'
          'Dal, rice, eggs, potatoes and seasonal vegetables give the most nutrition per rupee.';
    }

    if (q.contains('breakfast')) {
      return 'Breakfast ideas 🍳\n${list(IngredientMatcher.match(pantry, filters: MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const [], mealType: 'breakfast')))}';
    }

    if (q.contains('dinner') || q.contains('lunch') || q.contains('cook') || q.contains('make') || q.contains('what')) {
      return 'Based on your kitchen, I suggest 👩‍🍳\n${list(IngredientMatcher.match(pantry, filters: filtersBase))}';
    }

    if (q.contains('store') || q.contains('fresh') || q.contains('expire')) {
      final soon = pantry.where((i) => i.freshness() == Freshness.expiringSoon).map((i) => i.name).toList();
      return soon.isEmpty
          ? 'Everything in your kitchen looks fresh! 🟢 Keep onions and potatoes in a cool, dark place (not together).'
          : 'Use these soon 🟡: ${soon.join(', ')}. Tap "What Can I Cook?" — I prioritise them automatically.';
    }

    return "I'm Chef AI 👩‍🍳 (offline mode). Ask me things like:\n"
        "• \"I don't have onions — what can I use?\"\n• \"I have only 20 minutes\"\n"
        '• "What can I cook for children?"\n• "Make this less spicy"\n• "Give me a healthy dinner"';
  }
}
