import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/ingredient.dart';
import '../../models/meal_plan.dart';
import '../../models/profile.dart';
import '../../models/recipe.dart';
import '../config/env.dart';
import '../utils/app_error.dart';
import '../utils/id.dart';
import '../utils/ingredient_matcher.dart';

/// Everything Chef AI should know about the family. Sent with each request so
/// the Edge Function needs no extra database round-trips (lower latency).
class AIContext {
  const AIContext({
    this.ingredients = const [],
    this.profile,
    this.savedRecipeNames = const [],
    this.mealPlanSummary = const [],
    this.familySize,
  });

  final List<Ingredient> ingredients;
  final UserProfile? profile;
  final List<String> savedRecipeNames;
  final List<String> mealPlanSummary;
  final int? familySize;

  Map<String, dynamic> toJson() => {
        'ingredients': [
          for (final i in ingredients.where((i) => i.freshness() != Freshness.expired).take(60))
            {
              'name': i.name,
              'quantity': i.quantityLabel,
              if (i.daysLeft() != null) 'days_left': i.daysLeft(),
            }
        ],
        if (profile != null)
          'profile': {
            'age_group': profile!.ageGroup,
            'diet': profile!.diet,
            'allergies': profile!.allergies,
            'preferences': profile!.foodPreferences,
            'favorites': profile!.favoriteFoods,
            'dislikes': profile!.dislikedFoods,
            'spice_level': profile!.spiceLevel,
          },
        'saved_recipes': savedRecipeNames.take(20).toList(),
        'meal_plan': mealPlanSummary.take(21).toList(),
        if (familySize != null) 'family_size': familySize,
      };
}

class MealPlanRequest {
  const MealPlanRequest({
    this.people = 4,
    this.budget,
    this.diet = 'vegetarian',
    this.preferences = '',
    this.useKitchen = true,
    this.mealsPerDay = const ['dinner'],
    this.days = 7,
  });

  final int people;
  final int? budget;
  final String diet;
  final String preferences;
  final bool useKitchen;
  final List<String> mealsPerDay;
  final int days;

  Map<String, dynamic> toJson() => {
        'people': people,
        'budget': budget,
        'diet': diet,
        'preferences': preferences,
        'use_kitchen': useKitchen,
        'meals_per_day': mealsPerDay,
        'days': days,
      };
}

/// Secure AI client. Talks ONLY to the Supabase Edge Function — the OpenAI key
/// never ships in the app. Every response is validated before it reaches UI.
class AIService {
  AIService({SupabaseClient? client, http.Client? httpClient, String? baseUrl, String? publicKey, Duration? timeout})
      // ignore: prefer_initializing_formals
      : _client = client,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? (Env.isSupabaseConfigured ? Env.supabaseUrl : null),
        _publicKey = publicKey ?? Env.supabaseAnonKey,
        _timeout = timeout ?? const Duration(seconds: 45);

  final SupabaseClient? _client;
  final http.Client _http;
  final String? _baseUrl;
  final String _publicKey;
  final Duration _timeout;

  bool get isAvailable => _baseUrl != null;

  static const loginNeeded = AppFailure(
    FailureKind.auth,
    'Online Chef AI needs a free account — log in from Profile. (Demo Mode uses offline answers.)',
  );

  Uri get _endpoint => Uri.parse('$_baseUrl/functions/v1/${Env.aiFunctionName}');

  Map<String, String> get _headers {
    // Signed-in users send their JWT; demo users send the public anon key and
    // the function decides whether demo AI is allowed (ALLOW_DEMO_AI).
    final token = _client?.auth.currentSession?.accessToken ?? _publicKey;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'apikey': _publicKey,
    };
  }

  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> payload) async {
    if (!isAvailable) throw AppFailure.aiBreak;
    final http.Response res;
    try {
      res = await _http
          .post(_endpoint, headers: _headers, body: jsonEncode({'action': action, ...payload}))
          .timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, 'Chef AI is taking too long. Please try again.');
    } catch (e) {
      throw AppFailure(FailureKind.offline, AppFailure.offline.message, e);
    }
    if (res.statusCode == 429) {
      throw const AppFailure(FailureKind.ai, "You've reached today's Chef AI limit. Try again tomorrow!");
    }
    if (res.statusCode == 401) throw loginNeeded;
    if (res.statusCode != 200) {
      debugPrint('AI $action failed ${res.statusCode}: ${res.body}');
      throw AppFailure.aiBreak;
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const AppFailure(FailureKind.ai, 'Chef AI gave a confusing answer. Please try again.');
  }

  /// Recipes that prioritise the family's ingredients.
  Future<List<Recipe>> generateRecipes(AIContext ctx, {String? request, int count = 4}) async {
    final res = await _call('generate_recipes', {
      'context': ctx.toJson(),
      'request': request ?? '',
      'count': count,
    });
    final recipes = parseRecipes(res['recipes']);
    if (recipes.isEmpty) throw const AppFailure(FailureKind.ai, 'Chef AI could not think of recipes. Please try again.');
    return recipes.map((r) => IngredientMatcher.annotate(r, ctx.ingredients)).toList();
  }

  /// Full recipe for a dish name (used by meal-plan items).
  Future<Recipe> recipeDetail(String name, AIContext ctx) async {
    final res = await _call('recipe_detail', {'context': ctx.toJson(), 'name': name});
    final r = Recipe.tryParseAi(res['recipe'], newId());
    if (r == null) throw const AppFailure(FailureKind.ai, 'Chef AI gave a confusing answer. Please try again.');
    return IngredientMatcher.annotate(r, ctx.ingredients);
  }

  Future<List<MealPlanItem>> generateMealPlan(MealPlanRequest req, AIContext ctx) async {
    final res = await _call('meal_plan', {'context': ctx.toJson(), 'plan': req.toJson()});
    final items = parseMealPlan(res['days']);
    if (items.isEmpty) throw const AppFailure(FailureKind.ai, 'Chef AI could not build a plan. Please try again.');
    return items;
  }

  Future<List<Substitution>> suggestSubstitutions(String ingredient, String? recipeName, AIContext ctx) async {
    final res = await _call('substitutions', {
      'context': ctx.toJson(),
      'ingredient': ingredient,
      'recipe': recipeName ?? '',
    });
    return (res['substitutions'] is List ? res['substitutions'] as List : const [])
        .map(Substitution.fromJson)
        .where((s) => s.substitute.isNotEmpty)
        .toList();
  }

  /// Shopping list for a set of meals, minus what's already in the kitchen.
  Future<List<String>> generateShoppingList(List<String> meals, AIContext ctx) async {
    final res = await _call('shopping_list', {'context': ctx.toJson(), 'meals': meals});
    return (res['items'] is List ? res['items'] as List : const [])
        .map((e) => e is Map ? '${e['name'] ?? ''}'.trim() : '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Ingredient names recognised in a photo (camera "Scan Ingredients").
  Future<List<String>> scanIngredients(Uint8List jpeg) async {
    final res = await _call('scan_ingredients', {'image_base64': base64Encode(jpeg)});
    return (res['ingredients'] is List ? res['ingredients'] as List : const [])
        .map((e) => e is Map ? '${e['name'] ?? ''}'.trim() : '$e'.trim())
        .where((e) => e.isNotEmpty && e.length < 40)
        .toList();
  }

  /// Streams Chef AI's reply token-by-token for a snappy chat experience.
  Stream<String> askChefAI(List<Map<String, String>> history, AIContext ctx, {String? recipeJson}) async* {
    if (!isAvailable) throw AppFailure.aiBreak;
    final req = http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'action': 'chat',
        'stream': true,
        'context': ctx.toJson(),
        'messages': history.length > 16 ? history.sublist(history.length - 16) : history,
        'recipe': ?recipeJson,
      });
    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, 'Chef AI is taking too long. Please try again.');
    } catch (e) {
      throw AppFailure(FailureKind.offline, AppFailure.offline.message, e);
    }
    if (res.statusCode == 429) {
      throw const AppFailure(FailureKind.ai, "You've reached today's Chef AI limit. Try again tomorrow!");
    }
    if (res.statusCode == 401) throw loginNeeded;
    if (res.statusCode != 200) throw AppFailure.aiBreak;
    yield* res.stream.transform(utf8.decoder).timeout(_timeout);
  }

  // ── Validation helpers (public for tests) ──

  static List<Recipe> parseRecipes(Object? raw) {
    if (raw is! List) return const [];
    final out = <Recipe>[];
    for (final r in raw) {
      final parsed = Recipe.tryParseAi(r, newId());
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static List<MealPlanItem> parseMealPlan(Object? raw) {
    if (raw is! List) return const [];
    final out = <MealPlanItem>[];
    for (final d in raw.whereType<Map>()) {
      final day = d['day'] is int ? d['day'] as int : _dayIndex('${d['day']}');
      if (day < 0 || day > 6) continue;
      for (final m in (d['meals'] is List ? d['meals'] as List : const []).whereType<Map>()) {
        final name = '${m['recipe_name'] ?? m['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        out.add(MealPlanItem.fromJson({...Map<String, dynamic>.from(m), 'id': newId(), 'day': day, 'recipe_name': name}));
      }
    }
    return out;
  }

  static int _dayIndex(String s) {
    const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final l = s.toLowerCase();
    for (var i = 0; i < 7; i++) {
      if (l.startsWith(days[i])) return i;
    }
    return int.tryParse(l) ?? -1;
  }
}
