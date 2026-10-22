/// Defensive JSON readers. AI responses and cached data are untrusted, so
/// every reader tolerates wrong types instead of throwing.
library;

String jStr(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v.trim();
  return v.toString();
}

String? jStrOrNull(Object? v) {
  final s = jStr(v);
  return s.isEmpty ? null : s;
}

int jInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) {
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
    if (m != null) return double.parse(m.group(0)!).round();
  }
  return fallback;
}

double jDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

bool jBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

DateTime? jDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

List<Map<String, dynamic>> jMapList(Object? v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

List<String> jStrList(Object? v) {
  if (v is! List) return const [];
  return v
      .map((e) => e is Map ? jStr(e['name'] ?? e['text'] ?? e['step']) : jStr(e))
      .where((e) => e.isNotEmpty)
      .toList();
}

String? dateOnly(DateTime? d) =>
    d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
