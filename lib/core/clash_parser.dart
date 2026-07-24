import 'proxy_profile.dart';

/// Parses a Clash-family subscription body (YAML with a top-level `proxies:`
/// list) into [ProxyProfile]s whose [ProxyProfile.outbound] is a sing-box
/// (1.13.x) outbound object, mirroring the shapes built by [ShareLinkParser].
///
/// Sellers on Clash/Clash.Meta panels serve this format. Each proxy entry is a
/// map with a `type` field (`ss`, `vmess`, `trojan`, `vless`, `hysteria2`,
/// `tuic`). Unsupported entries are surfaced as failures (same behaviour as the
/// share-link parser), never silently dropped.
class ClashParser {
  /// Parse a decoded YAML document (already parsed into Dart maps/lists).
  ///
  /// [doc] is what `loadYaml` returns, converted to plain [Map]/[List] (the
  /// caller does the conversion so this file stays free of the yaml package).
  /// Returns the parsed profiles; parse failures are appended to [errors] as
  /// `name -> reason` strings.
  static List<ProxyProfile> parse(
    Map<dynamic, dynamic> doc, {
    required List<String> errors,
  }) {
    final proxies = doc['proxies'];
    if (proxies is! List) return const [];

    final out = <ProxyProfile>[];
    for (final raw in proxies) {
      if (raw is! Map) {
        errors.add('clash entry -> not a mapping');
        continue;
      }
      final name = _s(raw['name']).isNotEmpty
          ? _s(raw['name'])
          : '${_s(raw['server'])}:${_s(raw['port'])}';
      try {
        final p = _one(raw, name);
        out.add(p);
      } catch (e) {
        errors.add('$name -> ${e is ProfileParseException ? e.message : e}');
      }
    }
    return out;
  }

  static ProxyProfile _one(Map<dynamic, dynamic> m, String name) {
    final type = _s(m['type']).toLowerCase();
    final server = _s(m['server']);
    final port = _int(m['port']);
    if (server.isEmpty || port == 0) {
      throw const ProfileParseException('missing server/port');
    }
    switch (type) {
      case 'ss':
        return _ss(m, name, server, port);
      case 'vmess':
        return _vmess(m, name, server, port);
      case 'trojan':
        return _trojan(m, name, server, port);
      case 'vless':
        return _vless(m, name, server, port);
      case 'hysteria2':
      case 'hy2':
        return _hysteria2(m, name, server, port);
      case 'tuic':
        return _tuic(m, name, server, port);
      default:
        throw ProfileParseException('unsupported clash type "$type"');
    }
  }

  // ss: cipher/password
  static ProxyProfile _ss(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final outbound = <String, dynamic>{
      'type': 'shadowsocks',
      'server': server,
      'server_port': port,
      'method': _s(m['cipher']),
      'password': _s(m['password']),
    };
    return ProxyProfile(
      name: name,
      protocol: 'shadowsocks',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  // vmess: uuid, alterId, cipher, tls, network + ws/grpc/h2 opts
  static ProxyProfile _vmess(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final security = _s(m['cipher']).isEmpty ? 'auto' : _s(m['cipher']);
    final outbound = <String, dynamic>{
      'type': 'vmess',
      'server': server,
      'server_port': port,
      'uuid': _s(m['uuid']),
      'security': security,
      'alter_id': _int(m['alterId']),
    };
    if (_bool(m['tls'])) {
      final sni = _firstNonEmpty([_s(m['servername']), _s(m['sni']), server]);
      final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
      _applyCommonTls(m, tls);
      outbound['tls'] = tls;
    }
    final transport = _clashTransport(m);
    if (transport != null) outbound['transport'] = transport;
    return ProxyProfile(
      name: name,
      protocol: 'vmess',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  // trojan: password, sni, alpn; always TLS
  static ProxyProfile _trojan(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'server': server,
      'server_port': port,
      'password': _s(m['password']),
    };
    final sni = _firstNonEmpty([_s(m['sni']), _s(m['servername']), server]);
    final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
    _applyCommonTls(m, tls);
    outbound['tls'] = tls;
    final transport = _clashTransport(m);
    if (transport != null) outbound['transport'] = transport;
    return ProxyProfile(
      name: name,
      protocol: 'trojan',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  // vless: uuid, flow, tls/reality, network
  static ProxyProfile _vless(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final outbound = <String, dynamic>{
      'type': 'vless',
      'server': server,
      'server_port': port,
      'uuid': _s(m['uuid']),
    };
    final flow = _s(m['flow']);
    if (flow.isNotEmpty) outbound['flow'] = flow;

    // TLS is on when `tls: true` or a reality-opts block is present.
    final reality = m['reality-opts'];
    final wantsTls = _bool(m['tls']) || reality is Map;
    if (wantsTls) {
      final sni = _firstNonEmpty([_s(m['servername']), _s(m['sni']), server]);
      final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
      _applyCommonTls(m, tls);
      if (reality is Map) {
        final pbk = _s(reality['public-key']);
        if (pbk.isNotEmpty) {
          tls['reality'] = <String, dynamic>{
            'enabled': true,
            'public_key': pbk,
            if (_s(reality['short-id']).isNotEmpty)
              'short_id': _s(reality['short-id']),
          };
          // REALITY needs a uTLS fingerprint; default to chrome if absent.
          tls['utls'] ??= {
            'enabled': true,
            'fingerprint':
                _s(m['client-fingerprint']).isNotEmpty ? _s(m['client-fingerprint']) : 'chrome',
          };
        }
      }
      outbound['tls'] = tls;
    }
    final transport = _clashTransport(m);
    if (transport != null) outbound['transport'] = transport;
    return ProxyProfile(
      name: name,
      protocol: 'vless',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  // hysteria2: password, sni, obfs, alpn, skip-cert-verify
  static ProxyProfile _hysteria2(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'server': server,
      'server_port': port,
      'password': _firstNonEmpty([_s(m['password']), _s(m['auth'])]),
    };
    final obfs = _s(m['obfs']);
    if (obfs.isNotEmpty) {
      outbound['obfs'] = <String, dynamic>{
        'type': obfs,
        if (_s(m['obfs-password']).isNotEmpty) 'password': _s(m['obfs-password']),
      };
    }
    final sni = _firstNonEmpty([_s(m['sni']), server]);
    final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
    _applyCommonTls(m, tls);
    outbound['tls'] = tls;
    return ProxyProfile(
      name: name,
      protocol: 'hysteria2',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  // tuic: uuid, password, congestion-controller, alpn, sni
  static ProxyProfile _tuic(
      Map<dynamic, dynamic> m, String name, String server, int port) {
    final outbound = <String, dynamic>{
      'type': 'tuic',
      'server': server,
      'server_port': port,
      'uuid': _s(m['uuid']),
      'password': _s(m['password']),
    };
    final cc = _s(m['congestion-controller']);
    if (cc.isNotEmpty) outbound['congestion_control'] = cc;
    if (_s(m['udp-relay-mode']).isNotEmpty) {
      outbound['udp_relay_mode'] = _s(m['udp-relay-mode']);
    }
    final sni = _firstNonEmpty([_s(m['sni']), server]);
    final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
    _applyCommonTls(m, tls);
    outbound['tls'] = tls;
    return ProxyProfile(
      name: name,
      protocol: 'tuic',
      server: server,
      port: port,
      outbound: outbound,
    );
  }

  /// Common Clash TLS knobs: skip-cert-verify, alpn, client-fingerprint.
  static void _applyCommonTls(Map<dynamic, dynamic> m, Map<String, dynamic> tls) {
    if (_bool(m['skip-cert-verify'])) tls['insecure'] = true;
    final alpn = m['alpn'];
    if (alpn is List && alpn.isNotEmpty) {
      tls['alpn'] = alpn.map((e) => e.toString()).toList();
    } else if (alpn is String && alpn.isNotEmpty) {
      tls['alpn'] = alpn.split(',');
    }
    final fp = _s(m['client-fingerprint']);
    if (fp.isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': fp};
    }
  }

  /// Clash `network:` + ws/grpc/h2 opts -> sing-box transport object.
  static Map<String, dynamic>? _clashTransport(Map<dynamic, dynamic> m) {
    final net = _s(m['network']).toLowerCase();
    switch (net) {
      case 'ws':
        final ws = m['ws-opts'];
        final opts = ws is Map ? ws : const {};
        final headers = opts['headers'];
        final host = headers is Map ? _s(headers['Host']) : '';
        return {
          'type': 'ws',
          if (_s(opts['path']).isNotEmpty) 'path': _s(opts['path']),
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        final g = m['grpc-opts'];
        final opts = g is Map ? g : const {};
        return {
          'type': 'grpc',
          if (_s(opts['grpc-service-name']).isNotEmpty)
            'service_name': _s(opts['grpc-service-name']),
        };
      case 'h2':
        final h = m['h2-opts'];
        final opts = h is Map ? h : const {};
        final host = opts['host'];
        return {
          'type': 'http',
          if (host is List && host.isNotEmpty)
            'host': host.map((e) => e.toString()).toList()
          else if (host is String && host.isNotEmpty)
            'host': host.split(','),
          if (_s(opts['path']).isNotEmpty) 'path': _s(opts['path']),
        };
      default:
        return null;
    }
  }

  static String _s(Object? v) => v == null ? '' : v.toString();

  static int _int(Object? v) {
    if (v is int) return v;
    return int.tryParse(_s(v)) ?? 0;
  }

  static bool _bool(Object? v) {
    if (v is bool) return v;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1';
  }

  static String _firstNonEmpty(List<String> xs) =>
      xs.firstWhere((e) => e.isNotEmpty, orElse: () => '');
}
