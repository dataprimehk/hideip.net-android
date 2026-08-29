import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Three anonymous counters, each sent once per install, so hideip.net can
/// see the shape of its funnel (opened, added a server, tunnel came up)
/// without ever seeing a person. The contract is docs/app-events-api.md.
///
/// What leaves the phone is exactly `{"event": ..., "platform": ...}`. No
/// identifier, no version, no locale, no timestamp beyond the one the
/// request itself carries, no cookie back. The server keeps a daily total per
/// event and platform and nothing else, which keeps the store declaration
/// "Data Not Collected" true. The user can switch it off in Settings; the
/// switch is honoured before anything else here runs.
///
/// Sending is fire-and-forget: a failed send is simply retried on the next
/// trigger, and the app never waits on it or shows an error for it.
enum AppEvent { firstOpen, firstProfile, firstConnect }

extension AppEventWire on AppEvent {
  String get wire => switch (this) {
        AppEvent.firstOpen => 'first_open',
        AppEvent.firstProfile => 'first_profile',
        AppEvent.firstConnect => 'first_connect',
      };
}

class AppTelemetry {
  AppTelemetry._();

  static const endpoint = String.fromEnvironment(
    'HIDEIP_EVENTS_ENDPOINT',
    defaultValue: 'https://hideip.net/api/app/events',
  );
  static const _timeout = Duration(seconds: 6);
  static const _prefix = 'tel_sent_v1_';

  /// Test seam: replaced in unit tests so nothing touches the network.
  @visibleForTesting
  static Future<bool> Function(Map<String, String> body) send = _post;

  static String get platform => Platform.isIOS ? 'ios' : 'android';

  /// Records [event] if allowed and not yet sent. Returns true when a request
  /// went out and was accepted; false for "already sent", "switched off" and
  /// any failure alike, because none of those are the caller's concern.
  static Future<bool> mark(AppEvent event, {required bool enabled}) async {
    if (!enabled) return false;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    final key = '$_prefix${event.wire}';
    if (prefs.getBool(key) ?? false) return false;
    final ok = await send({'event': event.wire, 'platform': platform});
    if (ok) await prefs.setBool(key, true);
    return ok;
  }

  static Future<bool> _post(Map<String, String> body) async {
    try {
      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
