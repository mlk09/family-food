import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON cache on top of SharedPreferences, namespaced per account so
/// family A's cached kitchen never leaks into family B's session on the same
/// device ("demo" is its own namespace).
class LocalStore {
  LocalStore(this._prefs, this.namespace);

  final SharedPreferences _prefs;
  final String namespace;

  String _k(String key) => '$namespace:$key';

  List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(_k(key), jsonEncode(value));

  Map<String, dynamic>? readMap(String key) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic>? value) =>
      value == null ? _prefs.remove(_k(key)) : _prefs.setString(_k(key), jsonEncode(value));

  bool getBool(String key, [bool fallback = false]) => _prefs.getBool(_k(key)) ?? fallback;
  Future<void> setBool(String key, bool v) => _prefs.setBool(_k(key), v);

  Future<void> clearNamespace() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('$namespace:')).toList()) {
      await _prefs.remove(k);
    }
  }
}
