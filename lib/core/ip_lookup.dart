import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'safe_http.dart';

class IpGeo {
  final double lat;
  final double lon;
  final String city;
  const IpGeo({required this.lat, required this.lon, required this.city});
}

class IpLookupData {
  final String ip;
  final IpGeo? geo;
  const IpLookupData({required this.ip, this.geo});
}

/// Public-IP proof is disabled by default until a first-party endpoint is
/// supplied at build time. No third party learns that this app launched, which
/// server a user imported, or when the tunnel was toggled.
class IpLookup {
  static const _endpoint = String.fromEnvironment('HIDEIP_IP_ENDPOINT');
  static const _timeout = Duration(seconds: 8);
  static const _shotIp = String.fromEnvironment('HIP_SHOT_IP');

  static IpLookupData? _last;
  static DateTime? _lastAt;

  static Future<String?> current() async {
    if (_shotIp.isNotEmpty) return _shotIp;
    return (await _fetch())?.ip;
  }

  /// Server geolocation used to call a third party for every unnamed import.
  /// It stays local/unknown until hideip.net offers a privacy-reviewed batch
  /// endpoint or an on-device database.
  static Future<String?> countryFor(String _) async => null;

  static Future<IpGeo?> locate() async {
    if (_shotIp.isNotEmpty) {
      return const IpGeo(lat: 52.37, lon: 4.9, city: 'Amsterdam');
    }
    return (await _fetch())?.geo;
  }

  static Future<IpLookupData?> _fetch() async {
    final heldAt = _lastAt;
    if (_last != null &&
        heldAt != null &&
        DateTime.now().difference(heldAt) < const Duration(seconds: 10)) {
      return _last;
    }
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || !isAllowedIpEndpoint(uri)) return null;
    try {
      final response = await SafeHttpFetcher().get(
        uri,
        maxBytes: 16 * 1024,
        timeout: _timeout,
      );
      if (response.statusCode != 200) return null;
      final parsed = parseIpLookupBody(response.body);
      if (parsed != null) {
        _last = parsed;
        _lastAt = DateTime.now();
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }
}

bool isAllowedIpEndpoint(Uri uri) {
  final host = uri.host.toLowerCase();
  return uri.scheme.toLowerCase() == 'https' &&
      uri.userInfo.isEmpty &&
      (host == 'hideip.net' || host.endsWith('.hideip.net'));
}

IpLookupData? parseIpLookupBody(String body) {
  try {
    final value = jsonDecode(body) as Map<String, dynamic>;
    final ip = (value['ip'] as String?)?.trim() ?? '';
    if (InternetAddress.tryParse(ip) == null) return null;
    final lat = value['latitude'];
    final lon = value['longitude'];
    IpGeo? geo;
    if (lat is num &&
        lon is num &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180) {
      final rawCity = (value['city'] as String?)?.trim() ?? '';
      geo = IpGeo(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        city: rawCity.isEmpty || rawCity.length > 128 ? 'you' : rawCity,
      );
    }
    return IpLookupData(ip: ip, geo: geo);
  } catch (_) {
    return null;
  }
}
