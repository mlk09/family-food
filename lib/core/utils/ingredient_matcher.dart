import '../../data/recipe_library.dart';
import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../constants/app_constants.dart';

/// Normalises ingredient names so "Tomatoes", "tamatar" and "tomato" match.
class IngredientNames {
  IngredientNames._();

  static const _synonyms = {
    'aloo': 'potato', 'alu': 'potato', 'potatoes': 'potato',
    'tamatar': 'tomato', 'tomatoes': 'tomato',
    'pyaz': 'onion', 'pyaaz': 'onion', 'kanda': 'onion', 'onions': 'onion',
    'chawal': 'rice', 'basmati': 'rice', 'basmati rice': 'rice', 'cooked rice': 'rice',
    'eggs': 'egg', 'anda': 'egg', 'ande': 'egg',
    'dahi': 'curd', 'yogurt': 'curd', 'yoghurt': 'curd',
    'atta': 'wheat flour', 'flour': 'wheat flour',
    'sooji': 'semolina', 'rava': 'semolina', 'suji': 'semolina',
    'palak': 'spinach', 'bhindi': 'okra', 'ladyfinger': 'okra', "lady's finger": 'okra',
    'gobi': 'cauliflower', 'matar': 'peas', 'green peas': 'peas',
    'shimla mirch': 'capsicum', 'bell pepper': 'capsicum',
    'dhania': 'coriander leaves', 'coriander': 'coriander leaves', 'cilantro': 'coriander leaves',
    'adrak': 'ginger', 'lehsun': 'garlic', 'lahsun': 'garlic',
    'hari mirch': 'green chilli', 'green chillies': 'green chilli', 'chilli': 'green chilli',
    'chole': 'chickpeas', 'kabuli chana': 'chickpeas', 'chana': 'chickpeas',
    'kidney beans': 'rajma', 'toor': 'toor dal', 'arhar dal': 'toor dal',
    'moong': 'moong dal', 'chicken breast': 'chicken', 'murgi': 'chicken',
    'bananas': 'banana', 'kela': 'banana', 'apples': 'apple', 'carrots': 'carrot', 'gajar': 'carrot',
    'nimbu': 'lemon', 'lime': 'lemon', 'doodh': 'milk', 'makhan': 'butter',
    'cottage cheese': 'paneer', 'noodles': 'pasta', 'spaghetti': 'pasta', 'macaroni': 'pasta',
    'scallion': 'spring onion', 'green onion': 'spring onion',
    'groundnuts': 'peanuts', 'moongphali': 'peanuts', 'flattened rice': 'poha',
    'cucumbers': 'cucumber', 'kheera': 'cucumber',
    'baingan': 'brinjal', 'eggplant': 'brinjal', 'mirchi': 'green chilli', 'aata': 'wheat flour',
    'dal': 'toor dal', 'daal': 'toor dal', 'moong daal': 'moong dal', 'rajmah': 'rajma',
    'chana dal': 'chana dal', 'pudina': 'mint', 'lauki': 'bottle gourd', 'mooli': 'radish',
    'patta gobhi': 'cabbage', 'band gobhi': 'cabbage', 'phool gobhi': 'cauliflower', 'gobhi': 'cauliflower',
    'murga': 'chicken', 'macchi': 'fish', 'machli': 'fish', 'cheeni': 'sugar', 'namak': 'salt',
  };

  static String normalize(String raw) {
    var s = raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z\s\x27]'), '').replaceAll(RegExp(r'\s+'), ' ');
    if (_synonyms.containsKey(s)) return _synonyms[s]!;
    if (s.endsWith('es') && _synonyms.containsKey(s.substring(0, s.length - 2))) {
      return _synonyms[s.substring(0, s.length - 2)]!;
    }
    if (s.endsWith('s') && s.length > 3) {
      final single = s.substring(0, s.length - 1);
      return _synonyms[single] ?? single;
    }
    return s;
  }

  static bool isStaple(String name) => AppConstants.pantryStaples.contains(normalize(name));

  /// Preparation words that don't change what the ingredient is.
  static const _modifiers = {
    'cooked', 'boiled', 'fresh', 'chopped', 'raw', 'ripe', 'dried', 'dry', 'frozen', 'leftover',
    'large', 'small', 'medium', 'whole', 'soaked', 'grated', 'sliced', 'diced', 'big', 'organic',
  };

  static String _core(String n) => n.split(' ').where((w) => !_modifiers.contains(w)).join(' ');

  /// True when [have] satisfies [need]: "cooked rice" ≈ "rice", but
  /// "onion" ≠ "spring onion".
  static bool matches(String have, String need) {
    final a = normalize(have), b = normalize(need);
    if (a == b) return true;
    final ca = _core(a), cb = _core(b);
    return ca.isNotEmpty && (ca == cb || normalize(ca) == normalize(cb));
  }
}

class RecipeMatch {
  const RecipeMatch(this.recipe, this.score, this.used, this.missing);
  final Recipe recipe;
  final double score;
  final List<String> used;
  final List<String> missing;
}

class MatchFilters {
  const MatchFilters({this.diet, this.maxMinutes, this.kidsOnly = false, this.allergies = const [], this.mealType});
  final String? diet;
  final int? maxMinutes;
  final bool kidsOnly;
  final List<String> allergies;
  final String? mealType;
}

/// Local, instant recipe matcher. Ranks library recipes by how much of the
/// recipe the family already has, ignoring pantry staples.
class IngredientMatcher {
  IngredientMatcher._();

  static const _nonVeg = {'chicken', 'mutton', 'fish', 'prawn', 'meat'};
  static const _eggs = {'egg'};
  static const _dairy = {'milk', 'curd', 'paneer', 'cheese', 'butter', 'ghee', 'cream'};
  static const _jainAvoid = {'onion', 'garlic', 'potato', 'carrot', 'ginger', 'spring onion'};

  static bool dietAllows(Recipe r, String? diet) {
    final names = r.ingredients.map((i) => IngredientNames.normalize(i.name)).toSet();
    switch (diet) {
      case 'vegetarian':
        return names.intersection({..._nonVeg, ..._eggs}).isEmpty;
      case 'eggetarian':
        return names.intersection(_nonVeg).isEmpty;
      case 'vegan':
        return names.intersection({..._nonVeg, ..._eggs, ..._dairy, 'honey'}).isEmpty;
      case 'jain':
        return names.intersection({..._nonVeg, ..._eggs, ..._jainAvoid}).isEmpty;
      default:
        return true;
    }
  }

  static bool containsAllergen(Recipe r, List<String> allergies) {
    if (allergies.isEmpty) return false;
    final names = r.ingredients.map((i) => i.name.toLowerCase()).join(' ');
    for (final a in allergies) {
      final k = a.toLowerCase().trim();
      if (k.isEmpty) continue;
      if (names.contains(k)) return true;
      if ((k.contains('nut') || k.contains('peanut')) && RegExp(r'peanut|cashew|almond|walnut').hasMatch(names)) return true;
      if ((k.contains('dairy') || k.contains('lactose') || k.contains('milk')) &&
          RegExp(r'milk|curd|paneer|cheese|butter|ghee|cream').hasMatch(names)) {
        return true;
      }
      if (k.contains('gluten') && RegExp(r'wheat|bread|pasta|semolina|oats').hasMatch(names)) return true;
      if (k.contains('egg') && names.contains('egg')) return true;
    }
    return false;
  }

  static List<RecipeMatch> match(
    List<Ingredient> pantry, {
    MatchFilters filters = const MatchFilters(),
    List<Recipe>? library,
    int limit = 12,
  }) {
    final have = pantry.where((i) => i.freshness() != Freshness.expired).map((i) => i.name).toList();
    final results = <RecipeMatch>[];

    for (final r in library ?? RecipeLibrary.all) {
      if (!dietAllows(r, filters.diet)) continue;
      if (containsAllergen(r, filters.allergies)) continue;
      if (filters.maxMinutes != null && r.totalTime > filters.maxMinutes!) continue;
      if (filters.kidsOnly && !r.tags.contains('kids')) continue;
      if (filters.mealType != null && !r.tags.contains(filters.mealType)) continue;

      final core = r.ingredients.where((i) => !IngredientNames.isStaple(i.name)).toList();
      if (core.isEmpty) continue;
      final used = <String>[], missing = <String>[];
      for (final ing in core) {
        (have.any((h) => IngredientNames.matches(h, ing.name)) ? used : missing).add(ing.name);
      }
      if (used.isEmpty) continue;
      // Favour high coverage, then absolute number of pantry items used.
      final score = used.length / core.length + used.length * 0.03;
      results.add(RecipeMatch(r, score, used, missing));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Marks each recipe ingredient as available/missing for the given pantry.
  static Recipe annotate(Recipe r, List<Ingredient> pantry) {
    final have = pantry.where((i) => i.freshness() != Freshness.expired).map((i) => i.name).toList();
    final ings = r.ingredients
        .map((i) => i.copyWith(available: IngredientNames.isStaple(i.name) || have.any((h) => IngredientNames.matches(h, i.name))))
        .toList();
    final missing = ings.where((i) => !i.available).map((i) => i.name).toList();
    return r.copyWith(ingredients: ings, missingIngredients: missing);
  }

  /// Best-guess shopping category for an ingredient name.
  static String categoryFor(String name) {
    final n = IngredientNames.normalize(name);
    const map = {
      'vegetables': ['potato', 'tomato', 'onion', 'carrot', 'peas', 'beans', 'spinach', 'okra', 'cauliflower', 'capsicum', 'cucumber', 'garlic', 'ginger', 'green chilli', 'coriander leaves', 'curry leaves', 'spring onion', 'cabbage', 'mushroom', 'brinjal', 'lemon'],
      'fruits': ['banana', 'apple', 'orange', 'pomegranate', 'mango', 'grapes', 'papaya', 'watermelon'],
      'dairy': ['milk', 'curd', 'paneer', 'cheese', 'butter', 'ghee', 'cream'],
      'meat': ['chicken', 'mutton', 'fish', 'prawn'],
      'eggs': ['egg'],
      'grains': ['rice', 'wheat flour', 'semolina', 'poha', 'oats', 'pasta', 'bread', 'toor dal', 'moong dal', 'rajma', 'chickpeas', 'masoor dal'],
      'spices': ['cumin seeds', 'turmeric', 'garam masala', 'red chilli powder', 'mustard seeds', 'coriander powder', 'bay leaf', 'cardamom', 'oregano', 'black pepper', 'chaat masala', 'amchur', 'chana masala', 'salt', 'sugar'],
      'snacks': ['peanuts', 'cashews', 'biscuits', 'chips'],
    };
    for (final e in map.entries) {
      if (e.value.contains(n)) return e.key;
    }
    return 'other';
  }
}
