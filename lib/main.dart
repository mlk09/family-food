import 'dart:async';

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

  final prefs = await SharedPreferences.getInstance();
  await SessionNotifier.ensureDemoSeeded(prefs);

  if (Env.isSupabaseConfigured) {
    try {
      await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  }

  // Notifications initialise in the background so they never delay launch.
  unawaited(NotificationService.instance.init());

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const FamilyFoodApp(),
  ));
}
