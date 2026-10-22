import 'package:family_food_assistant/app.dart';
import 'package:family_food_assistant/data/session.dart';
import 'package:family_food_assistant/routes/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(sp)],
    child: const FamilyFoodApp(),
  ));
  // Splash → redirect. (Never pumpAndSettle: the Chef AI button pulses forever.)
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('first launch shows onboarding, then login', (tester) async {
    await pumpApp(tester, {});
    expect(find.text("Tell us what's in your kitchen"), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Try Demo Mode'), findsOneWidget);
  });

  testWidgets('login form validates input', (tester) async {
    await pumpApp(tester, {onboardingSeenKey: true});
    await tester.tap(find.text('Log in'));
    await settle(tester);
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('demo mode → home → all five tabs', (tester) async {
    await pumpApp(tester, {onboardingSeenKey: true});
    await tester.tap(find.text('Try Demo Mode'));
    await settle(tester);

    expect(find.text('What Can I Cook?'), findsWidgets);
    expect(find.text('DEMO DATA'), findsWidgets);
    expect(find.text('My Kitchen'), findsWidgets);

    await tester.tap(find.text('My Kitchen').last);
    await settle(tester);
    expect(find.text('Search ingredients'), findsOneWidget);
    expect(find.text('Spinach'), findsWidgets);

    await tester.tap(find.text('Meal Plan').last);
    await settle(tester);
    expect(find.text('MONDAY'), findsOneWidget);

    await tester.tap(find.text('Shopping').last);
    await settle(tester);
    expect(find.text('Shopping List'), findsOneWidget);
    expect(find.text('Capsicum'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await settle(tester);
    expect(find.text('Demo Chef'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await settle(tester);
    expect(find.textContaining('Demo 👋'), findsOneWidget);
  });

  testWidgets('What Can I Cook shows instant recipes and opens a recipe', (tester) async {
    await pumpApp(tester, {onboardingSeenKey: true});
    await tester.tap(find.text('Try Demo Mode'));
    await settle(tester);
    await tester.tap(find.text('What Can I Cook?').first);
    await settle(tester);
    expect(find.text('Recipes you can make'), findsOneWidget);

    await tester.tap(find.textContaining('Masala Egg Rice').first);
    await settle(tester);
    expect(find.text('Start Cooking'), findsOneWidget);
    expect(find.text('Ingredients'), findsOneWidget);
  });

  testWidgets('Chef AI opens from the floating button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, {onboardingSeenKey: true});
    await tester.tap(find.text('Try Demo Mode'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('Ask Chef AI')).last);
    await settle(tester);
    expect(find.text('Chef AI'), findsOneWidget);
    expect(find.text('I have only 20 minutes.'), findsOneWidget);
    semantics.dispose();
  });
}
