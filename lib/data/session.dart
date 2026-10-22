import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/services/auth_service.dart';
import 'demo_data.dart';
import 'local_store.dart';
import 'sync_engine.dart';

enum SessionMode { signedOut, demo, cloud }

class AppSession {
  const AppSession(this.mode, {this.userId, this.email, this.isAnonymous = false});
  final SessionMode mode;
  final String? userId;
  final String? email;
  final bool isAnonymous;

  bool get isDemo => mode == SessionMode.demo;
  bool get isCloud => mode == SessionMode.cloud;
  bool get isSignedIn => mode != SessionMode.signedOut;
  String get namespace => isDemo ? 'demo' : 'u:${userId ?? 'anon'}';

  /// The user id written into rows (demo uses a fixed local id).
  String get ownerId => userId ?? DemoData.demoUserId;
}

/// Overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!Env.isSupabaseConfigured) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null; // initialisation failed (e.g. offline first launch)
  }
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(supabaseClientProvider)));

class SessionNotifier extends Notifier<AppSession> {
  static const _demoKey = 'demo_mode';

  /// Call before runApp: re-seeds demo data if the demo flag survived but the
  /// data did not (e.g. partially cleared storage).
  static Future<void> ensureDemoSeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_demoKey) ?? false) await DemoData.seedIfNeeded(LocalStore(prefs, 'demo'));
  }

  @override
  AppSession build() {
    final prefs = ref.watch(sharedPrefsProvider);
    final auth = ref.watch(authServiceProvider);
    final sub = auth.changes.listen((_) => _sync());
    ref.onDispose(sub.cancel);
    if (prefs.getBool(_demoKey) ?? false) return const AppSession(SessionMode.demo);
    return _fromUser(auth.currentUser);
  }

  AppSession _fromUser(User? u) => u == null
      ? const AppSession(SessionMode.signedOut)
      : AppSession(SessionMode.cloud, userId: u.id, email: u.email, isAnonymous: u.isAnonymous);

  void _sync() {
    if (state.isDemo) return;
    final next = _fromUser(ref.read(authServiceProvider).currentUser);
    if (next.userId != state.userId || next.mode != state.mode) state = next;
  }

  Future<void> enterDemo() async {
    final prefs = ref.read(sharedPrefsProvider);
    await DemoData.seedIfNeeded(LocalStore(prefs, 'demo'));
    await prefs.setBool(_demoKey, true);
    state = const AppSession(SessionMode.demo);
  }

  Future<void> resetDemo() async {
    final prefs = ref.read(sharedPrefsProvider);
    await LocalStore(prefs, 'demo').clearNamespace();
    await enterDemo();
    ref.invalidateSelf();
  }

  Future<void> signOut() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (state.isDemo) {
      await prefs.setBool(_demoKey, false);
    } else {
      await ref.read(authServiceProvider).signOut();
    }
    state = const AppSession(SessionMode.signedOut);
  }

  /// Call after a successful sign-in to leave demo mode and pick up the user.
  Future<void> refreshFromAuth() async {
    await ref.read(sharedPrefsProvider).setBool(_demoKey, false);
    state = _fromUser(ref.read(authServiceProvider).currentUser);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AppSession>(SessionNotifier.new);

final localStoreProvider = Provider<LocalStore>((ref) {
  final session = ref.watch(sessionProvider);
  return LocalStore(ref.watch(sharedPrefsProvider), session.namespace);
});

/// Flushes queued writes now and whenever connectivity returns.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final session = ref.watch(sessionProvider);
  final engine = SyncEngine(
    ref.watch(localStoreProvider),
    session.isCloud ? ref.watch(supabaseClientProvider) : null,
  );
  if (engine.enabled) {
    final sub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) unawaited(engine.flush());
    });
    ref.onDispose(sub.cancel);
    unawaited(engine.flush());
  }
  return engine;
});

/// True when the device reports any network connection.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  final first = await c.checkConnectivity();
  yield !first.contains(ConnectivityResult.none);
  yield* c.onConnectivityChanged.map((r) => !r.contains(ConnectivityResult.none));
});
