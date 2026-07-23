import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'proxy_profile.dart';
import 'subscription.dart';

/// Exchanges a verified store purchase for tunnel credentials on hideip.net
/// servers. Anonymous by design: the signed transaction is the only
/// identifier the backend ever sees; it re-validates the signature against
/// Apple before issuing anything.
class ProvisioningService {
  static const String endpoint = 'https://api.hideip.net:8444';

  /// Name prefix that marks server profiles managed by the subscription, so
  /// refreshes can replace them without touching the user's own imports.
  /// The backend labels every premium profile `hideip.net <location>`.
  static const String profilePrefix = 'hideip.net ';

  final http.Client _client;
  ProvisioningService({http.Client? client})
      : _client = client ?? http.Client();

  /// Send the signed transaction; returns the subscription URL the profiles
  /// live at, or null when the backend rejected or was unreachable.
  Future<String?> provision(String jws) async {
    try {
      final resp = await _client
          .post(
            Uri.parse('$endpoint/v1/provision'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'platform': 'ios', 'jws': jws}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['subscription_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch and parse the premium subscription. Null on any failure so the
  /// caller can keep whatever it already has (transient network trouble must
  /// not drop a working profile); an empty list only on a definitive "gone"
  /// (subscription lapsed server-side).
  Future<List<ProxyProfile>?> fetchProfiles(String subscriptionUrl) async {
    try {
      final resp = await _client
          .get(Uri.parse(subscriptionUrl))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 404 || resp.statusCode == 410) return const [];
      if (resp.statusCode != 200) return null;
      return Subscription.parse(resp.body).profiles;
    } catch (_) {
      return null;
    }
  }
}

/// Replace the premium-managed profiles inside [current] with [fresh],
/// leaving every user-imported profile untouched and in place. Premium
/// profiles are recognized by name prefix.
List<ProxyProfile> mergePremiumProfiles(
    List<ProxyProfile> current, List<ProxyProfile> fresh) {
  final kept = current.where((p) => !isPremiumProfile(p)).toList();
  return [...kept, ...fresh];
}

/// Whether [p] is managed by the premium subscription (vs user-imported).
bool isPremiumProfile(ProxyProfile p) =>
    p.name.startsWith(ProvisioningService.profilePrefix);

/// Persisted pointers for the premium subscription: the subscription URL the
/// backend issued, and the latest signed transaction (kept so a provision
/// that failed offline can be retried on a later launch).
class PremiumSub {
  static const _kUrl = 'premium_sub_url_v1';
  static const _kJws = 'premium_jws_v1';

  static Future<String?> url() async =>
      (await SharedPreferences.getInstance()).getString(_kUrl);

  static Future<void> saveUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_kUrl, url);

  static Future<String?> jws() async =>
      (await SharedPreferences.getInstance()).getString(_kJws);

  static Future<void> saveJws(String jws) async =>
      (await SharedPreferences.getInstance()).setString(_kJws, jws);

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUrl);
    await prefs.remove(_kJws);
  }
}
