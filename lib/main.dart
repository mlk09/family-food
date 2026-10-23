import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/notification_service.dart';
import 'data/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds a widget error would otherwise paint a blank/grey box.
  // Show readable text instead so users can screenshot it for a bug report.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => StartupErrorView(error: details.exceptionAsString());
  }

  try {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 10));
    try {
      await SessionNotifier.ensureDemoSeeded(prefs);
    } catch (e) {
      debugPrint('Demo seed failed: $e');
    }

    if (Env.isSupabaseConfigured) {
      try {
        // A slow network or a stuck deep-link check must never hold the
        // splash screen; the app works offline and connects later.
        await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey)
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('Supabase init failed: $e');
      }
    }

    // Notifications initialise in the background so they never delay launch.
    unawaited(NotificationService.instance.init().catchError((Object e) => debugPrint('Notifications init failed: $e')));

    runApp(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const FamilyFoodApp(),
    ));
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: StartupErrorView(error: '$e')),
    ));
  }
}

/// Shown instead of a blank screen when the app can't start or a screen fails.
class StartupErrorView extends StatelessWidget {
  const StartupErrorView({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF14110F),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                '😕 Kuch gadbad ho gayi\n\nApp band karke dobara kholo. Phir bhi aaye to is screen ka screenshot bhejo.\n\n$error',
                style: const TextStyle(color: Color(0xFFF5EDE6), fontSize: 16, height: 1.4, decoration: TextDecoration.none),
              ),
            ),
          ),
        ),
      );
}
