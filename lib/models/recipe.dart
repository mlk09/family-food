import 'json_utils.dart';

class RecipeIngredient {
  const RecipeIngredient({required this.name, this.quantity = '', this.available = false});
  final String name;
  final String quantity;
  final bool available;

  RecipeIngredient copyWith({bool? available}) =>
      RecipeIngredient(name: name, quantity: quantity, available: available ?? this.available);

  factory RecipeIngredient.fromJson(Object? j) {
    if (j is String) return RecipeIngredient(name: j);
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return RecipeIngredient(
      name: jStr(m['name'] ?? m['ingredient']),
      quantity: jStr(m['quantity'] ?? m['amount']),
      available: jBool(m['available']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity, 'available': available};
}

class Nutrition {
  const Nutrition({this.calories, this.protein, this.carbs, this.fat});
  final int? calories;
  final int? protein;
  final int? carbs;
  final int? fat;

  bool get isEmpty => calories == null && protein == null && carbs == null && fat == null;

  static Nutrition? fromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? v) => v == null ? null : jInt(v);
    final r = Nutrition(
      calories: n(j['calories']),
      protein: n(j['protein'] ?? j['protein_g']),
      carbs: n(j['carbs'] ?? j['carbs_g']),
      fat: n(j['fat'] ?? j['fat_g']),
    );
    return r.isEmpty ? null : r;
  }

  Map<String, dynamic> toJson() => {'calories': calories, 'protein': protein, 'carbs': carbs, 'fat': fat};
}

class Substitution {
  const Substitution({required this.ingredient, required this.substitute});
  final String ingredient;
  final String substitute;

  factory Substitution.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return Substitution(
      ingredient: jStr(m['ingredient'] ?? m['original']),
      substitute: jStr(m['substitute'] ?? m['replacement']),
    );
  }

  Map<String, dynamic> toJson() => {'ingredient': ingredient, 'substitute': substitute};
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    this.description = '',
    this.emoji = '🍽️',
    this.imageUrl,
    this.prepTime = 10,
    this.cookTime = 15,
    this.servings = 2,
    this.difficulty = 'Easy',
    this.rating,
    this.ingredients = const [],
    this.instructions = const [],
    this.missingIngredients = const [],
    this.nutrition,
    this.substitutions = const [],
    this.tags = const [],
    this.safetyNotes = const [],
    this.source = 'library',
  });

  final String id;
  final String name;
  final String description;
  final String emoji;
  final String? imageUrl;
  final int prepTime;
  final int cookTime;
  final int servings;
  final String difficulty;
  final double? rating;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final List<String> missingIngredients;
  final Nutrition? nutrition;
  final List<Substitution> substitutions;
  final List<String> tags;
  final List<String> safetyNotes;

  /// 'library' (built-in), 'ai', 'demo'.
  final String source;

  int get totalTime => prepTime + cookTime;
  bool get isAi => source == 'ai';

  Recipe copyWith({
    String? id,
    List<RecipeIngredient>? ingredients,
    List<String>? missingIngredients,
    String? source,
  }) =>
      Recipe(
        id: id ?? this.id,
        name: name,
        description: description,
        emoji: emoji,
        imageUrl: imageUrl,
        prepTime: prepTime,
        cookTime: cookTime,
        servings: servings,
        difficulty: difficulty,
        rating: rating,
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions,
        missingIngredients: missingIngredients ?? this.missingIngredients,
        nutrition: nutrition,
        substitutions: substitutions,
        tags: tags,
        safetyNotes: safetyNotes,
        source: source ?? this.source,
      );

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final diff = jStr(j['difficulty'], 'Easy');
    return Recipe(
      id: jStr(j['id']),
      name: jStr(j['name'] ?? j['recipe_name']),
      description: jStr(j['description']),
      emoji: jStr(j['emoji'], '🍽️'),
      imageUrl: jStrOrNull(j['image_url']),
      prepTime: jInt(j['prep_time'], 10).clamp(0, 600),
      cookTime: jInt(j['cook_time'], 15).clamp(0, 1440),
      servings: jInt(j['servings'], 2).clamp(1, 50),
      difficulty: ['Easy', 'Medium', 'Hard'].firstWhere(
        (d) => d.toLowerCase() == diff.toLowerCase(),
        orElse: () => 'Easy',
      ),
      rating: j['rating'] == null ? null : jDouble(j['rating']).clamp(0, 5).toDouble(),
      ingredients: (j['ingredients'] is List ? j['ingredients'] as List : const [])
          .map(RecipeIngredient.fromJson)
          .where((i) => i.name.isNotEmpty)
          .toList(),
      instructions: jStrList(j['instructions'] ?? j['steps']),
      missingIngredients: jStrList(j['missing_ingredients']),
      nutrition: Nutrition.fromJson(j['nutrition']),
      substitutions: (j['substitutions'] is List ? j['substitutions'] as List : const [])
          .map(Substitution.fromJson)
          .where((s) => s.ingredient.isNotEmpty && s.substitute.isNotEmpty)
          .toList(),
      tags: jStrList(j['tags']),
      safetyNotes: jStrList(j['safety_notes']),
      source: jStr(j['source'], 'library'),
    );
  }

  /// Validates an AI-produced recipe. Returns null when it is unusable so the
  /// UI never renders half-broken data.
  static Recipe? tryParseAi(Object? raw, String fallbackId) {
    if (raw is! Map) return null;
    try {
      final r = Recipe.fromJson({...Map<String, dynamic>.from(raw), 'source': 'ai'});
      if (r.name.length < 2 || r.name.length > 80) return null;
      if (r.ingredients.isEmpty || r.instructions.isEmpty) return null;
      return r.id.isEmpty ? r.copyWith(id: fallbackId) : r;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'emoji': emoji,
        'image_url': imageUrl,
        'prep_time': prepTime,
        'cook_time': cookTime,
        'servings': servings,
        'difficulty': difficulty,
        'rating': rating,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'instructions': instructions,
        'missing_ingredients': missingIngredients,
        'nutrition': nutrition?.toJson(),
        'substitutions': substitutions.map((e) => e.toJson()).toList(),
        'tags': tags,
        'safety_notes': safetyNotes,
        'source': source,
      };
}
