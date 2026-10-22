import 'json_utils.dart';

class MealPlanItem {
  const MealPlanItem({
    required this.id,
    required this.day,
    required this.mealType,
    required this.recipeName,
    this.emoji = '🍽️',
    this.description = '',
    this.ingredients = const [],
    this.recipeId,
  });

  final String id;

  /// 0 = Monday … 6 = Sunday.
  final int day;
  final String mealType;
  final String recipeName;
  final String emoji;
  final String description;
  final List<String> ingredients;

  /// Built-in library recipe id when the meal maps to one.
  final String? recipeId;

  factory MealPlanItem.fromJson(Map<String, dynamic> j) => MealPlanItem(
        id: jStr(j['id']),
        day: jInt(j['day'] ?? j['day_index']).clamp(0, 6),
        mealType: jStr(j['meal_type'], 'dinner').toLowerCase(),
        recipeName: jStr(j['recipe_name'] ?? j['name']),
        emoji: jStr(j['emoji'], '🍽️'),
        description: jStr(j['description']),
        ingredients: jStrList(j['ingredients']),
        recipeId: jStrOrNull(j['recipe_id']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'meal_type': mealType,
        'recipe_name': recipeName,
        'emoji': emoji,
        'description': description,
        'ingredients': ingredients,
        'recipe_id': recipeId,
      };
}

class MealPlan {
  const MealPlan({
    required this.id,
    required this.weekStart,
    this.userId,
    this.familyId,
    this.people = 4,
    this.budget,
    this.diet = 'vegetarian',
    this.mealsPerDay = const ['dinner'],
    this.items = const [],
    this.updatedAt,
  });

  final String id;
  final String? userId;
  final String? familyId;
  final DateTime weekStart;
  final int people;
  final int? budget;
  final String diet;
  final List<String> mealsPerDay;
  final List<MealPlanItem> items;
  final DateTime? updatedAt;

  List<MealPlanItem> itemsForDay(int day) {
    final list = items.where((i) => i.day == day).toList();
    const order = ['breakfast', 'lunch', 'dinner'];
    list.sort((a, b) => order.indexOf(a.mealType).compareTo(order.indexOf(b.mealType)));
    return list;
  }

  MealPlan copyWith({List<MealPlanItem>? items, String? userId, String? familyId}) => MealPlan(
        id: id,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        weekStart: weekStart,
        people: people,
        budget: budget,
        diet: diet,
        mealsPerDay: mealsPerDay,
        items: items ?? this.items,
        updatedAt: DateTime.now(),
      );

  factory MealPlan.fromJson(Map<String, dynamic> j) => MealPlan(
        id: jStr(j['id']),
        userId: jStrOrNull(j['user_id']),
        familyId: jStrOrNull(j['family_id']),
        weekStart: jDate(j['week_start']) ?? DateTime.now(),
        people: jInt(j['people'], 4),
        budget: j['budget'] == null ? null : jInt(j['budget']),
        diet: jStr(j['diet'], 'vegetarian'),
        mealsPerDay: jStrList(j['meals_per_day']).isEmpty ? const ['dinner'] : jStrList(j['meals_per_day']),
        items: jMapList(j['items'] ?? j['meal_plan_items']).map(MealPlanItem.fromJson).toList(),
        updatedAt: jDate(j['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'family_id': familyId,
        'week_start': dateOnly(weekStart),
        'people': people,
        'budget': budget,
        'diet': diet,
        'meals_per_day': mealsPerDay,
        'items': items.map((e) => e.toJson()).toList(),
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
}
