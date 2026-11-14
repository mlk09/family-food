import 'dart:async';

import 'package:family_food_assistant/app.dart';
import 'package:family_food_assistant/core/services/auth_service.dart';
import 'package:family_food_assistant/data/session.dart';
import 'package:family_food_assistant/routes/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed in through a reset-password email link.
class _RecoveryAuth extends AuthService {
  _RecoveryAuth() : super(null);
  final events = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => const User(id: 'u1', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');

  @override
  Stream<AuthState> get changes => events.stream;
}

void main() {
  testWidgets('reset-password link asks for a new password', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({onboardingSeenKey: true});
    final sp = await SharedPreferences.getInstance();
    final auth = _RecoveryAuth();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(sp), authServiceProvider.overrideWithValue(auth)],
      child: const FamilyFoodApp(),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 600));

    auth.events.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Naya password banao'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'secret123');
    await tester.enterText(find.byType(TextFormField).last, 'secret124');
    await tester.tap(find.text('Password save karo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dono password ek jaise nahi hain'), findsOneWidget);
    await auth.events.close();
  });
}
