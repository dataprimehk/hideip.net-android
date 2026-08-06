import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'catalog.dart';
import 'premium.dart';
import 'profile_store.dart';
import 'proxy_profile.dart';
import 'subscription.dart';

const String provisioningEndpoint = 'https://api.hideip.net:8444';
const String _catalogApiSource = 'https://api.hideip.net:8443/v1/catalog';
const String _catalogDirectSource = '$provisioningEndpoint/v1/catalog';
// TODO(filip): Set the public R2 and Firebase catalog URLs in release dart-defines.
const String _catalogR2Source = String.fromEnvironment('HIDEIP_CATALOG_R2_URL');
const String _catalogFirebaseSource = String.fromEnvironment(
  'HIDEIP_CATALOG_FIREBASE_URL',
);
const List<String> catalogSourceUrls = [
  _catalogApiSource,
  if (_catalogR2Source != '') _catalogR2Source,
  if (_catalogFirebaseSource != '') _catalogFirebaseSource,
  _catalogDirectSource,
];

class PremiumProfileRefresh {
  final List<ProxyProfile>? profiles;
  final int? catalogEpoch;

  const PremiumProfileRefresh({this.profiles, this.catalogEpoch});

  bool get changed => profiles != null;
}

/// Exchanges a verified store purchase for tunnel credentials on hideip.net
/// servers. Anonymous by design: the signed proof is the only identifier the
/// backend ever sees; it re-validates the proof against Apple (iOS JWS) or
/// Google (Android purchase token) before issuing anything.
class ProvisioningService {
  static const String endpoint = provisioningEndpoint;

  final http.Client _client;
  final List<Uri> _catalogSources;
  final String _catalogPublicKey;
  final Duration _catalogTimeout;

  ProvisioningService({
    http.Client? client,
    List<Uri>? catalogSources,
    String? catalogPublicKey,
    Duration? catalogTimeout,
  }) : _client = client ?? http.Client(),
       _catalogSources =
           catalogSources ??
           catalogSourceUrls.map(Uri.parse).toList(growable: false),
       _catalogPublicKey = catalogPublicKey ?? catalogVerificationPublicKey,
       _catalogTimeout = catalogTimeout ?? catalogSourceTimeout;

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
  Future<List<ProxyProfile>?> fetchProfiles(String subscriptionUrl) async =>
      (await refreshProfiles(subscriptionUrl))?.profiles;

  /// Prefer a signed public catalog and locally held UUID. The legacy
  /// subscription remains the final fallback and also bootstraps old installs
  /// whose profile cache predates the separately persisted identity.
  Future<PremiumProfileRefresh?> refreshProfiles(
    String subscriptionUrl, {
    Iterable<ProxyProfile>? cachedProfiles,
  }) async {
    final storedIdentity = await PremiumSub.identity();
    var identity = storedIdentity;
    if (identity != null &&
        !catalogIdentityMatchesSubscription(identity, subscriptionUrl)) {
      identity = null;
    }
    if (identity == null && storedIdentity == null) {
      identity = catalogIdentityFromProfiles(
        subscriptionUrl,
        cachedProfiles ?? await ProfileStore.load(),
      );
      if (identity != null) await PremiumSub.saveIdentity(identity);
    }

    if (identity != null) {
      // TODO(filip): Define an out-of-band epoch signal; the current API cannot reveal an epoch change without fetching a catalog.
      final knownEpoch = await PremiumSub.catalogEpoch();
      final catalog = await CatalogClient(
        client: _client,
        sources: _catalogSources,
        publicKey: _catalogPublicKey,
        timeout: _catalogTimeout,
      ).fetch(minimumEpoch: knownEpoch);
      if (catalog != null) {
        if (catalog.epoch == knownEpoch) {
          return PremiumProfileRefresh(catalogEpoch: catalog.epoch);
        }
        try {
          final profiles = profilesFromCatalog(catalog, identity);
          if (profiles.isNotEmpty) {
            return PremiumProfileRefresh(
              profiles: profiles,
              catalogEpoch: catalog.epoch,
            );
          }
        } catch (_) {
          // A signed but unusable catalog must not displace working profiles.
        }
      }
    }

    return _fetchLegacyProfiles(subscriptionUrl);
  }

  Future<PremiumProfileRefresh?> _fetchLegacyProfiles(
    String subscriptionUrl,
  ) async {
    try {
      final resp = await _client
          .get(Uri.parse(subscriptionUrl), headers: subscriptionHeaders)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 404 || resp.statusCode == 410) {
        return const PremiumProfileRefresh(profiles: []);
      }
      if (resp.statusCode != 200) return null;
      // Everything this URL serves is subscription-managed by definition;
      // the flag (not the name) is what marks a profile as ours, so the
      // backend is free to label servers by plain location.
      final profiles = Subscription.parse(
        resp.body,
      ).profiles.map((p) => p.copyWith(premium: true)).toList();
      final identity = catalogIdentityFromProfiles(subscriptionUrl, profiles);
      if (identity != null) await PremiumSub.saveIdentity(identity);
      return PremiumProfileRefresh(profiles: profiles);
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
  List<ProxyProfile> current,
  List<ProxyProfile> fresh,
) {
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
  static const _kUuid = 'premium_uuid_v1';
  static const _kToken = 'premium_sub_token_v1';
  static const _kCatalogEpoch = 'premium_catalog_epoch_v1';

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
      (await SharedPreferences.getInstance()).setString(
        _kProof,
        jsonEncode(payload.toJson()),
      );

  static Future<CatalogIdentity?> identity() async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = prefs.getString(_kUuid);
    final token = prefs.getString(_kToken);
    if (uuid == null || uuid.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return CatalogIdentity(uuid: uuid, subToken: token);
  }

  static Future<void> saveIdentity(CatalogIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    final changed =
        prefs.getString(_kUuid) != identity.uuid ||
        prefs.getString(_kToken) != identity.subToken;
    await prefs.setString(_kUuid, identity.uuid);
    await prefs.setString(_kToken, identity.subToken);
    if (changed) await prefs.remove(_kCatalogEpoch);
  }

  static Future<int?> catalogEpoch() async =>
      (await SharedPreferences.getInstance()).getInt(_kCatalogEpoch);

  static Future<void> saveCatalogEpoch(int epoch) async =>
      (await SharedPreferences.getInstance()).setInt(_kCatalogEpoch, epoch);

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUrl);
    await prefs.remove(_kProof);
    await prefs.remove(_kUuid);
    await prefs.remove(_kToken);
    await prefs.remove(_kCatalogEpoch);
  }
}
