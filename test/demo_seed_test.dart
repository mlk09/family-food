import 'package:family_food_assistant/data/demo_data.dart';
import 'package:family_food_assistant/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('demo data seeds every collection', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance(), 'demo');
    await DemoData.seedIfNeeded(store);
    expect(store.readList('ingredients'), isNotEmpty);
    expect(store.readList('shopping'), isNotEmpty);
    expect(store.readMap('meal_plan'), isNotNull);
    expect(store.readMap('profile'), isNotNull);
    expect(store.readMap('family'), isNotNull);
    expect(store.readList('saved_recipes'), hasLength(2));
    expect(store.getBool('seeded'), isTrue);
  });
}
