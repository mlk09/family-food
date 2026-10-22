import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../utils/app_error.dart';

/// Thin wrapper over Supabase Auth so the UI never talks to Supabase directly.
class AuthService {
  AuthService(this._client);
  final SupabaseClient? _client;

  bool get available => _client != null;
  User? get currentUser => _client?.auth.currentUser;
  Stream<AuthState> get changes => _client?.auth.onAuthStateChange ?? const Stream.empty();

  SupabaseClient get _db {
    final c = _client;
    if (c == null) {
      throw const AppFailure(
        FailureKind.auth,
        'Cloud sign-in is not set up yet. Use Demo Mode, or add your Supabase keys (see README).',
      );
    }
    return c;
  }

  Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Returns true when the user must confirm their email before logging in.
  Future<bool> signUp(String name, String email, String password) async {
    final res = await _db.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'name': name.trim()},
      emailRedirectTo: kIsWeb ? null : Env.authRedirectUrl,
    );
    return res.session == null;
  }

  Future<void> signInWithGoogle() async {
    await _db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : Env.authRedirectUrl,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _db.auth.resetPasswordForEmail(email.trim(), redirectTo: kIsWeb ? null : Env.authRedirectUrl);
  }

  Future<void> updatePassword(String password) async {
    await _db.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  /// Deletes the account server-side (Edge Function with service role).
  /// All user rows cascade-delete via foreign keys.
  Future<void> deleteAccount() async {
    final res = await _db.functions.invoke('delete-account', method: HttpMethod.post);
    if (res.status != 200) {
      throw const AppFailure(FailureKind.auth, "We couldn't delete your account right now. Please try again.");
    }
    await _db.auth.signOut();
  }
}
