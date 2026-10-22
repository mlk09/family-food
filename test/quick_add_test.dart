import 'package:family_food_assistant/core/services/ai_service.dart';
import 'package:family_food_assistant/core/services/offline_chef.dart';
import 'package:family_food_assistant/core/utils/ingredient_matcher.dart';
import 'package:family_food_assistant/core/utils/quick_add_parser.dart';
import 'package:family_food_assistant/models/ingredient.dart';
import 'package:family_food_assistant/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuickAddParser', () {
    test('splits on commas, new lines and "aur"', () {
      expect(QuickAddParser.split('aloo, pyaz aur tamatar\nchawal'), ['aloo', 'pyaz', 'tamatar', 'chawal']);
    });

    test('reads quantities and units before or after the name', () {
      final items = QuickAddParser.parse('2 kg aloo, 6 ande, milk 1 litre, 500g paneer, 1 dozen banana, onion x3');
      final byName = {for (final i in items) i.name: i};
      expect(byName['Aloo']!.quantity, 2);
      expect(byName['Aloo']!.unit, 'kg');
      expect(byName['Ande']!.quantity, 6);
      expect(byName['Milk']!.unit, 'litre');
      expect(byName['Paneer']!.quantity, 500);
      expect(byName['Paneer']!.unit, 'g');
      expect(byName['Banana']!.quantity, 12);
      expect(byName['Onion']!.quantity, 3);
    });

    test('Hindi names get the right category and an expiry date', () {
      final aloo = QuickAddParser.parseOne('aloo')!;
      expect(aloo.category, 'vegetables');
      expect(aloo.expiryDate, isNotNull);
      expect(QuickAddParser.parseOne('chawal')!.category, 'grains');
      expect(QuickAddParser.parseOne('dahi')!.category, 'dairy');
    });

    test('ignores junk', () {
      expect(QuickAddParser.parse(' , ,, '), isEmpty);
      expect(QuickAddParser.parseOne('5'), isNull);
    });

    test('quick-added Hindi items unlock recipes', () {
      final pantry = QuickAddParser.parse('aloo, pyaz, tamatar, chawal, ande');
      final names = IngredientMatcher.match(pantry).map((m) => m.recipe.name);
      expect(names, contains('Aloo Tamatar'));
      expect(names, contains('Masala Egg Rice'));
    });
  });

  group('Offline Chef understands Hinglish', () {
    final ctx = AIContext(
      ingredients: [
        for (final n in ['Aloo', 'Pyaz', 'Tamatar', 'Chawal', 'Ande']) Ingredient(id: n, name: n),
      ],
      profile: const UserProfile(id: 'u', diet: 'eggetarian'),
    );

    test('substitutions', () {
      expect(OfflineChef.reply('Pyaz nahi hai, kya use karun?', ctx), contains('Spring onion'));
    });
    test('what to cook', () {
      expect(OfflineChef.reply('Mere paas jo hai usse kya banau?', ctx), contains('Masala Egg Rice'));
    });
    test('time, kids, spice, budget', () {
      expect(OfflineChef.reply('Sirf 20 minute hain, kya banau?', ctx), contains('20 minutes'));
      expect(OfflineChef.reply('Bachchon ke liye kya banau?', ctx), contains('Kid-friendly'));
      expect(OfflineChef.reply('Ise kam teekha kaise banau?', ctx), contains('less spicy'));
      expect(OfflineChef.reply('300 rupaye mein kya banau?', ctx), contains('₹300'));
    });
  });
}
