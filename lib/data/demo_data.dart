import '../core/utils/id.dart';
import '../models/ingredient.dart';
import '../models/meal_plan.dart';
import '../models/profile.dart';
import '../models/shopping_item.dart';
import 'local_store.dart';
import 'recipe_library.dart';

/// Sample data for Demo Mode. Everything is stored only on this device and is
/// clearly labelled "Demo" in the UI.
class DemoData {
  DemoData._();

  static const demoUserId = '00000000-0000-4000-8000-000000000001';
  static const demoFamilyId = '00000000-0000-4000-8000-0000000000f1';

  static Future<void> seedIfNeeded(LocalStore store) async {
    if (store.getBool('seeded')) return;
    final now = DateTime.now();
    DateTime inDays(int d) => DateTime(now.year, now.month, now.day).add(Duration(days: d));

    Ingredient ing(String name, double q, String unit, String cat, int? expiresIn) => Ingredient(
          id: newId(),
          userId: demoUserId,
          familyId: demoFamilyId,
          name: name,
          quantity: q,
          unit: unit,
          category: cat,
          purchaseDate: inDays(-2),
          expiryDate: expiresIn == null ? null : inDays(expiresIn),
          notes: 'Demo data',
        );

    final ingredients = [
      ing('Potato', 5, 'pieces', 'vegetables', 12),
      ing('Tomato', 4, 'pieces', 'vegetables', 2),
      ing('Onion', 3, 'pieces', 'vegetables', 20),
      ing('Eggs', 8, 'pieces', 'eggs', 9),
      ing('Rice', 2, 'kg', 'grains', 180),
      ing('Paneer', 200, 'g', 'dairy', 1),
      ing('Milk', 1, 'litre', 'dairy', 3),
      ing('Spinach', 1, 'packet', 'vegetables', -1),
      ing('Green chilli', 6, 'pieces', 'vegetables', 6),
      ing('Garlic', 1, 'pieces', 'vegetables', 25),
      ing('Toor dal', 1, 'kg', 'grains', 200),
      ing('Banana', 4, 'pieces', 'fruits', 3),
      ing('Garam masala', 1, 'packet', 'spices', null),
    ];
    await store.writeList('ingredients', ingredients.map((e) => e.toJson()).toList());

    ShoppingItem item(String n, String q, String cat, int pr) => ShoppingItem(
          id: newId(), userId: demoUserId, familyId: demoFamilyId, name: n, quantity: q, category: cat, priority: pr);
    await store.writeList('shopping', [
      item('Capsicum', '2', 'vegetables', 1),
      item('Coriander leaves', '1 bunch', 'vegetables', 2),
      item('Curd', '500 g', 'dairy', 1),
      item('Wheat flour', '5 kg', 'grains', 0),
    ].map((e) => e.toJson()).toList());

    final picks = [
      ('dal-tadka', 'dinner'), ('aloo-paratha', 'dinner'), ('veg-pasta', 'dinner'),
      ('egg-curry', 'dinner'), ('veg-pulao', 'dinner'), ('rajma-chawal', 'dinner'), ('khichdi', 'dinner'),
    ];
    final items = <MealPlanItem>[];
    for (var d = 0; d < 7; d++) {
      final r = RecipeLibrary.byId(picks[d].$1)!;
      items.add(MealPlanItem(
        id: newId(),
        day: d,
        mealType: picks[d].$2,
        recipeName: r.name,
        emoji: r.emoji,
        description: r.description,
        ingredients: r.ingredients.map((i) => i.name).toList(),
        recipeId: r.id,
      ));
    }
    items.add(MealPlanItem(
      id: newId(), day: (now.weekday - 1), mealType: 'breakfast', recipeName: 'Kanda Poha', emoji: '🍋',
      description: 'Light flattened-rice breakfast.', ingredients: const ['poha', 'onion', 'peanuts'], recipeId: 'poha'));
    await store.writeMap(
      'meal_plan',
      MealPlan(
        id: newId(),
        userId: demoUserId,
        familyId: demoFamilyId,
        weekStart: weekStartOf(now),
        people: 4,
        budget: 2500,
        diet: 'eggetarian',
        mealsPerDay: const ['breakfast', 'dinner'],
        items: items,
      ).toJson(),
    );

    await store.writeMap(
      'profile',
      UserProfile(
        id: demoUserId,
        name: 'Demo Chef',
        ageGroup: 'adult',
        diet: 'eggetarian',
        foodPreferences: const ['North Indian', 'Quick meals'],
        allergies: const [],
        favoriteFoods: const ['Paneer', 'Dal'],
        dislikedFoods: const ['Bitter gourd'],
        spiceLevel: 2,
        familyId: demoFamilyId,
        cookingStreak: 5,
        lastCookedOn: inDays(-1),
      ).toJson(),
    );

    await store.writeMap(
      'family',
      const Family(
        id: demoFamilyId,
        name: 'Sharma Family (Demo)',
        inviteCode: 'DEMO42',
        members: [
          FamilyMember(userId: demoUserId, displayName: 'Demo Chef (you)', role: 'dad', isAdmin: true),
          FamilyMember(userId: 'demo-mom', displayName: 'Priya', role: 'mom'),
          FamilyMember(userId: 'demo-kid', displayName: 'Aarav', role: 'child'),
          FamilyMember(userId: 'demo-gma', displayName: 'Dadi', role: 'grandma'),
        ],
      ).toJson(),
    );

    await store.writeList('saved_recipes', [
      RecipeLibrary.byId('egg-fried-rice')!.copyWith(source: 'demo').toJson(),
      RecipeLibrary.byId('palak-paneer')!.copyWith(source: 'demo').toJson(),
    ]);
    await store.setBool('seeded', true);
  }
}
