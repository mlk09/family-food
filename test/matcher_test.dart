import 'package:family_food_assistant/core/services/ai_service.dart';
import 'package:family_food_assistant/core/services/offline_chef.dart';
import 'package:family_food_assistant/core/utils/ingredient_matcher.dart';
import 'package:family_food_assistant/data/recipe_library.dart';
import 'package:family_food_assistant/features/kitchen/kitchen_screen.dart';
import 'package:family_food_assistant/features/shopping/shopping_screen.dart';
import 'package:family_food_assistant/models/ingredient.dart';
import 'package:family_food_assistant/models/profile.dart';
import 'package:family_food_assistant/models/shopping_item.dart';
import 'package:flutter_test/flutter_test.dart';

Ingredient ing(String name, {int? days, String cat = 'vegetables'}) => Ingredient(
      id: name,
      name: name,
      category: cat,
      expiryDate: days == null ? null : DateTime.now().add(Duration(days: days)),
    );

void main() {
  group('IngredientNames', () {
    test('normalises plurals and Hindi names', () {
      expect(IngredientNames.normalize('Tomatoes'), 'tomato');
      expect(IngredientNames.normalize('Aloo'), 'potato');
      expect(IngredientNames.normalize('pyaz'), 'onion');
      expect(IngredientNames.normalize('Eggs'), 'egg');
      expect(IngredientNames.normalize('Dahi'), 'curd');
    });
    test('matches compound names', () {
      expect(IngredientNames.matches('Rice', 'cooked rice'), isTrue);
      expect(IngredientNames.matches('Potato', 'tomato'), isFalse);
    });
  });

  group('IngredientMatcher', () {
    final pantry = [ing('Potato'), ing('Tomato'), ing('Onion'), ing('Rice', cat: 'grains'), ing('Egg', cat: 'eggs')];

    test('spec example: potato, tomato, onion, rice, egg → egg fried rice & aloo tamatar', () {
      final names = IngredientMatcher.match(pantry).map((m) => m.recipe.name).toList();
      expect(names, contains('Masala Egg Rice'));
      expect(names, contains('Aloo Tamatar'));
      expect(names, contains('Egg Fried Rice'));
    });

    test('ranks recipes with full coverage first', () {
      final m = IngredientMatcher.match(pantry);
      for (var i = 1; i < m.length; i++) {
        expect(m[i - 1].score >= m[i].score, isTrue);
      }
      final fried = m.firstWhere((x) => x.recipe.id == 'egg-fried-rice');
      expect(fried.missing, contains('spring onion'));
      expect(fried.missing, isNot(contains('salt')), reason: 'staples are never missing');
    });

    test('expired ingredients are ignored', () {
      final m = IngredientMatcher.match([ing('Paneer', days: -2, cat: 'dairy')]);
      expect(m.where((x) => x.used.contains('paneer')), isEmpty);
    });

    test('diet filters', () {
      bool any(String diet, String id) => IngredientMatcher.match(pantry, filters: MatchFilters(diet: diet)).any((m) => m.recipe.id == id);
      expect(any('vegetarian', 'egg-fried-rice'), isFalse);
      expect(any('eggetarian', 'egg-fried-rice'), isTrue);
      expect(any('jain', 'aloo-tamatar'), isFalse, reason: 'jain excludes potato & onion');
      final chicken = RecipeLibrary.byId('chicken-curry')!;
      expect(IngredientMatcher.dietAllows(chicken, 'vegetarian'), isFalse);
      expect(IngredientMatcher.dietAllows(chicken, 'non-vegetarian'), isTrue);
      expect(IngredientMatcher.dietAllows(RecipeLibrary.byId('poha')!, 'vegan'), isTrue);
    });

    test('allergy filter removes recipes with allergens', () {
      final poha = RecipeLibrary.byId('poha')!;
      expect(IngredientMatcher.containsAllergen(poha, ['nuts']), isTrue);
      expect(IngredientMatcher.containsAllergen(RecipeLibrary.byId('veg-pasta')!, ['gluten']), isTrue);
      expect(IngredientMatcher.containsAllergen(RecipeLibrary.byId('jeera-rice')!, ['dairy']), isTrue, reason: 'ghee');
      expect(IngredientMatcher.containsAllergen(RecipeLibrary.byId('aloo-tamatar')!, ['peanuts']), isFalse);
    });

    test('time and kids filters', () {
      final quick = IngredientMatcher.match(pantry, filters: const MatchFilters(maxMinutes: 20));
      expect(quick.every((m) => m.recipe.totalTime <= 20), isTrue);
      final kids = IngredientMatcher.match(pantry, filters: const MatchFilters(kidsOnly: true));
      expect(kids.every((m) => m.recipe.tags.contains('kids')), isTrue);
    });

    test('annotate marks availability', () {
      final r = IngredientMatcher.annotate(RecipeLibrary.byId('egg-fried-rice')!, pantry);
      expect(r.ingredients.firstWhere((i) => i.name == 'egg').available, isTrue);
      expect(r.missingIngredients, containsAll(['spring onion', 'soy sauce', 'garlic']));
    });

    test('categoryFor groups shopping items', () {
      expect(IngredientMatcher.categoryFor('Paneer'), 'dairy');
      expect(IngredientMatcher.categoryFor('Tomatoes'), 'vegetables');
      expect(IngredientMatcher.categoryFor('Atta'), 'grains');
      expect(IngredientMatcher.categoryFor('Dish soap'), 'other');
    });
  });

  test('every library recipe is complete', () {
    final ids = <String>{};
    for (final r in RecipeLibrary.all) {
      expect(ids.add(r.id), isTrue, reason: 'duplicate id ${r.id}');
      expect(r.ingredients, isNotEmpty, reason: r.name);
      expect(r.instructions.length, greaterThanOrEqualTo(4), reason: r.name);
      expect(r.nutrition, isNotNull, reason: r.name);
      expect(r.substitutions, isNotEmpty, reason: r.name);
      expect(r.tags.any((t) => ['breakfast', 'lunch', 'dinner', 'snack'].contains(t)), isTrue, reason: r.name);
    }
  });

  group('OfflineChef', () {
    final ctx = AIContext(
      ingredients: [ing('Potato'), ing('Tomato'), ing('Onion'), ing('Rice', cat: 'grains'), ing('Egg', cat: 'eggs')],
      profile: const UserProfile(id: 'u', diet: 'eggetarian'),
    );

    test('answers substitution questions', () {
      expect(OfflineChef.reply("I don't have onions. What can I use?", ctx), contains('Spring onion'));
      expect(OfflineChef.reply('Can I make this recipe without eggs?', ctx), contains('curd'));
    });
    test('answers time, kids, spice and budget questions', () {
      expect(OfflineChef.reply('I have only 20 minutes.', ctx), contains('20 minutes'));
      expect(OfflineChef.reply('What can I cook for children?', ctx), contains('Kid-friendly'));
      expect(OfflineChef.reply('Make this less spicy.', ctx), contains('less spicy'));
      expect(OfflineChef.reply('I have ₹300. What can I cook for my family?', ctx), contains('₹300'));
    });

    test('meal plan respects diet, allergies and days', () {
      final items = OfflineChef.mealPlan(
        const MealPlanRequest(diet: 'vegetarian', mealsPerDay: ['breakfast', 'dinner']),
        ctx.ingredients,
        allergies: const ['peanuts'],
      );
      expect(items.length, 14);
      for (final i in items) {
        final r = RecipeLibrary.byId(i.recipeId!)!;
        expect(IngredientMatcher.dietAllows(r, 'vegetarian'), isTrue, reason: r.name);
        expect(IngredientMatcher.containsAllergen(r, ['peanuts']), isFalse, reason: r.name);
        expect(r.tags, contains(i.mealType));
      }
      expect(items.map((e) => e.day).toSet(), {0, 1, 2, 3, 4, 5, 6});
    });
  });

  group('Kitchen view & shopping groups', () {
    final items = [ing('Spinach', days: -1), ing('Tomato', days: 1), ing('Rice', days: 100, cat: 'grains'), ing('Salt', cat: 'spices')];

    test('filters by freshness and search, sorts by expiry', () {
      expect(applyKitchenView(items, filter: KitchenFilter.expired).single.name, 'Spinach');
      expect(applyKitchenView(items, filter: KitchenFilter.expiring).single.name, 'Tomato');
      expect(applyKitchenView(items, query: 'ri').single.name, 'Rice');
      expect(applyKitchenView(items).map((e) => e.name).first, 'Spinach');
      expect(applyKitchenView(items, category: 'grains').single.name, 'Rice');
      expect(applyKitchenView(items, sort: KitchenSort.name).map((e) => e.name).toList(), ['Rice', 'Salt', 'Spinach', 'Tomato']);
    });

    test('groups shopping items into store sections', () {
      final g = groupShopping(const [
        ShoppingItem(id: '1', name: 'Paneer', category: 'dairy'),
        ShoppingItem(id: '2', name: 'Chips', category: 'snacks'),
        ShoppingItem(id: '3', name: 'Tomato', category: 'vegetables'),
      ]);
      expect(g.keys.toList(), ['vegetables', 'dairy', 'other']);
      expect(g['other']!.single.name, 'Chips');
    });
  });
}
