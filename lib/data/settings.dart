import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/notification_service.dart';
import 'providers.dart';
import 'session.dart';
import 'sync_engine.dart';

/// Device-wide theme choice (light / dark / system).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final v = ref.watch(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.dark);
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    await ref.read(sharedPrefsProvider).setString(_key, m.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class NotificationPrefs {
  const NotificationPrefs({this.expiry = true, this.meals = false, this.shopping = false, this.plan = false});
  final bool expiry, meals, shopping, plan;

  NotificationPrefs copyWith({bool? expiry, bool? meals, bool? shopping, bool? plan}) => NotificationPrefs(
        expiry: expiry ?? this.expiry,
        meals: meals ?? this.meals,
        shopping: shopping ?? this.shopping,
        plan: plan ?? this.plan,
      );

  Map<String, dynamic> toJson() =>
      {'notify_expiry': expiry, 'notify_meals': meals, 'notify_shopping': shopping, 'notify_plan': plan};

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        expiry: j['notify_expiry'] as bool? ?? true,
        meals: j['notify_meals'] as bool? ?? false,
        shopping: j['notify_shopping'] as bool? ?? false,
        plan: j['notify_plan'] as bool? ?? false,
      );
}

/// Per-account notification settings, mirrored to `user_preferences`.
class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() {
    final j = ref.watch(localStoreProvider).readMap('prefs');
    return j == null ? const NotificationPrefs() : NotificationPrefs.fromJson(j);
  }

  Future<void> update(NotificationPrefs p) async {
    final enabling = (p.expiry && !state.expiry) || (p.meals && !state.meals) || (p.shopping && !state.shopping) || (p.plan && !state.plan);
    state = p;
    await ref.read(localStoreProvider).writeMap('prefs', p.toJson());
    final session = ref.read(sessionProvider);
    await ref.read(syncEngineProvider).enqueue(OutboxOp('upsert', 'user_preferences', {
      'user_id': session.ownerId,
      ...p.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }));
    if (enabling) await NotificationService.instance.requestPermission();
    await apply();
  }

  /// Re-schedules all local notifications from current data.
  Future<void> apply() async {
    final n = NotificationService.instance;
    if (!n.supported) return;
    final items = ref.read(ingredientsProvider).value ?? const [];
    final shopping = ref.read(shoppingProvider).value ?? const [];
    if (state.expiry) {
      unawaited(n.scheduleExpiry(items));
    } else {
      unawaited(n.scheduleExpiry(const []));
    }
    unawaited(n.scheduleMeals(enabled: state.meals));
    unawaited(n.scheduleShoppingReminder(enabled: state.shopping, pendingItems: shopping.where((s) => !s.checked).length));
    unawaited(n.schedulePlanReminder(enabled: state.plan));
  }
}

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(NotificationPrefsNotifier.new);
