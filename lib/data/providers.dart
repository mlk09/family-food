import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/app_error.dart';
import '../core/utils/id.dart';
import '../core/utils/ingredient_matcher.dart';
import '../models/ingredient.dart';
import '../models/meal_plan.dart';
import '../models/profile.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import 'local_store.dart';
import 'session.dart';
import 'sync_engine.dart';

/// Offline-first list repository: returns the local cache instantly, refreshes
/// from Supabase in the background, and queues writes through the outbox.
abstract class CollectionNotifier<T> extends AsyncNotifier<List<T>> {
  String get cacheKey;
  String get table;
  T fromJson(Map<String, dynamic> j);
  Map<String, dynamic> toJson(T item);
  String idOf(T item);
  int compare(T a, T b) => 0;

  Future<List<Map<String, dynamic>>> fetchRemote(SupabaseClient db) => db.from(table).select();
  OutboxOp upsertOp(T item) => OutboxOp('upsert', table, toJson(item));
  OutboxOp deleteOp(T item) => OutboxOp('delete', table, {'id': idOf(item)});

  late LocalStore _store;
  late SyncEngine _sync;
  late AppSession session;

  @override
  Future<List<T>> build() async {
    session = ref.watch(sessionProvider);
    _store = ref.watch(localStoreProvider);
    _sync = ref.watch(syncEngineProvider);
    final cached = _store.readList(cacheKey).map(fromJson).toList()..sort(compare);
    if (session.isCloud) Future.microtask(refresh);
    return cached;
  }

  List<T> get items => state.value ?? const [];

  Future<void> refresh() async {
    final db = ref.read(supabaseClientProvider);
    if (db == null || !session.isCloud) return;
    try {
      await _sync.flush();
      final rows = await fetchRemote(db).timeout(const Duration(seconds: 12));
      // Don't clobber local edits that haven't reached the server yet.
      if (_sync.pending > 0) return;
      final list = rows.map(fromJson).toList()..sort(compare);
      await _store.writeList(cacheKey, list.map(toJson).toList());
      state = AsyncData(list);
    } catch (e) {
      debugPrint('$table refresh skipped: $e');
    }
  }

  Future<void> _persist(List<T> list) async {
    list.sort(compare);
    state = AsyncData(list);
    await _store.writeList(cacheKey, list.map(toJson).toList());
  }

  Future<void> upsert(T item) async {
    final list = [...items.where((e) => idOf(e) != idOf(item)), item];
    await _persist(list);
    await _sync.enqueue(upsertOp(item));
  }

  Future<void> upsertAll(List<T> newItems) async {
    final ids = newItems.map(idOf).toSet();
    await _persist([...items.where((e) => !ids.contains(idOf(e))), ...newItems]);
    for (final i in newItems) {
      await _sync.enqueue(upsertOp(i));
    }
  }

  Future<void> remove(T item) async {
    await _persist(items.where((e) => idOf(e) != idOf(item)).toList());
    await _sync.enqueue(deleteOp(item));
  }

  /// Ownership stamp for new rows.
  ({String userId, String? familyId}) get owner =>
      (userId: session.ownerId, familyId: ref.read(profileProvider).value?.familyId);
}

// ───────────────────────── Kitchen inventory ─────────────────────────

class IngredientsNotifier extends CollectionNotifier<Ingredient> {
  @override
  String get cacheKey => 'ingredients';
  @override
  String get table => 'ingredients';
  @override
  Ingredient fromJson(Map<String, dynamic> j) => Ingredient.fromJson(j);
  @override
  Map<String, dynamic> toJson(Ingredient i) => i.toJson();
  @override
  String idOf(Ingredient i) => i.id;
  @override
  int compare(Ingredient a, Ingredient b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());

  Future<void> save(Ingredient i) =>
      upsert(i.userId == null ? i.copyWith(userId: owner.userId, familyId: owner.familyId) : i);

  /// Adds ingredients, merging quantity into an existing item with the same name.
  Future<void> addOrMerge(List<Ingredient> incoming) async {
    final out = <Ingredient>[];
    for (final n in incoming) {
      final existing = items.where((e) => IngredientNames.matches(e.name, n.name) && e.unit == n.unit).firstOrNull;
      out.add(existing == null
          ? n.copyWith(userId: owner.userId, familyId: owner.familyId)
          : existing.copyWith(quantity: existing.quantity + n.quantity, expiryDate: n.expiryDate));
    }
    await upsertAll(out);
  }
}

final ingredientsProvider =
    AsyncNotifierProvider<IngredientsNotifier, List<Ingredient>>(IngredientsNotifier.new);

// ───────────────────────── Shopping list ─────────────────────────

class ShoppingNotifier extends CollectionNotifier<ShoppingItem> {
  @override
  String get cacheKey => 'shopping';
  @override
  String get table => 'shopping_list_items';
  @override
  ShoppingItem fromJson(Map<String, dynamic> j) => ShoppingItem.fromJson(j);
  @override
  Map<String, dynamic> toJson(ShoppingItem i) => i.toJson();
  @override
  String idOf(ShoppingItem i) => i.id;
  @override
  int compare(ShoppingItem a, ShoppingItem b) {
    if (a.checked != b.checked) return a.checked ? 1 : -1;
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> save(ShoppingItem i) =>
      upsert(i.userId == null ? i.copyWith(userId: owner.userId, familyId: owner.familyId) : i);

  /// Adds names to the list, skipping ones that are already there unchecked.
  Future<int> addNames(List<String> names, {String? recipeName, Map<String, String> quantities = const {}}) async {
    final existing = items.where((i) => !i.checked).map((i) => IngredientNames.normalize(i.name)).toSet();
    final fresh = <ShoppingItem>[];
    for (final n in names) {
      final key = IngredientNames.normalize(n);
      if (key.isEmpty || existing.contains(key)) continue;
      existing.add(key);
      fresh.add(ShoppingItem(
        id: newId(),
        userId: owner.userId,
        familyId: owner.familyId,
        name: n[0].toUpperCase() + n.substring(1),
        quantity: quantities[n] ?? '',
        category: IngredientMatcher.categoryFor(n),
        recipeName: recipeName,
      ));
    }
    if (fresh.isNotEmpty) await upsertAll(fresh);
    return fresh.length;
  }

  Future<void> toggle(ShoppingItem i) => upsert(i.copyWith(checked: !i.checked));

  Future<void> clearChecked() async {
    for (final i in items.where((i) => i.checked).toList()) {
      await remove(i);
    }
  }

  /// Moves bought (checked) items into the kitchen inventory.
  Future<int> moveCheckedToKitchen() async {
    final bought = items.where((i) => i.checked).toList();
    if (bought.isEmpty) return 0;
    final now = DateTime.now();
    await ref.read(ingredientsProvider.notifier).addOrMerge([
      for (final b in bought)
        Ingredient(
          id: newId(),
          name: b.name,
          quantity: double.tryParse(RegExp(r'[\d.]+').firstMatch(b.quantity)?.group(0) ?? '') ?? 1,
          unit: _unitFrom(b.quantity),
          category: b.category,
          purchaseDate: now,
          expiryDate: now.add(Duration(days: _shelfLife(b.category))),
        ),
    ]);
    await clearChecked();
    return bought.length;
  }

  static String _unitFrom(String q) {
    final l = q.toLowerCase();
    for (final u in ['kg', 'litre', 'ml', 'packet', 'bottle', 'cup', 'spoon']) {
      if (l.contains(u)) return u;
    }
    if (RegExp(r'\d\s*g\b').hasMatch(l)) return 'g';
    return 'pieces';
  }

  static int _shelfLife(String category) => switch (category) {
        'vegetables' => 7,
        'fruits' => 6,
        'dairy' => 5,
        'meat' => 2,
        'eggs' => 14,
        'frozen' => 60,
        _ => 90,
      };
}

final shoppingProvider = AsyncNotifierProvider<ShoppingNotifier, List<ShoppingItem>>(ShoppingNotifier.new);

// ───────────────────────── Saved recipes ─────────────────────────

const _recipeNs = '6f1b3c2a-8d4e-4f5a-9b7c-1e2d3f4a5b6c';

/// Library recipes have slug ids; map them to a stable per-user UUID so two
/// families saving the same built-in recipe never collide.
String recipeDbId(String id, String owner) =>
    Uuid.isValidUUID(fromString: id) ? id : const Uuid().v5(_recipeNs, '$owner:$id');

class SavedRecipesNotifier extends CollectionNotifier<Recipe> {
  @override
  String get cacheKey => 'saved_recipes';
  @override
  String get table => 'saved_recipes';
  @override
  Recipe fromJson(Map<String, dynamic> j) => Recipe.fromJson(j);
  @override
  Map<String, dynamic> toJson(Recipe r) => r.toJson();
  @override
  String idOf(Recipe r) => r.id;

  @override
  Future<List<Map<String, dynamic>>> fetchRemote(SupabaseClient db) async {
    final rows = await db
        .from('saved_recipes')
        .select('recipe_id, recipes(data)')
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        if (r['recipes'] is Map && (r['recipes'] as Map)['data'] is Map)
          {...Map<String, dynamic>.from((r['recipes'] as Map)['data'] as Map), 'id': r['recipe_id']},
    ];
  }

  @override
  OutboxOp upsertOp(Recipe item) => OutboxOp('save_recipe', table, {
        'id': newId(),
        'user_id': owner.userId,
        'family_id': owner.familyId,
        'recipe': item.toJson(),
      });

  @override
  OutboxOp deleteOp(Recipe item) =>
      OutboxOp('unsave_recipe', table, {'recipe_id': item.id, 'user_id': owner.userId});

  bool isSaved(Recipe r) => items.any((e) => e.id == r.id || e.name == r.name);

  Future<bool> toggle(Recipe r) async {
    final existing = items.where((e) => e.id == r.id || e.name == r.name).firstOrNull;
    if (existing != null) {
      await remove(existing);
      return false;
    }
    await upsert(r.copyWith(id: recipeDbId(r.id, owner.userId)));
    return true;
  }
}

final savedRecipesProvider = AsyncNotifierProvider<SavedRecipesNotifier, List<Recipe>>(SavedRecipesNotifier.new);

// ───────────────────────── Recently viewed (device only) ─────────────────────────

class RecentRecipesNotifier extends Notifier<List<Recipe>> {
  @override
  List<Recipe> build() => ref.watch(localStoreProvider).readList('recent_recipes').map(Recipe.fromJson).toList();

  Future<void> add(Recipe r) async {
    final list = [r, ...state.where((e) => e.name != r.name)].take(15).toList();
    state = list;
    await ref.read(localStoreProvider).writeList('recent_recipes', list.map((e) => e.toJson()).toList());
  }
}

final recentRecipesProvider = NotifierProvider<RecentRecipesNotifier, List<Recipe>>(RecentRecipesNotifier.new);

// ───────────────────────── Profile ─────────────────────────

class ProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    final session = ref.watch(sessionProvider);
    final store = ref.watch(localStoreProvider);
    final cached = store.readMap('profile');
    if (session.isCloud) Future.microtask(refresh);
    return cached == null ? UserProfile(id: session.ownerId) : UserProfile.fromJson(cached);
  }

  Future<void> refresh() async {
    final db = ref.read(supabaseClientProvider);
    final session = ref.read(sessionProvider);
    if (db == null || !session.isCloud) return;
    try {
      final row = await db.from('profiles').select().eq('id', session.ownerId).maybeSingle().timeout(const Duration(seconds: 12));
      if (row == null) return;
      final p = UserProfile.fromJson(row);
      await ref.read(localStoreProvider).writeMap('profile', p.toJson());
      state = AsyncData(p);
    } catch (e) {
      debugPrint('profile refresh skipped: $e');
    }
  }

  Future<void> save(UserProfile p) async {
    state = AsyncData(p);
    await ref.read(localStoreProvider).writeMap('profile', p.toJson());
    await ref.read(syncEngineProvider).enqueue(OutboxOp('profile', 'profiles', p.toJson()));
  }

  Future<void> recordCooked() async {
    final p = state.value;
    if (p != null) await save(p.recordCooked());
  }

  Future<String?> uploadAvatar(Uint8List bytes, String ext) async {
    final db = ref.read(supabaseClientProvider);
    final session = ref.read(sessionProvider);
    if (db == null || !session.isCloud) return null;
    final path = '${session.ownerId}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'));
    return db.storage.from('avatars').getPublicUrl(path);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// ───────────────────────── Meal plan ─────────────────────────

class MealPlanNotifier extends AsyncNotifier<MealPlan?> {
  @override
  Future<MealPlan?> build() async {
    final session = ref.watch(sessionProvider);
    final cached = ref.watch(localStoreProvider).readMap('meal_plan');
    if (session.isCloud) Future.microtask(refresh);
    return cached == null ? null : MealPlan.fromJson(cached);
  }

  Future<void> refresh() async {
    final db = ref.read(supabaseClientProvider);
    if (db == null || !ref.read(sessionProvider).isCloud) return;
    final sync = ref.read(syncEngineProvider);
    try {
      await sync.flush();
      final row = await db
          .from('meal_plans')
          .select('*, meal_plan_items(*)')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (row == null || sync.pending > 0) return;
      final items = (row['meal_plan_items'] as List? ?? const [])
          .map((e) => {...Map<String, dynamic>.from(e as Map), 'recipe_id': (e)['library_key']})
          .toList();
      final plan = MealPlan.fromJson({...row, 'items': items});
      await ref.read(localStoreProvider).writeMap('meal_plan', plan.toJson());
      state = AsyncData(plan);
    } catch (e) {
      debugPrint('meal plan refresh skipped: $e');
    }
  }

  Future<void> save(MealPlan plan) async {
    final session = ref.read(sessionProvider);
    final stamped = plan.copyWith(
      userId: plan.userId ?? session.ownerId,
      familyId: plan.familyId ?? ref.read(profileProvider).value?.familyId,
    );
    state = AsyncData(stamped);
    await ref.read(localStoreProvider).writeMap('meal_plan', stamped.toJson());
    await ref.read(syncEngineProvider).enqueue(OutboxOp('meal_plan', 'meal_plans', stamped.toJson()));
  }
}

final mealPlanProvider = AsyncNotifierProvider<MealPlanNotifier, MealPlan?>(MealPlanNotifier.new);

// ───────────────────────── Family ─────────────────────────

class FamilyNotifier extends AsyncNotifier<Family?> {
  @override
  Future<Family?> build() async {
    final session = ref.watch(sessionProvider);
    final cached = ref.watch(localStoreProvider).readMap('family');
    if (session.isCloud) Future.microtask(refresh);
    return cached == null ? null : Family.fromJson(cached);
  }

  SupabaseClient _online() {
    final db = ref.read(supabaseClientProvider);
    if (db == null || !ref.read(sessionProvider).isCloud) {
      throw const AppFailure(FailureKind.validation, 'Family sharing needs a signed-in account. Demo data is view-only here.');
    }
    return db;
  }

  Future<void> refresh() async {
    final db = ref.read(supabaseClientProvider);
    if (db == null || !ref.read(sessionProvider).isCloud) return;
    try {
      final membership = await db
          .from('family_members')
          .select('family_id')
          .eq('user_id', ref.read(sessionProvider).ownerId)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      Family? fam;
      if (membership != null) {
        final row = await db
            .from('families')
            .select('id, name, invite_code, family_members(user_id, display_name, role, is_admin)')
            .eq('id', membership['family_id'] as Object)
            .single();
        fam = Family.fromJson(row);
      }
      await ref.read(localStoreProvider).writeMap('family', fam?.toJson());
      state = AsyncData(fam);
    } catch (e) {
      debugPrint('family refresh skipped: $e');
    }
  }

  Future<void> _afterChange() async {
    await refresh();
    await ref.read(profileProvider.notifier).refresh();
    ref.invalidate(ingredientsProvider);
    ref.invalidate(shoppingProvider);
    ref.invalidate(mealPlanProvider);
    ref.invalidate(savedRecipesProvider);
  }

  Future<void> create(String name, String displayName, String role) async {
    await _online().rpc('create_family', params: {'p_name': name, 'p_display_name': displayName, 'p_role': role});
    await _afterChange();
  }

  Future<void> join(String code, String displayName, String role) async {
    await _online().rpc('join_family', params: {'p_code': code.trim().toUpperCase(), 'p_display_name': displayName, 'p_role': role});
    await _afterChange();
  }

  Future<void> leave() async {
    await _online().rpc('leave_family');
    await _afterChange();
  }
}

final familyProvider = AsyncNotifierProvider<FamilyNotifier, Family?>(FamilyNotifier.new);
