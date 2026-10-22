import '../constants/app_constants.dart';
import 'ingredient_matcher.dart';

const _emoji = {
  'potato': '🥔', 'tomato': '🍅', 'onion': '🧅', 'egg': '🥚', 'rice': '🍚', 'garlic': '🧄',
  'carrot': '🥕', 'spinach': '🥬', 'cabbage': '🥬', 'capsicum': '🫑', 'green chilli': '🌶️', 'cucumber': '🥒',
  'milk': '🥛', 'curd': '🥛', 'paneer': '🧀', 'cheese': '🧀', 'butter': '🧈', 'ghee': '🧈',
  'chicken': '🍗', 'mutton': '🥩', 'fish': '🐟', 'prawn': '🦐',
  'banana': '🍌', 'apple': '🍎', 'orange': '🍊', 'lemon': '🍋', 'mango': '🥭', 'grapes': '🍇', 'watermelon': '🍉',
  'bread': '🍞', 'wheat flour': '🌾', 'pasta': '🍝', 'oats': '🥣', 'poha': '🍚', 'semolina': '🌾',
  'toor dal': '🫘', 'moong dal': '🫘', 'rajma': '🫘', 'chickpeas': '🫘', 'peas': '🫛', 'beans': '🫛',
  'corn': '🌽', 'mushroom': '🍄', 'broccoli': '🥦', 'cauliflower': '🥦', 'okra': '🌿', 'coriander leaves': '🌿',
  'ginger': '🫚', 'peanuts': '🥜', 'cashews': '🥜', 'honey': '🍯', 'salt': '🧂', 'sugar': '🍬',
  'garam masala': '🌶️', 'turmeric': '🟡', 'oil': '🫒', 'coconut': '🥥', 'avocado': '🥑', 'ice cream': '🍨',
};

String foodEmoji(String name, [String? category]) =>
    _emoji[IngredientNames.normalize(name)] ?? AppConstants.category(category).emoji;
