import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'safe_http.dart';

/// A located public address: coordinates plus whatever text the database knew.
///
/// [lat], [lon] and [city] stay non-nullable because the map draws with them
/// unconditionally. The textual fields are optional: the databases answer
/// every one of them with null when a range is unknown to them.
class IpGeo {
  final double lat;
  final double lon;
  final String city;

  /// ISO 3166-1 alpha-2, upper case, or null when unknown.
  final String? cc;
  final String? country;
  final String? isp;

  const IpGeo({
    required this.lat,
    required this.lon,
    required this.city,
    this.cc,
    this.country,
    this.isp,
  });
}

/// One answer from the lookup endpoint.
///
/// The textual location fields live here as well as on [geo] on purpose. The
/// endpoint answers the country, the city and the network operator out of
/// separate databases from the coordinates, so a range can be known by name
/// and unknown by position. [geo] stays null without usable coordinates, since
/// its only consumer is the map, but [cc], [country] and [isp] survive that
/// case and remain readable here.
class IpLookupData {
  final String ip;
  final IpGeo? geo;
  final String? cc;
  final String? country;
  final String? isp;

  const IpLookupData({
    required this.ip,
    this.geo,
    this.cc,
    this.country,
    this.isp,
  });
}

/// Public-IP proof comes from hideip.net's own endpoint. A phone cannot know
/// its public address without asking something past the NAT, and asking a
/// third party told that party every user's real address and the moment each
/// tunnel came up. Asking our own host gives nothing away that provisioning,
/// the subscription fetch and the catalog read did not already give it.
///
/// The location beside the address is answered by that same host out of local
/// databases, so it costs no extra request and reaches no third party either.
class IpLookup {
  static const _endpoint = String.fromEnvironment(
    'HIDEIP_IP_ENDPOINT',
    defaultValue: 'https://api.hideip.net:8444/v1/ip',
  );
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
      return const IpGeo(
        lat: 52.37,
        lon: 4.9,
        city: 'Amsterdam',
        cc: 'NL',
        country: 'Netherlands',
        isp: 'Example ISP',
      );
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

/// Free text off the wire, or null when it is empty or implausibly long.
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 128) return null;
  return trimmed;
}

/// A country code only counts as one when it is exactly two ASCII letters.
String? _countryCode(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.length != 2) return null;
  for (final unit in trimmed.codeUnits) {
    final isUpper = unit >= 0x41 && unit <= 0x5a;
    final isLower = unit >= 0x61 && unit <= 0x7a;
    if (!isUpper && !isLower) return null;
  }
  return trimmed.toUpperCase();
}

IpLookupData? parseIpLookupBody(String body) {
  try {
    final value = jsonDecode(body) as Map<String, dynamic>;
    final ip = (value['ip'] as String?)?.trim() ?? '';
    if (InternetAddress.tryParse(ip) == null) return null;
    final cc = _countryCode(value['cc']);
    final country = _text(value['country']);
    final isp = _text(value['isp']);
    final lat = value['latitude'];
    final lon = value['longitude'];
    IpGeo? geo;
    if (lat is num &&
        lon is num &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180) {
      geo = IpGeo(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        city: _text(value['city']) ?? 'you',
        cc: cc,
        country: country,
        isp: isp,
      );
    }
    return IpLookupData(ip: ip, geo: geo, cc: cc, country: country, isp: isp);
  } catch (_) {
    return null;
  }
}
