import '../../models/ingredient.dart';
import 'id.dart';
import 'ingredient_matcher.dart';

/// Turns one line like "2 kg aloo, pyaz aur 6 ande, milk 1 litre" into
/// ingredients, so a whole kitchen can be added in a single step.
class QuickAddParser {
  QuickAddParser._();

  static const _units = {
    'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilogram': 'kg',
    'g': 'g', 'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g',
    'l': 'litre', 'ltr': 'litre', 'litre': 'litre', 'liter': 'litre', 'litres': 'litre', 'liters': 'litre',
    'ml': 'ml',
    'packet': 'packet', 'packets': 'packet', 'pkt': 'packet', 'pack': 'packet',
    'bottle': 'bottle', 'bottles': 'bottle',
    'cup': 'cup', 'cups': 'cup',
    'pc': 'pieces', 'pcs': 'pieces', 'piece': 'pieces', 'pieces': 'pieces',
    'dozen': 'dozen', 'darjan': 'dozen',
  };

  /// Splits on commas, new lines, "aur", "and", "&", "+".
  static List<String> split(String text) => text
      .split(RegExp(r'[,\n;]|\s+(?:aur|and|&|\+)\s+', caseSensitive: false))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static Ingredient? parseOne(String raw) {
    var words = raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    double? qty;
    String? unit;

    double? numOf(String w) => double.tryParse(w.replaceAll(',', '.'));
    // "2kg" → "2", "kg"
    final glued = RegExp(r'^(\d+(?:[.,]\d+)?)([a-zA-Z]+)$');
    words = [
      for (final w in words)
        if (glued.firstMatch(w) case final m?) ...[m.group(1)!, m.group(2)!] else w,
    ];

    // Leading "2 kg" / "6" or trailing "1 litre" / "x6".
    if (words.isNotEmpty && numOf(words.first) != null) {
      qty = numOf(words.removeAt(0));
      if (words.isNotEmpty && _units.containsKey(words.first.toLowerCase())) unit = _units[words.removeAt(0).toLowerCase()];
    } else if (words.length >= 2 && _units.containsKey(words.last.toLowerCase()) && numOf(words[words.length - 2]) != null) {
      unit = _units[words.removeLast().toLowerCase()];
      qty = numOf(words.removeLast());
    } else if (words.length >= 2 && numOf(words.last.replaceFirst(RegExp('^x'), '')) != null) {
      qty = numOf(words.removeLast().replaceFirst(RegExp('^x'), ''));
    }

    final name = words.join(' ').replaceAll(RegExp(r'[^\p{L}\p{N}\s\x27-]', unicode: true), '').trim();
    if (name.isEmpty || name.length > 40) return null;
    if (unit == 'dozen') {
      qty = (qty ?? 1) * 12;
      unit = 'pieces';
    }
    final now = DateTime.now();
    final category = IngredientMatcher.categoryFor(name);
    return Ingredient(
      id: newId(),
      name: name[0].toUpperCase() + name.substring(1),
      quantity: (qty == null || qty <= 0) ? 1 : qty,
      unit: unit ?? 'pieces',
      category: category,
      purchaseDate: now,
      expiryDate: _defaultExpiry(category, now),
    );
  }

  static List<Ingredient> parse(String text) => split(text).map(parseOne).whereType<Ingredient>().toList();

  /// Sensible default shelf life so "use soon" reminders work without typing dates.
  static DateTime? _defaultExpiry(String category, DateTime now) {
    final days = switch (category) {
      'vegetables' => 7,
      'fruits' => 6,
      'dairy' => 4,
      'meat' => 2,
      'eggs' => 14,
      'grains' => 180,
      'spices' => 365,
      _ => null,
    };
    return days == null ? null : DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }
}
