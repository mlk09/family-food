import 'dart:convert';

import 'package:family_food_assistant/core/services/notification_service.dart';
import 'package:family_food_assistant/core/utils/id.dart';
import 'package:family_food_assistant/data/local_store.dart';
import 'package:family_food_assistant/data/providers.dart';
import 'package:family_food_assistant/data/recipe_library.dart';
import 'package:family_food_assistant/data/session.dart';
import 'package:family_food_assistant/data/sync_engine.dart';
import 'package:family_food_assistant/features/ai/ai_providers.dart';
import 'package:family_food_assistant/features/meal_plan/meal_plan_controller.dart';
import 'package:family_food_assistant/core/services/ai_service.dart';
import 'package:family_food_assistant/models/ingredient.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<ProviderContainer> demoContainer({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(sp),
    // AI not configured in tests → exercises offline fallbacks.
    aiServiceProvider.overrideWithValue(AIService(httpClient: MockClient((_) async => http.Response('', 500)))),
  ]);
  await c.read(sessionProvider.notifier).enterDemo();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kitchen inventory CRUD (demo/offline)', () {
    test('add, edit, delete and persist across restarts', () async {
      final c = await demoContainer();
      final n = c.read(ingredientsProvider.notifier);
      final before = (await c.read(ingredientsProvider.future)).length;
      expect(before, greaterThan(5), reason: 'demo data loaded');

      final id = newId();
      await n.save(Ingredient(id: id, name: 'Capsicum', quantity: 2));
      var list = c.read(ingredientsProvider).value!;
      expect(list.length, before + 1);
      final added = list.firstWhere((i) => i.id == id);
      expect(added.userId, isNotNull, reason: 'owner stamped');

      await n.save(added.copyWith(quantity: 5, unit: 'pieces'));
      expect(c.read(ingredientsProvider).value!.firstWhere((i) => i.id == id).quantity, 5);

      // Simulate app restart: new container, same storage.
      final sp = c.read(sharedPrefsProvider);
      c.dispose();
      final c2 = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
      final reloaded = await c2.read(ingredientsProvider.future);
      expect(reloaded.firstWhere((i) => i.id == id).quantity, 5, reason: 'cached offline');

      await c2.read(ingredientsProvider.notifier).remove(reloaded.firstWhere((i) => i.id == id));
      expect(c2.read(ingredientsProvider).value!.any((i) => i.id == id), isFalse);
      c2.dispose();
    });

    test('addOrMerge combines same ingredient', () async {
      final c = await demoContainer();
      await c.read(ingredientsProvider.future);
      final n = c.read(ingredientsProvider.notifier);
      final potato = c.read(ingredientsProvider).value!.firstWhere((i) => i.name == 'Potato');
      await n.addOrMerge([Ingredient(id: newId(), name: 'potatoes', quantity: 3)]);
      expect(c.read(ingredientsProvider).value!.firstWhere((i) => i.id == potato.id).quantity, potato.quantity + 3);
      c.dispose();
    });
  });

  group('Shopping list', () {
    test('adds missing ingredients without duplicates and categorises', () async {
      final c = await demoContainer();
      await c.read(shoppingProvider.future);
      final n = c.read(shoppingProvider.notifier);
      final added = await n.addNames(['paneer', 'Capsicum', 'coriander leaves'], recipeName: 'Paneer Bhurji');
      expect(added, 1, reason: 'capsicum & coriander already listed in demo');
      final paneer = c.read(shoppingProvider).value!.firstWhere((i) => i.name == 'Paneer');
      expect(paneer.category, 'dairy');
      expect(paneer.recipeName, 'Paneer Bhurji');

      await n.toggle(paneer);
      expect(c.read(shoppingProvider).value!.firstWhere((i) => i.id == paneer.id).checked, isTrue);
      expect(c.read(shoppingProvider).value!.last.id, paneer.id, reason: 'checked items sink to bottom');

      final moved = await n.moveCheckedToKitchen();
      expect(moved, 1);
      expect(c.read(shoppingProvider).value!.any((i) => i.id == paneer.id), isFalse);
      final kitchenPaneer = c.read(ingredientsProvider).value!.where((i) => i.name.toLowerCase() == 'paneer');
      expect(kitchenPaneer, isNotEmpty, reason: 'bought item now in kitchen');
      c.dispose();
    });
  });

  group('Saved recipes', () {
    test('toggle saves and unsaves; library ids become UUIDs', () async {
      final c = await demoContainer();
      await c.read(savedRecipesProvider.future);
      final n = c.read(savedRecipesProvider.notifier);
      final r = RecipeLibrary.byId('dal-tadka')!;
      expect(n.isSaved(r), isFalse);
      expect(await n.toggle(r), isTrue);
      expect(n.isSaved(r), isTrue);
      final stored = c.read(savedRecipesProvider).value!.firstWhere((e) => e.name == r.name);
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(stored.id), isTrue);
      expect(recipeDbId('dal-tadka', 'a'), isNot(recipeDbId('dal-tadka', 'b')), reason: 'no cross-family collisions');
      expect(await n.toggle(r), isFalse);
      expect(n.isSaved(r), isFalse);
      c.dispose();
    });
  });

  group('Meal planner', () {
    test('generates an offline plan, saves it, and fills the shopping list', () async {
      final c = await demoContainer();
      await c.read(mealPlanProvider.future);
      await c.read(ingredientsProvider.future);
      await c.read(shoppingProvider.future);
      final planner = c.read(plannerProvider.notifier);
      await planner.generate(const MealPlanRequest(people: 3, diet: 'vegetarian', mealsPerDay: ['lunch', 'dinner']));
      final draft = c.read(plannerProvider).draft!;
      expect(draft.items.length, 14);
      expect(draft.people, 3);

      final item = draft.items.first;
      final alt = planner.alternativesFor(item).first;
      planner.swap(item, alt);
      expect(c.read(plannerProvider).draft!.items.any((i) => i.recipeName == alt.name), isTrue);

      await planner.save();
      expect(c.read(plannerProvider).draft, isNull);
      expect(c.read(mealPlanProvider).value!.items.length, 14);

      final before = c.read(shoppingProvider).value!.length;
      final added = await planner.addPlanToShopping();
      expect(c.read(shoppingProvider).value!.length, before + added);
      c.dispose();
    });
  });

  group('Suggestions (What Can I Cook?)', () {
    test('instant results arrive even when AI is unavailable', () async {
      final c = await demoContainer();
      await c.read(ingredientsProvider.future);
      await c.read(profileProvider.future);
      await c.read(suggestionsProvider.notifier).run();
      final s = c.read(suggestionsProvider);
      expect(s.instant, isNotEmpty);
      expect(s.aiLoading, isFalse);
      c.dispose();
    });
  });

  group('Chef AI chat', () {
    test('falls back to offline answer and persists history', () async {
      final c = await demoContainer();
      await c.read(ingredientsProvider.future);
      await c.read(chatProvider.notifier).send("I don't have onions. What can I use?");
      final msgs = c.read(chatProvider).messages;
      expect(msgs.length, 2);
      expect(msgs.last.content, contains('Spring onion'));
      expect(c.read(localStoreProvider).readList('chat').length, 2);
      c.dispose();
    });
  });

  group('SyncEngine', () {
    test('queues writes offline and flushes them in order when back online', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance(), 'u:test');
      var online = false;
      final calls = <String>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        httpClient: MockClient((req) async {
          if (!online) throw http.ClientException('offline');
          calls.add('${req.method} ${req.url.path}');
          return http.Response('[]', 201, headers: {'content-type': 'application/json'}, request: req);
        }),
      );
      final engine = SyncEngine(store, client);
      await engine.enqueue(OutboxOp('upsert', 'ingredients', {'id': '1', 'name': 'Tomato'}));
      await engine.enqueue(OutboxOp('delete', 'ingredients', {'id': '2'}));
      await engine.flush();
      expect(engine.pending, 2, reason: 'kept while offline');

      online = true;
      await engine.flush();
      expect(engine.pending, 0);
      expect(calls, ['POST /rest/v1/ingredients', 'DELETE /rest/v1/ingredients']);
    });

    test('drops a write rejected by the server so the queue never jams', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance(), 'u:test');
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        httpClient: MockClient((req) async => http.Response(
              jsonEncode({'code': '42501', 'message': 'new row violates row-level security policy'}),
              403,
              headers: {'content-type': 'application/json'},
              request: req,
            )),
      );
      final engine = SyncEngine(store, client);
      await engine.enqueue(OutboxOp('upsert', 'ingredients', {'id': '1'}));
      await engine.flush();
      expect(engine.pending, 0);
    });

    test('is a no-op in demo mode', () async {
      SharedPreferences.setMockInitialValues({});
      final engine = SyncEngine(LocalStore(await SharedPreferences.getInstance(), 'demo'), null);
      await engine.enqueue(OutboxOp('upsert', 'ingredients', {'id': '1'}));
      expect(engine.pending, 0);
    });
  });

  test('expiry reminders are friendly and only for soon-expiring items', () {
    final now = DateTime(2026, 10, 22, 8);
    final r = NotificationService.expiryReminders([
      Ingredient(id: '1', name: 'Tomatoes', expiryDate: DateTime(2026, 10, 24)),
      Ingredient(id: '2', name: 'Rice', expiryDate: DateTime(2027, 1, 1)),
      Ingredient(id: '3', name: 'Milk', expiryDate: DateTime(2026, 10, 21)),
      Ingredient(id: '4', name: 'Paneer', expiryDate: DateTime(2026, 10, 22)),
    ], now);
    expect(r.map((e) => e.title), ['🍅 Your tomatoes may expire soon', '⏰ Use your paneer today']);
    expect(r.first.when, DateTime(2026, 10, 23, 9));
    expect(r.last.when.isAfter(now), isTrue);
  });
}
