import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/wg_profile.dart';
import 'package:hideip_vpn/core/wg_singbox.dart';

final _privateKey = base64.encode(List<int>.filled(32, 9));

const _server = WgServer(
  serverId: 'srv_a1b2c3d4',
  label: 'Amsterdam',
  countryCode: 'NL',
  city: 'Amsterdam',
  host: '1.2.3.4',
  port: 51820,
  serverPubkey: 'c2VydmVycHVia2V5MDAwMDAwMDAwMDAwMDAwMDAwMDA=',
);

WgProfile _profile({int mtu = 1280}) => WgProfile(
      address: '10.66.0.10/32',
      dns: const ['1.1.1.1', '1.0.0.1'],
      mtu: mtu,
      persistentKeepalive: 25,
      allowedIps: const ['0.0.0.0/0', '::/0'],
      servers: const [_server],
      fetchedAt: DateTime.utc(2026, 7, 30),
    );

Map<String, dynamic> _build({int mtu = 1280}) => WgSingboxConfig.build(
      profile: _profile(mtu: mtu),
      server: _server,
      privateKey: _privateKey,
      tunStack: 'system',
    );

void main() {
  group('endpoint mapping', () {
    test('WireGuard is an endpoint, not an outbound', () {
      // sing-box 1.11 moved WireGuard into the top-level `endpoints` array;
      // the engine here is libbox 1.13.12, so the legacy outbound form would
      // simply be rejected.
      final cfg = _build();
      expect(cfg['endpoints'], isA<List>());
      final ep = (cfg['endpoints'] as List).single as Map<String, dynamic>;
      expect(ep['type'], 'wireguard');
      expect(ep['tag'], WgSingboxConfig.endpointTag);
      // No wireguard outbound left behind.
      final outbounds = (cfg['outbounds'] as List).cast<Map>();
      expect(outbounds.any((o) => o['type'] == 'wireguard'), isFalse);
      expect(outbounds.single['type'], 'direct');
    });

    test('carries the assigned address, private key and peer', () {
      final ep =
          (_build()['endpoints'] as List).single as Map<String, dynamic>;
      expect(ep['address'], ['10.66.0.10/32']);
      expect(ep['private_key'], _privateKey);
      // Userspace: a system interface would collide with the TUN the platform
      // already handed the core, and needs privileges an app does not have.
      expect(ep['system'], isFalse);

      final peer = (ep['peers'] as List).single as Map<String, dynamic>;
      expect(peer['address'], '1.2.3.4');
      expect(peer['port'], 51820);
      expect(peer['public_key'], _server.serverPubkey);
      expect(peer['allowed_ips'], ['0.0.0.0/0', '::/0']);
      expect(peer['persistent_keepalive_interval'], 25);
    });

    test('MTU is 1280 on both the endpoint and the TUN inbound', () {
      final cfg = _build();
      final ep = (cfg['endpoints'] as List).single as Map<String, dynamic>;
      final tun = (cfg['inbounds'] as List).single as Map<String, dynamic>;
      expect(ep['mtu'], 1280);
      expect(tun['mtu'], 1280);
    });

    test('a larger backend MTU is clamped back to 1280', () {
      // Never take an MTU on trust: 1420 is a perfectly ordinary WireGuard
      // value that still breaks large packets once it rides inside a mobile
      // or PPPoE link.
      final ep =
          (_build(mtu: 1420)['endpoints'] as List).single as Map<String, dynamic>;
      expect(ep['mtu'], 1280);
    });

    test('route.final points at the endpoint tag', () {
      final route = _build()['route'] as Map<String, dynamic>;
      expect(route['final'], WgSingboxConfig.endpointTag);
      expect(route['auto_detect_interface'], isTrue);
    });

    test('DNS is resolved through the tunnel, not around it', () {
      final dns = _build()['dns'] as Map<String, dynamic>;
      final servers = (dns['servers'] as List).cast<Map>();
      final remote = servers.first;
      expect(remote['address'], '1.1.1.1');
      expect(remote['detour'], WgSingboxConfig.endpointTag);
      expect(dns['final'], 'wg-dns-0');
    });

    test('the kill switch drives strict_route on the TUN', () {
      final on = WgSingboxConfig.build(
        profile: _profile(),
        server: _server,
        privateKey: _privateKey,
        tunStack: 'system',
        killSwitch: true,
      );
      final tun = (on['inbounds'] as List).single as Map<String, dynamic>;
      expect(tun['strict_route'], isTrue);
      final off = (_build()['inbounds'] as List).single as Map<String, dynamic>;
      expect(off['strict_route'], isFalse);
    });

    test('the gvisor stack can be pinned for iOS', () {
      final cfg = WgSingboxConfig.build(
        profile: _profile(),
        server: _server,
        privateKey: _privateKey,
        tunStack: 'gvisor',
      );
      final tun = (cfg['inbounds'] as List).single as Map<String, dynamic>;
      expect(tun['stack'], 'gvisor');
    });

    test('buildJson emits parsable JSON with the same shape', () {
      final raw = WgSingboxConfig.buildJson(
        profile: _profile(),
        server: _server,
        privateKey: _privateKey,
        tunStack: 'system',
      );
      final cfg = jsonDecode(raw) as Map<String, dynamic>;
      final ep = (cfg['endpoints'] as List).single as Map<String, dynamic>;
      expect(ep['type'], 'wireguard');
      expect(ep['mtu'], 1280);
    });

    test('the log level defaults to warn, never a file output', () {
      // A box.log file output is a debug-only affordance; release builds must
      // not write one.
      final log = _build()['log'] as Map<String, dynamic>;
      expect(log['level'], 'warn');
      expect(log.containsKey('output'), isFalse);
    });

    test('usableKey rejects a key the core would choke on', () {
      expect(WgSingboxConfig.usableKey(_privateKey), isTrue);
      expect(WgSingboxConfig.usableKey('too-short'), isFalse);
      expect(WgSingboxConfig.usableKey(''), isFalse);
    });
  });
}
