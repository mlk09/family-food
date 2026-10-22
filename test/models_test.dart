import 'package:family_food_assistant/core/utils/safety.dart';
import 'package:family_food_assistant/core/utils/validators.dart';
import 'package:family_food_assistant/models/ingredient.dart';
import 'package:family_food_assistant/models/meal_plan.dart';
import 'package:family_food_assistant/models/profile.dart';
import 'package:family_food_assistant/models/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 22, 10);

  group('Ingredient', () {
    Ingredient ing(int? days) => Ingredient(id: '1', name: 'Tomato', expiryDate: days == null ? null : DateTime(2026, 10, 22).add(Duration(days: days)));

    test('freshness bands', () {
      expect(ing(10).freshness(now), Freshness.fresh);
      expect(ing(2).freshness(now), Freshness.expiringSoon);
      expect(ing(0).freshness(now), Freshness.expiringSoon);
      expect(ing(-1).freshness(now), Freshness.expired);
      expect(ing(null).freshness(now), Freshness.unknown);
    });

    test('json round trip keeps dates as yyyy-mm-dd', () {
      final i = Ingredient(id: 'a', name: 'Rice', quantity: 2.5, unit: 'kg', category: 'grains', expiryDate: DateTime(2026, 12, 1));
      final j = i.toJson();
      expect(j['expiry_date'], '2026-12-01');
      final back = Ingredient.fromJson(j);
      expect(back.name, 'Rice');
      expect(back.quantity, 2.5);
      expect(back.quantityLabel, '2.5 kg');
    });

    test('fromJson tolerates bad types', () {
      final i = Ingredient.fromJson({'id': 5, 'name': 'Egg', 'quantity': '8', 'expiry_date': 'not a date'});
      expect(i.id, '5');
      expect(i.quantity, 8);
      expect(i.expiryDate, isNull);
    });
  });

  group('Recipe AI validation', () {
    final valid = {
      'recipe_name': 'Egg Fried Rice',
      'prep_time': '10 min',
      'cook_time': 15,
      'servings': 3,
      'difficulty': 'easy',
      'ingredients': [
        {'name': 'rice', 'quantity': '2 cups'},
        'egg',
      ],
      'instructions': ['Cook rice', {'text': 'Scramble eggs'}],
      'nutrition': {'calories': '420', 'protein_g': 14},
    };

    test('accepts loosely typed but complete recipe', () {
      final r = Recipe.tryParseAi(valid, 'fallback')!;
      expect(r.name, 'Egg Fried Rice');
      expect(r.id, 'fallback');
      expect(r.prepTime, 10);
      expect(r.difficulty, 'Easy');
      expect(r.ingredients.map((e) => e.name), ['rice', 'egg']);
      expect(r.instructions, ['Cook rice', 'Scramble eggs']);
      expect(r.nutrition!.calories, 420);
      expect(r.source, 'ai');
    });

    test('rejects malformed recipes', () {
      expect(Recipe.tryParseAi('just text', 'x'), isNull);
      expect(Recipe.tryParseAi({...valid, 'instructions': []}, 'x'), isNull);
      expect(Recipe.tryParseAi({...valid, 'ingredients': null}, 'x'), isNull);
      expect(Recipe.tryParseAi({...valid, 'recipe_name': ''}, 'x'), isNull);
      expect(Recipe.tryParseAi({...valid, 'recipe_name': 'x' * 200}, 'x'), isNull);
    });

    test('clamps absurd numbers', () {
      final r = Recipe.tryParseAi({...valid, 'servings': 9999, 'cook_time': -5}, 'x')!;
      expect(r.servings, 50);
      expect(r.cookTime, 0);
    });
  });

  group('Profile streak', () {
    test('increments on consecutive days and resets after a gap', () {
      var p = const UserProfile(id: 'u');
      p = p.recordCooked(DateTime(2026, 10, 20));
      expect(p.cookingStreak, 1);
      p = p.recordCooked(DateTime(2026, 10, 20, 20));
      expect(p.cookingStreak, 1, reason: 'same day does not double count');
      p = p.recordCooked(DateTime(2026, 10, 21));
      expect(p.cookingStreak, 2);
      expect(p.currentStreak(DateTime(2026, 10, 22)), 2);
      expect(p.currentStreak(DateTime(2026, 10, 24)), 0, reason: 'streak expires');
      p = p.recordCooked(DateTime(2026, 10, 25));
      expect(p.cookingStreak, 1);
    });
  });

  test('meal plan sorts meals within a day', () {
    final plan = MealPlan.fromJson({
      'id': 'p',
      'week_start': '2026-10-19',
      'items': [
        {'id': '1', 'day': 0, 'meal_type': 'dinner', 'recipe_name': 'Dal'},
        {'id': '2', 'day': 0, 'meal_type': 'breakfast', 'recipe_name': 'Poha'},
        {'id': '3', 'day_index': 1, 'meal_type': 'lunch', 'recipe_name': 'Rajma'},
      ],
    });
    expect(plan.itemsForDay(0).map((e) => e.recipeName), ['Poha', 'Dal']);
    expect(plan.itemsForDay(1).single.recipeName, 'Rajma');
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email(' mom@family.in '), isNull);
    });
    test('password', () {
      expect(Validators.password('123'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });
    test('quantity', () {
      expect(Validators.quantity('0'), isNotNull);
      expect(Validators.quantity('abc'), isNotNull);
      expect(Validators.quantity('2.5'), isNull);
    });
  });

  group('Safety', () {
    test('detects hazards in steps', () {
      expect(Safety.tipFor('Chop the onions finely'), contains('knife'));
      expect(Safety.tipFor('Heat oil and add mustard seeds'), contains('oil'));
      expect(Safety.tipFor('Pressure cook for 3 whistles'), contains('Pressure'));
      expect(Safety.tipFor('Serve with salad'), isNull);
    });
    test('extracts timers', () {
      expect(Safety.timerFor('Simmer for 10 minutes'), const Duration(minutes: 10));
      expect(Safety.timerFor('Cook 3–4 minutes'), const Duration(minutes: 4));
      expect(Safety.timerFor('Rest 30 seconds'), const Duration(seconds: 30));
      expect(Safety.timerFor('Stir well'), isNull);
    });
  });
}
