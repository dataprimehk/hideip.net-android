import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'premium.dart';
import 'proxy_profile.dart';
import 'subscription.dart';

/// Exchanges a verified store purchase for tunnel credentials on hideip.net
/// servers. Anonymous by design: the signed proof is the only identifier the
/// backend ever sees; it re-validates the proof against Apple (iOS JWS) or
/// Google (Android purchase token) before issuing anything.
class ProvisioningService {
  static const String endpoint = 'https://api.hideip.net:8444';

  final http.Client _client;
  ProvisioningService({http.Client? client})
      : _client = client ?? http.Client();

  /// Send the signed purchase proof; returns the subscription URL the profiles
  /// live at, or null when the backend rejected or was unreachable. The body
  /// is per-store: iOS keeps `{platform: ios, jws}`; Android sends
  /// `{platform: android, purchase_token, product_id}`.
  Future<String?> provision(PurchasePayload payload) async {
    try {
      final resp = await _client
          .post(
            Uri.parse('$endpoint/v1/provision'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(provisionBody(payload)),
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
          .get(Uri.parse(subscriptionUrl), headers: subscriptionHeaders)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 404 || resp.statusCode == 410) return const [];
      if (resp.statusCode != 200) return null;
      // Everything this URL serves is subscription-managed by definition;
      // the flag (not the name) is what marks a profile as ours, so the
      // backend is free to label servers by plain location.
      return Subscription.parse(resp.body)
          .profiles
          .map((p) => p.copyWith(premium: true))
          .toList();
    } catch (_) {
      return null;
    }
  }
}

/// The `/v1/provision` request body for [payload], per the client/backend
/// contract. iOS is unchanged from the JWS-only era (`{platform, jws}`);
/// Android sends the Play token under snake_case keys the backend expects.
Map<String, dynamic> provisionBody(PurchasePayload payload) =>
    payload.platform == 'android'
        ? {
            'platform': 'android',
            'purchase_token': payload.purchaseToken,
            'product_id': payload.productId,
          }
        : {'platform': 'ios', 'jws': payload.jws};

/// Replace the premium-managed profiles inside [current] with [fresh],
/// leaving every user-imported profile untouched and in place.
List<ProxyProfile> mergePremiumProfiles(
    List<ProxyProfile> current, List<ProxyProfile> fresh) {
  final kept = current.where((p) => !isPremiumProfile(p)).toList();
  return [...kept, ...fresh];
}

/// Whether [p] is managed by the premium subscription (vs user-imported).
bool isPremiumProfile(ProxyProfile p) => p.premium;

/// Persisted pointers for the premium subscription: the subscription URL the
/// backend issued, and the latest signed purchase proof (kept so a provision
/// that failed offline can be retried on a later launch).
class PremiumSub {
  static const _kUrl = 'premium_sub_url_v1';
  // The key predates Android support; the value is now a [PurchasePayload]
  // JSON blob, but a legacy iOS record is a bare JWS string that
  // [PurchasePayload.tryParse] migrates in place.
  static const _kProof = 'premium_jws_v1';

  static Future<String?> url() async =>
      (await SharedPreferences.getInstance()).getString(_kUrl);

  static Future<void> saveUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_kUrl, url);

  /// The persisted purchase proof, migrating a legacy bare-JWS record.
  static Future<PurchasePayload?> proof() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kProof);
    return raw == null ? null : PurchasePayload.tryParse(raw);
  }

  static Future<void> saveProof(PurchasePayload payload) async =>
      (await SharedPreferences.getInstance())
          .setString(_kProof, jsonEncode(payload.toJson()));

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUrl);
    await prefs.remove(_kProof);
  }
}
