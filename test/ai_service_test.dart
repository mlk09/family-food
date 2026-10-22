import 'dart:async';
import 'dart:convert';

import 'package:family_food_assistant/core/services/ai_service.dart';
import 'package:family_food_assistant/core/utils/app_error.dart';
import 'package:family_food_assistant/models/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> recipeJson(String name) => {
      'name': name,
      'description': 'Tasty',
      'emoji': '🍳',
      'prep_time': 5,
      'cook_time': 10,
      'servings': 2,
      'difficulty': 'Easy',
      'ingredients': [
        {'name': 'egg', 'quantity': '2'},
        {'name': 'spring onion', 'quantity': '1'},
      ],
      'instructions': ['Beat eggs', 'Cook'],
      'missing_ingredients': ['spring onion'],
      'nutrition': {'calories': 200, 'protein': 12, 'carbs': 2, 'fat': 14},
      'substitutions': [],
      'tags': ['quick'],
      'safety_notes': [],
    };

http.Response ok(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

AIService serviceWith(MockClient client, {Duration? timeout}) =>
    AIService(httpClient: client, baseUrl: 'https://test.supabase.co', publicKey: 'anon', timeout: timeout);

const ctx = AIContext(ingredients: [Ingredient(id: '1', name: 'Eggs')]);

void main() {
  test('sends action + context to the Edge Function, never an OpenAI key', () async {
    late http.Request captured;
    final ai = serviceWith(MockClient((req) async {
      captured = req;
      return ok({'recipes': [recipeJson('Omelette')]});
    }));
    final recipes = await ai.generateRecipes(ctx, request: 'quick');
    expect(captured.url.toString(), 'https://test.supabase.co/functions/v1/chef-ai');
    expect(captured.headers['Authorization'], 'Bearer anon');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['action'], 'generate_recipes');
    expect((body['context'] as Map)['ingredients'], [
      {'name': 'Eggs', 'quantity': '1'},
    ]);
    expect(captured.body.toLowerCase(), isNot(contains('sk-')));
    expect(recipes.single.name, 'Omelette');
    // Availability is recomputed locally from the pantry, not trusted from AI.
    expect(recipes.single.ingredients.firstWhere((i) => i.name == 'egg').available, isTrue);
    expect(recipes.single.missingIngredients, ['spring onion']);
  });

  test('drops invalid recipes and keeps valid ones', () async {
    final ai = serviceWith(MockClient((_) async => ok({
          'recipes': [
            recipeJson('Good'),
            {'name': 'Broken'},
            'nonsense',
          ]
        })));
    final r = await ai.generateRecipes(ctx);
    expect(r.map((e) => e.name), ['Good']);
  });

  test('malformed JSON becomes a friendly AppFailure', () async {
    final ai = serviceWith(MockClient((_) async => http.Response('<html>oops</html>', 200)));
    expect(ai.generateRecipes(ctx), throwsA(isA<AppFailure>().having((e) => e.message, 'message', contains('confusing'))));
  });

  test('empty recipe list is reported, not shown blank', () async {
    final ai = serviceWith(MockClient((_) async => ok({'recipes': []})));
    expect(ai.generateRecipes(ctx), throwsA(isA<AppFailure>()));
  });

  test('server errors map to "Chef AI is taking a short break"', () async {
    final ai = serviceWith(MockClient((_) async => http.Response('{"error":"ai_unavailable"}', 502)));
    expect(ai.generateRecipes(ctx), throwsA(predicate((e) => e is AppFailure && e.message == AppFailure.aiBreak.message)));
  });

  test('rate limit has its own message', () async {
    final ai = serviceWith(MockClient((_) async => http.Response('{"error":"rate_limited"}', 429)));
    expect(ai.generateRecipes(ctx), throwsA(predicate((e) => e is AppFailure && e.message.contains('limit'))));
  });

  test('network failure → offline message', () async {
    final ai = serviceWith(MockClient((_) async => throw http.ClientException('Failed host lookup')));
    expect(ai.generateRecipes(ctx), throwsA(predicate((e) => e is AppFailure && e.kind == FailureKind.offline)));
  });

  test('timeout → friendly timeout', () async {
    final ai = serviceWith(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );
    expect(ai.generateRecipes(ctx), throwsA(predicate((e) => e is AppFailure && e.kind == FailureKind.timeout)));
  });

  test('not configured → unavailable', () {
    final ai = AIService(httpClient: MockClient((_) async => http.Response('', 200)));
    expect(ai.isAvailable, isFalse);
  });

  test('meal plan parsing accepts day names and numbers', () async {
    final ai = serviceWith(MockClient((_) async => ok({
          'days': [
            {
              'day': 0,
              'meals': [
                {'meal_type': 'dinner', 'recipe_name': 'Dal + Rice', 'emoji': '🍛', 'description': '', 'ingredients': ['dal']},
              ]
            },
            {
              'day': 'Tuesday',
              'meals': [
                {'meal_type': 'dinner', 'recipe_name': 'Aloo Paratha', 'emoji': '🥔', 'description': '', 'ingredients': []},
              ]
            },
            {'day': 9, 'meals': []},
            {
              'day': 2,
              'meals': [
                {'meal_type': 'dinner', 'recipe_name': '', 'emoji': '', 'description': '', 'ingredients': []},
              ]
            },
          ]
        })));
    final items = await ai.generateMealPlan(const MealPlanRequest(), ctx);
    expect(items.map((e) => (e.day, e.recipeName)), [(0, 'Dal + Rice'), (1, 'Aloo Paratha')]);
  });

  test('substitutions and scan parsing', () async {
    final ai = serviceWith(MockClient((req) async {
      final action = (jsonDecode(req.body) as Map)['action'];
      return ok(
        action == 'substitutions'
            ? {
                'substitutions': [
                  {'ingredient': 'onion', 'substitute': 'cabbage'},
                ]
              }
            : {
                'ingredients': [
                  {'name': 'tomato'},
                  {'name': ''},
                ]
              },
      );
    }));
    expect((await ai.suggestSubstitutions('onion', null, ctx)).single.substitute, 'cabbage');
    expect(await ai.scanIngredients(utf8.encode('fake-jpeg')), ['tomato']);
  });

  test('chat streams text chunks', () async {
    final ai = AIService(
      baseUrl: 'https://test.supabase.co',
      publicKey: 'anon',
      httpClient: MockClient.streaming((req, body) async {
        return http.StreamedResponse(Stream.fromIterable([utf8.encode('Try '), utf8.encode('spring onion!')]), 200);
      }),
    );
    final chunks = await ai.askChefAI([
      {'role': 'user', 'content': 'No onions?'},
    ], ctx).toList();
    expect(chunks.join(), 'Try spring onion!');
  });
}
