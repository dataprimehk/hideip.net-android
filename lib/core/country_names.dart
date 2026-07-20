import 'dart:convert';

import 'package:flutter/services.dart';

/// Country names for vote codes (ISO 3166-1 numeric), read once from the same
/// world-atlas asset the map is drawn from, so the two never disagree.
class CountryNames {
  static Future<Map<String, String>>? _loading;

  static Future<Map<String, String>> load() => _loading ??= _decode();

  static Future<Map<String, String>> _decode() async {
    final raw = await rootBundle.loadString('assets/world_geo.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    return {
      for (final c in data['countries'] as List)
        if (((c as Map)['name'] as String?) case final name?
            when name.isNotEmpty)
          c['id'] as String: name,
    };
  }
}
