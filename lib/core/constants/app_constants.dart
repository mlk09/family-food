import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class IngredientCategory {
  const IngredientCategory(this.id, this.label, this.emoji, this.color);
  final String id;
  final String label;
  final String emoji;
  final Color color;
}

class AppConstants {
  AppConstants._();

  static const appName = 'Family Food Assistant';
  static const shortName = 'FamilyFood';

  static const categories = <IngredientCategory>[
    IngredientCategory('vegetables', 'Vegetables', '🥕', AppColors.herb),
    IngredientCategory('fruits', 'Fruits', '🍎', AppColors.tomato),
    IngredientCategory('dairy', 'Dairy', '🥛', AppColors.sky),
    IngredientCategory('meat', 'Meat', '🍗', AppColors.chili),
    IngredientCategory('eggs', 'Eggs', '🥚', AppColors.turmeric),
    IngredientCategory('grains', 'Grains', '🌾', Color(0xFFD9A066)),
    IngredientCategory('spices', 'Spices', '🌶️', AppColors.saffron),
    IngredientCategory('snacks', 'Snacks', '🍪', AppColors.berry),
    IngredientCategory('frozen', 'Frozen', '🧊', AppColors.mint),
    IngredientCategory('other', 'Other', '🧺', AppColors.darkMuted),
  ];

  static IngredientCategory category(String? id) =>
      categories.firstWhere((c) => c.id == id, orElse: () => categories.last);

  /// Shopping list groups (spec: Vegetables, Dairy, Meat, Grains, Spices, Other).
  static const shoppingGroups = ['vegetables', 'fruits', 'dairy', 'meat', 'eggs', 'grains', 'spices', 'other'];

  static const units = ['pieces', 'kg', 'g', 'litre', 'ml', 'packet', 'bottle', 'cup', 'spoon'];

  static const diets = ['vegetarian', 'vegan', 'eggetarian', 'non-vegetarian', 'jain', 'other'];
  static const dietLabels = {
    'vegetarian': 'Vegetarian',
    'vegan': 'Vegan',
    'eggetarian': 'Eggetarian',
    'non-vegetarian': 'Non-vegetarian',
    'jain': 'Jain',
    'other': 'Other',
  };

  static const ageGroups = ['child', 'teen', 'adult', 'senior'];
  static const ageGroupLabels = {
    'child': '🧒 Child (under 13)',
    'teen': '🧑 Teen',
    'adult': '🧑‍🍳 Adult',
    'senior': '👵 Senior',
  };

  static const spiceLevels = ['No spice', 'Mild', 'Medium', 'Spicy', 'Extra hot'];

  static const mealTypes = ['breakfast', 'lunch', 'dinner'];
  static const mealEmoji = {'breakfast': '🍳', 'lunch': '🥗', 'dinner': '🍛'};

  static const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static const memberRoles = {
    'dad': '👨 Dad',
    'mom': '👩 Mom',
    'child': '🧒 Child',
    'grandma': '👵 Grandma',
    'grandpa': '👴 Grandpa',
    'member': '🙂 Member',
  };

  static const allergyWarning =
      'AI-generated recipes can make mistakes. Always check every ingredient '
      'and label carefully for allergens before cooking or eating. This app '
      'does not give medical advice.';

  /// Staples assumed to be in most kitchens — never reported as "missing".
  static const pantryStaples = {
    'salt', 'water', 'oil', 'cooking oil', 'sugar', 'black pepper', 'pepper',
    'turmeric', 'red chilli powder', 'chilli powder', 'cumin', 'cumin seeds',
    'mustard seeds', 'garam masala', 'coriander powder', 'ice',
  };
}
