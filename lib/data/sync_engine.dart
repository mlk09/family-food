import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';

/// A pending remote write. Every mutation is applied to the local cache first
/// and queued here, so the app is fully usable offline.
class OutboxOp {
  const OutboxOp(this.kind, this.table, this.payload);
  final String kind; // upsert | delete | meal_plan | save_recipe | unsave_recipe | profile
  final String table;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {'kind': kind, 'table': table, 'payload': payload};
  factory OutboxOp.fromJson(Map<String, dynamic> j) =>
      OutboxOp(j['kind'] as String, j['table'] as String, Map<String, dynamic>.from(j['payload'] as Map));
}

/// Applies queued writes to Supabase in order. If a write fails because we are
/// offline it stays queued; if Supabase rejects it (e.g. RLS) it is dropped so
/// one bad row never blocks the queue forever.
class SyncEngine {
  SyncEngine(this.store, this.client);

  final LocalStore store;
  final SupabaseClient? client;
  Future<void>? _running;
  bool _again = false;

  static const _key = 'outbox';

  bool get enabled => client != null;
  int get pending => store.readList(_key).length;

  Future<void> enqueue(OutboxOp op) async {
    if (!enabled) return;
    final ops = store.readList(_key)..add(op.toJson());
    await store.writeList(_key, ops);
    unawaited(flush());
  }

  /// Drains the queue. Calls made while a drain is running schedule one more
  /// pass, so a "back online" signal is never lost.
  Future<void> flush() {
    if (!enabled) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _drain();
    } while (_again);
  }

  Future<void> _drain() async {
    {
      while (true) {
        final ops = store.readList(_key);
        if (ops.isEmpty) break;
        final op = OutboxOp.fromJson(ops.first);
        try {
          await _apply(op).timeout(const Duration(seconds: 15));
        } on PostgrestException catch (e) {
          debugPrint('Sync dropped ${op.kind} ${op.table}: ${e.message}');
        } catch (e) {
          // Network problem: keep the op and try again later.
          debugPrint('Sync paused: $e');
          break;
        }
        final rest = store.readList(_key);
        if (rest.isNotEmpty) rest.removeAt(0);
        await store.writeList(_key, rest);
      }
    }
  }

  Future<void> _apply(OutboxOp op) async {
    final db = client!;
    final p = Map<String, dynamic>.from(op.payload);
    switch (op.kind) {
      case 'upsert':
        await db.from(op.table).upsert(p);
      case 'delete':
        await db.from(op.table).delete().eq('id', p['id'] as Object);
      case 'profile':
        p.remove('family_id'); // family membership only changes via RPC
        await db.from('profiles').update(p).eq('id', p['id'] as Object);
      case 'save_recipe':
        final recipe = Map<String, dynamic>.from(p['recipe'] as Map);
        await db.from('recipes').upsert({
          'id': recipe['id'],
          'user_id': p['user_id'],
          'family_id': p['family_id'],
          'name': recipe['name'],
          'source': recipe['source'] ?? 'ai',
          'data': recipe,
        });
        await db.from('saved_recipes').upsert({
          'id': p['id'],
          'user_id': p['user_id'],
          'family_id': p['family_id'],
          'recipe_id': recipe['id'],
        }, onConflict: 'user_id,recipe_id');
      case 'unsave_recipe':
        // RLS limits this to the user's own or family-shared favourites.
        await db.from('saved_recipes').delete().eq('recipe_id', p['recipe_id'] as Object);
      case 'meal_plan':
        final items = (p.remove('items') as List? ?? const []).cast<Map>();
        await db.from('meal_plans').upsert(p);
        await db.from('meal_plan_items').delete().eq('meal_plan_id', p['id'] as Object);
        if (items.isNotEmpty) {
          await db.from('meal_plan_items').insert([
            for (final i in items)
              {
                'id': i['id'],
                'meal_plan_id': p['id'],
                'user_id': p['user_id'],
                'family_id': p['family_id'],
                'day_index': i['day'],
                'meal_type': i['meal_type'],
                'recipe_name': i['recipe_name'],
                'emoji': i['emoji'],
                'description': i['description'],
                'ingredients': i['ingredients'],
                'library_key': i['recipe_id'],
              }
          ]);
        }
      default:
        debugPrint('Unknown outbox op ${op.kind}');
    }
  }
}
