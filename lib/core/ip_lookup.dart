import 'dart:async';

import 'package:http/http.dart' as http;

/// Fetches the device's current public IP, used on the home screen as proof
/// that traffic is (or isn't) going through the tunnel.
///
/// TODO(hideip): replace [_endpoint] with hideip.net's own IP endpoint once a
/// serverless function exists (e.g. https://hideip.net/api/ip returning {"ip":...}).
/// For now we use ipify, which returns the bare IP as plain text.
class IpLookup {
  static const _endpoint = 'https://api.ipify.org';
  static const _timeout = Duration(seconds: 8);

  /// Returns the public IP string, or null on any failure (no network, timeout).
  static Future<String?> current() async {
    try {
      final res = await http.get(Uri.parse(_endpoint)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final ip = res.body.trim();
      return ip.isEmpty ? null : ip;
    } catch (_) {
      return null;
    }
  }
}
