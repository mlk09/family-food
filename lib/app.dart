import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'data/settings.dart';
import 'routes/app_router.dart';

class FamilyFoodApp extends ConsumerWidget {
  const FamilyFoodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Re-schedule expiry reminders whenever the kitchen changes.
    ref.listen(ingredientsProvider, (_, next) {
      if (next.hasValue) ref.read(notificationPrefsProvider.notifier).apply();
    });
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) {
        // Respect the user's font size but cap extreme values so layouts hold.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.4)),
          child: child!,
        );
      },
    );
  }
}
