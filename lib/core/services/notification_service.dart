import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../models/ingredient.dart';

/// Local notifications: ingredient expiry, meal, shopping and plan reminders.
/// Push (server-sent) notifications can be added later via FCM/APNs; this
/// service keeps the same API so screens don't change.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _expiryBase = 1000;
  static const _mealBase = 2000;
  static const shoppingId = 3001;
  static const planId = 3002;

  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_ready || !supported) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Falls back to UTC — reminders may be offset but still fire.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final a = await android?.requestNotificationsPermission();
    final i = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return (a ?? i) ?? false;
  }

  NotificationDetails _details(String channel, String name) => NotificationDetails(
        android: AndroidNotificationDetails(channel, name, importance: Importance.defaultImportance, priority: Priority.defaultPriority),
        iOS: const DarwinNotificationDetails(),
      );

  /// Builds friendly expiry messages (pure, unit-tested).
  static List<({int id, String title, String body, DateTime when})> expiryReminders(List<Ingredient> items, DateTime now) {
    final out = <({int id, String title, String body, DateTime when})>[];
    var n = 0;
    for (final i in items) {
      final d = i.daysLeft(now);
      if (d == null || d < 0 || d > 3) continue;
      // Remind at 9 AM the day before expiry (or in a minute if that's past).
      final exp = DateTime(i.expiryDate!.year, i.expiryDate!.month, i.expiryDate!.day, 9);
      var when = exp.subtract(const Duration(days: 1));
      if (when.isBefore(now)) when = now.add(const Duration(minutes: 1));
      out.add((
        id: _expiryBase + n++,
        title: d == 0 ? '⏰ Use your ${i.name.toLowerCase()} today' : '🍅 Your ${i.name.toLowerCase()} may expire soon',
        body: 'Tap "What Can I Cook?" — Chef AI will use it first.',
        when: when,
      ));
      if (n >= 20) break;
    }
    return out;
  }

  Future<void> scheduleExpiry(List<Ingredient> items) async {
    await init();
    if (!_ready) return;
    for (var id = _expiryBase; id < _expiryBase + 20; id++) {
      await _plugin.cancel(id: id);
    }
    for (final r in expiryReminders(items, DateTime.now())) {
      await _schedule(r.id, r.title, r.body, r.when, _details('expiry', 'Ingredient expiry'));
    }
  }

  /// Daily meal reminders at the given hours (null = off).
  Future<void> scheduleMeals({required bool enabled, int breakfast = 8, int lunch = 12, int dinner = 19}) async {
    await init();
    if (!_ready) return;
    final meals = {'Breakfast 🍳': breakfast, 'Lunch 🥗': lunch, 'Dinner 🍛': dinner};
    var i = 0;
    for (final e in meals.entries) {
      final id = _mealBase + i++;
      await _plugin.cancel(id: id);
      if (!enabled) continue;
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, e.value).subtract(const Duration(minutes: 30));
      if (at.isBefore(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: id,
        title: '${e.key.split(' ').first} in 30 minutes',
        body: "Check today's meal plan ${e.key.split(' ').last}",
        scheduledDate: at,
        notificationDetails: _details('meals', 'Meal reminders'),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> scheduleShoppingReminder({required bool enabled, required int pendingItems}) async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: shoppingId);
    if (!enabled || pendingItems == 0) return;
    final when = DateTime.now().add(const Duration(hours: 24));
    await _schedule(shoppingId, '🛒 $pendingItems items on your shopping list', 'Planning a grocery run today?', when,
        _details('shopping', 'Shopping reminders'));
  }

  Future<void> schedulePlanReminder({required bool enabled}) async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: planId);
    if (!enabled) return;
    final now = tz.TZDateTime.now(tz.local);
    // Next Sunday 6 PM: plan the week ahead.
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18).add(Duration(days: (7 - now.weekday) % 7));
    if (at.isBefore(now)) at = at.add(const Duration(days: 7));
    await _plugin.zonedSchedule(
      id: planId,
      title: '📅 Plan next week\'s meals',
      body: 'Chef AI can build a 7-day plan in seconds.',
      scheduledDate: at,
      notificationDetails: _details('plan', 'Meal plan reminders'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> _schedule(int id, String title, String body, DateTime when, NotificationDetails d) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: d,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
