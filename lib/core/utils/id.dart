import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated UUID v4 so rows can be created offline and synced later.
String newId() => _uuid.v4();

/// Monday of the week containing [d].
DateTime weekStartOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
