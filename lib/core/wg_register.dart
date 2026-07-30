import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'wg_keys.dart';
import 'wg_profile.dart';

/// How a register attempt ended.
enum WgRegisterStatus {
  /// A usable profile came back.
  ok,

  /// The subscription already has its five devices registered; this key is
  /// the sixth. The user has to free a slot before Speed mode works here.
  deviceLimit,

  /// The subscription is unknown or lapsed server-side (404/410). Treated the
  /// same as any other "your premium is gone" signal.
  gone,

  /// The key we sent was malformed (400). Regenerating the identity is the
  /// only sensible recovery, so this is reported separately from a transient
  /// failure even though it should never happen.
  badKey,

  /// Network trouble, a timeout, or a server-side error. Whatever profile is
  /// already cached stays valid; retry on the next refresh.
  transient,
}

/// The outcome of `POST /v1/wg/register`.
class WgRegisterResult {
  final WgRegisterStatus status;
  final WgProfile? profile;

  const WgRegisterResult(this.status, [this.profile]);

  bool get isOk => status == WgRegisterStatus.ok && profile != null;

  /// Whether the caller should drop the cached WireGuard profile: the
  /// subscription is gone, or this device is not allowed a slot.
  bool get shouldForget =>
      status == WgRegisterStatus.gone || status == WgRegisterStatus.deviceLimit;

  /// A short line for the UI, or null when there is nothing worth saying.
  /// Kept plain: a fallback to stealth is not a failure the user must act on.
  String? get message => switch (status) {
        WgRegisterStatus.deviceLimit =>
          'Speed mode is already set up on 5 devices. Turn it off on one of '
              'them to use it here.',
        WgRegisterStatus.badKey => 'Speed mode key was rejected; try again.',
        WgRegisterStatus.ok ||
        WgRegisterStatus.gone ||
        WgRegisterStatus.transient =>
          null,
      };
}

/// Registers this device's WireGuard public key with the provisioning backend
/// and caches the profile it returns.
///
/// The call is idempotent by contract: the same (subscription token, public
/// key) pair always gets the same tunnel address back, so the app re-runs it on
/// every subscription refresh. That keeps the peer alive on newly added servers
/// without needing a separate "did anything change" signal.
class WgRegisterService {
  /// Same host as the rest of provisioning.
  static const String endpoint = 'https://api.hideip.net:8444';

  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;
  final String _base;

  WgRegisterService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? endpoint;

  /// Register [publicKey] against [subToken].
  ///
  /// Only the public key is ever sent; the private half stays in
  /// [WgIdentity]. Never throws: every failure maps to a
  /// [WgRegisterStatus] so the caller can decide between falling back and
  /// keeping what it has.
  Future<WgRegisterResult> register({
    required String subToken,
    required String publicKey,
  }) async {
    if (!WgKeys.isValidKey(publicKey)) {
      return const WgRegisterResult(WgRegisterStatus.badKey);
    }
    try {
      final resp = await _client
          .post(
            Uri.parse('$_base/v1/wg/register'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(
                registerBody(subToken: subToken, publicKey: publicKey)),
          )
          .timeout(_timeout);
      switch (resp.statusCode) {
        case 200:
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final profile = WgProfile.tryParse(body);
          return profile == null
              ? const WgRegisterResult(WgRegisterStatus.transient)
              : WgRegisterResult(WgRegisterStatus.ok, profile);
        case 400:
          return const WgRegisterResult(WgRegisterStatus.badKey);
        case 404:
        case 410:
          return const WgRegisterResult(WgRegisterStatus.gone);
        case 409:
          return const WgRegisterResult(WgRegisterStatus.deviceLimit);
        default:
          return const WgRegisterResult(WgRegisterStatus.transient);
      }
    } catch (_) {
      return const WgRegisterResult(WgRegisterStatus.transient);
    }
  }

  /// Release this device's peer slot. Idempotent by contract, and best effort
  /// here: a failed revoke costs a slot until the subscription lapses, which
  /// is not worth blocking the UI over.
  Future<bool> revoke({
    required String subToken,
    required String publicKey,
  }) async {
    try {
      final resp = await _client
          .post(
            Uri.parse('$_base/v1/wg/revoke'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(
                registerBody(subToken: subToken, publicKey: publicKey)),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// The request body both WireGuard endpoints take, per the contract.
Map<String, dynamic> registerBody({
  required String subToken,
  required String publicKey,
}) =>
    {'sub_token': subToken, 'client_pubkey': publicKey};

/// Pulls the subscription token out of the subscription URL the backend issued
/// (`https://api.hideip.net:8444/v1/sub/<token>`). The WireGuard endpoints take
/// the bare token, not the URL, and the app only ever persists the URL.
String? subTokenFromUrl(String? subscriptionUrl) {
  if (subscriptionUrl == null || subscriptionUrl.isEmpty) return null;
  final uri = Uri.tryParse(subscriptionUrl);
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) return null;
  if (segments[segments.length - 2] != 'sub') return null;
  final token = segments.last;
  return token.isEmpty ? null : token;
}

/// Local cache of the issued WireGuard profile, so Speed mode can come up on
/// launch without waiting for a network round trip.
class WgProfileStore {
  static const _kProfile = 'wg_profile_v1';

  static Future<WgProfile?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kProfile);
    return raw == null ? null : WgProfile.decode(raw);
  }

  static Future<void> save(WgProfile profile) async =>
      (await SharedPreferences.getInstance())
          .setString(_kProfile, WgProfile.encode(profile));

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_kProfile);
}
