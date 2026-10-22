import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/session.dart';
import '../features/ai/chef_chat_screen.dart';
import '../features/auth/auth_screens.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/family/family_screen.dart';
import '../features/home/home_screen.dart';
import '../features/kitchen/add_ingredient_screen.dart';
import '../features/kitchen/kitchen_screen.dart';
import '../features/meal_plan/meal_plan_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/recipes/cooking_mode_screen.dart';
import '../features/recipes/recipe_detail_screen.dart';
import '../features/recipes/saved_recipes_screen.dart';
import '../features/recipes/what_can_i_cook_screen.dart';
import '../features/shopping/shopping_screen.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import 'app_shell.dart';

class Routes {
  Routes._();
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const forgot = '/forgot';
  static const home = '/home';
  static const kitchen = '/kitchen';
  static const plan = '/plan';
  static const shopping = '/shopping';
  static const profile = '/profile';
  static const addIngredient = '/kitchen/add';
  static const cook = '/cook';
  static const recipe = '/recipe';
  static const cooking = '/cooking';
  static const chef = '/chef';
  static const family = '/family';
  static const saved = '/saved';
}

const onboardingSeenKey = 'onboarding_seen';

/// Bridges Riverpod session changes into GoRouter's refresh mechanism.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(sessionProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  const publicRoutes = {Routes.splash, Routes.onboarding, Routes.login, Routes.signup, Routes.forgot};

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == Routes.splash) return null;
      final session = ref.read(sessionProvider);
      final onboarded = ref.read(sharedPrefsProvider).getBool(onboardingSeenKey) ?? false;
      final isPublic = publicRoutes.contains(loc);
      if (!session.isSignedIn) {
        if (!onboarded && loc != Routes.onboarding) return Routes.onboarding;
        return isPublic ? null : Routes.login;
      }
      if (isPublic) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignUpScreen()),
      GoRoute(path: Routes.forgot, builder: (_, _) => const ForgotPasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.kitchen, builder: (_, _) => const KitchenScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.plan, builder: (_, _) => const MealPlanScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.shopping, builder: (_, _) => const ShoppingScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: Routes.addIngredient,
        builder: (_, s) => AddIngredientScreen(
          existing: s.extra is Ingredient ? s.extra as Ingredient : null,
          startScan: s.extra == 'scan',
        ),
      ),
      GoRoute(path: Routes.cook, builder: (_, _) => const WhatCanICookScreen()),
      GoRoute(
        path: Routes.recipe,
        redirect: (_, s) => s.extra is Recipe ? null : Routes.home,
        builder: (_, s) => RecipeDetailScreen(recipe: s.extra! as Recipe),
      ),
      GoRoute(
        path: Routes.cooking,
        redirect: (_, s) => s.extra is Recipe ? null : Routes.home,
        builder: (_, s) => CookingModeScreen(recipe: s.extra! as Recipe),
      ),
      GoRoute(
        path: Routes.chef,
        pageBuilder: (_, s) => MaterialPage(
          fullscreenDialog: true,
          child: ChefChatScreen(recipe: s.extra is Recipe ? s.extra as Recipe : null),
        ),
      ),
      GoRoute(path: Routes.family, builder: (_, _) => const FamilyScreen()),
      GoRoute(path: Routes.saved, builder: (_, _) => const SavedRecipesScreen()),
    ],
  );
});
