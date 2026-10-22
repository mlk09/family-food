import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum FailureKind { offline, timeout, ai, auth, database, validation, unknown }

/// A user-safe error. [message] is always friendly; [cause] is for logs only.
class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, [this.cause]);
  final FailureKind kind;
  final String message;
  final Object? cause;

  static const aiBreak = AppFailure(FailureKind.ai, 'Chef AI is taking a short break. Please try again.');
  static const offline =
      AppFailure(FailureKind.offline, "You're offline. We'll keep things saved and sync when you're back.");

  @override
  String toString() => message;
}

/// Converts any exception into a friendly message. Never shows raw errors.
String friendlyError(Object error) {
  if (error is AppFailure) return error.message;
  if (error is TimeoutException) return 'That took too long. Please check your connection and try again.';
  if (error is AuthException) return _authMessage(error);
  if (error is PostgrestException) {
    if (error.code == '42501') return "You don't have permission to do that.";
    return "We couldn't save that right now. Please try again.";
  }
  if (error is FunctionException) return AppFailure.aiBreak.message;
  final s = error.toString().toLowerCase();
  if (s.contains('socket') || s.contains('network') || s.contains('failed host lookup') || s.contains('clientexception')) {
    return AppFailure.offline.message;
  }
  return 'Something went wrong. Please try again.';
}

String _authMessage(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) return 'Email or password is incorrect.';
  if (m.contains('already registered') || m.contains('already exists')) return 'An account with this email already exists. Try logging in.';
  if (m.contains('email not confirmed')) return 'Please confirm your email first — check your inbox.';
  if (m.contains('password')) return 'Password must be at least 6 characters.';
  if (m.contains('rate limit')) return 'Too many attempts. Please wait a minute and try again.';
  if (m.contains('anonymous')) return 'Guest access is not enabled for this server.';
  return 'Sign-in failed. Please try again.';
}
