import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Approximate location of the current public IP, used to anchor the "you"
/// pin on the world map.
class IpGeo {
  final double lat;
  final double lon;
  final String city;
  const IpGeo({required this.lat, required this.lon, required this.city});
}

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

  /// Geolocates the current public IP (approximate, city-level), or null on
  /// any failure. Only meaningful while the tunnel is down: with it up, the
  /// public IP geolocates to the exit node, not to the user.
  static Future<IpGeo?> locate() async {
    try {
      final res =
          await http.get(Uri.parse('https://ipwho.is/')).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['success'] == false) return null;
      final lat = data['latitude'], lon = data['longitude'];
      if (lat is! num || lon is! num) return null;
      return IpGeo(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        city: (data['city'] as String?) ?? 'you',
      );
    } catch (_) {
      return null;
    }
  }
}
