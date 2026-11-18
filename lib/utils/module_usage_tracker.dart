import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ModuleUsageTracker {
  ModuleUsageTracker._();

  static String _key(String facilityId) => 'ns_module_usage_v1_$facilityId';

  static const defaultModuleNames = [
    'Work Orders',
    'Work on Request',
    'Assets & BIM',
    'Preventive Maintenance',
  ];

  static Future<void> reset(String facilityId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(facilityId));
    } catch (_) {}
  }

  static Future<void> track(String moduleName, {required String facilityId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(facilityId));
      final Map<String, int> counts = raw != null
          ? (jsonDecode(raw) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toInt()))
          : {};
      counts[moduleName] = (counts[moduleName] ?? 0) + 1;
      await prefs.setString(_key(facilityId), jsonEncode(counts));
    } catch (_) {}
  }

  static Future<List<String>> getTop(
    int n, {
    required String facilityId,
    List<String>? allowedNames,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(facilityId));

      Map<String, int> counts = {};
      if (raw != null) {
        counts = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      if (allowedNames != null) {
        counts = Map.fromEntries(
            counts.entries.where((e) => allowedNames.contains(e.key)));
      }

      final fillFrom = allowedNames != null
          ? defaultModuleNames.where(allowedNames.contains).toList()
          : List<String>.from(defaultModuleNames);

      if (counts.isEmpty) return fillFrom.take(n).toList();

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final result = sorted.take(n).map((e) => e.key).toList();
      for (final d in fillFrom) {
        if (result.length >= n) break;
        if (!result.contains(d)) result.add(d);
      }
      return result;
    } catch (_) {
      return defaultModuleNames.take(n).toList();
    }
  }
}
