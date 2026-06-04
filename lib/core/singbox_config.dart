import 'dart:convert';

import 'proxy_profile.dart';

/// Assembles a full sing-box (1.13.x) config JSON from a [ProxyProfile].
///
/// The TUN inbound mirrors the proven Blok 2 test config (stack "system",
/// MTU 1500, auto_route, auto_detect_interface). The chosen profile becomes
/// the "proxy" outbound and route.final points to it; a direct + dns outbound
/// remain so DNS and bypass traffic still work.
class SingboxConfig {
  static const String proxyTag = 'proxy';

  /// Build the config for a single selected [profile]. [logLevel] is "info"
  /// during development; switch to "warn" for release builds.
  static Map<String, dynamic> build(
    ProxyProfile profile, {
    String logLevel = 'warn',
  }) {
    return {
      'log': {'level': logLevel, 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'remote', 'address': 'tls://1.1.1.1'},
          {'tag': 'local', 'address': '223.5.5.5', 'detour': 'direct'},
        ],
        'rules': [
          {'outbound': 'any', 'server': 'local'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          // 1280 is the IPv6 minimum MTU: it is guaranteed to traverse every
          // network (DSL/PPPoE, cellular, double-NAT, restrictive carriers) and
          // leaves ample headroom for any proxy encapsulation (Reality/Vision,
          // ShadowTLS, QUIC). A 1500 tun MTU silently dropped large packets over
          // an encapsulated link: small HTTP passed, HTTPS bursts/speedtests
          // failed. We trade a little per-packet efficiency for "never breaks".
          'mtu': 1280,
          'auto_route': true,
          'strict_route': false,
          'stack': 'system',
        },
      ],
      'outbounds': [
        profile.taggedOutbound(proxyTag),
        ...profile.extraOutbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': proxyTag,
        'rules': [
          // Keep DNS queries and private ranges off the tunnel sanely.
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
        ],
      },
    };
  }

  /// Convenience: build + encode to the JSON string VpnController.start expects.
  static String buildJson(ProxyProfile profile, {String logLevel = 'warn'}) =>
      jsonEncode(build(profile, logLevel: logLevel));
}
