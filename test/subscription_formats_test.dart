import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/subscription.dart';

void main() {
  group('Clash YAML subscription', () {
    const yaml = '''
proxies:
  - name: SS-Node
    type: ss
    server: ss.example.com
    port: 8388
    cipher: aes-256-gcm
    password: ss-pass
  - name: VMess-Node
    type: vmess
    server: vm.example.com
    port: 443
    uuid: vm-uuid-1
    alterId: 0
    cipher: auto
    tls: true
    servername: sni.example.com
    network: ws
    ws-opts:
      path: /wspath
      headers:
        Host: host.example.com
  - name: Trojan-Node
    type: trojan
    server: tj.example.com
    port: 443
    password: tj-pass
    sni: tj-sni.example.com
    skip-cert-verify: true
  - name: VLESS-Reality
    type: vless
    server: vl.example.com
    port: 443
    uuid: vl-uuid-2
    flow: xtls-rprx-vision
    tls: true
    servername: apple.com
    client-fingerprint: chrome
    reality-opts:
      public-key: PUBKEY
      short-id: ab12
  - name: Unknown-Node
    type: wireguard
    server: wg.example.com
    port: 51820
    private-key: xxx
''';

    test('parses ss/vmess/trojan/vless, counts unsupported as a failure', () {
      final res = Subscription.parse(yaml);
      expect(res.profiles.length, 4);
      // Unsupported wireguard entry becomes a failure with a reason.
      expect(res.errors.length, 1);
      expect(res.errors.first, contains('Unknown-Node'));
      expect(res.errors.first, contains('wireguard'));

      final byName = {for (final p in res.profiles) p.name: p};

      final ss = byName['SS-Node']!;
      expect(ss.protocol, 'shadowsocks');
      expect(ss.server, 'ss.example.com');
      expect(ss.port, 8388);
      expect(ss.outbound['method'], 'aes-256-gcm');
      expect(ss.outbound['password'], 'ss-pass');

      final vm = byName['VMess-Node']!;
      expect(vm.protocol, 'vmess');
      expect(vm.outbound['uuid'], 'vm-uuid-1');
      expect(vm.outbound['alter_id'], 0);
      expect(vm.outbound['tls']['enabled'], true);
      expect(vm.outbound['tls']['server_name'], 'sni.example.com');
      expect(vm.outbound['transport']['type'], 'ws');
      expect(vm.outbound['transport']['path'], '/wspath');
      expect(vm.outbound['transport']['headers']['Host'], 'host.example.com');

      final tj = byName['Trojan-Node']!;
      expect(tj.protocol, 'trojan');
      expect(tj.outbound['password'], 'tj-pass');
      expect(tj.outbound['tls']['enabled'], true);
      expect(tj.outbound['tls']['server_name'], 'tj-sni.example.com');
      expect(tj.outbound['tls']['insecure'], true);

      final vl = byName['VLESS-Reality']!;
      expect(vl.protocol, 'vless');
      expect(vl.outbound['uuid'], 'vl-uuid-2');
      expect(vl.outbound['flow'], 'xtls-rprx-vision');
      expect(vl.outbound['tls']['server_name'], 'apple.com');
      expect(vl.outbound['tls']['reality']['enabled'], true);
      expect(vl.outbound['tls']['reality']['public_key'], 'PUBKEY');
      expect(vl.outbound['tls']['reality']['short_id'], 'ab12');
      expect(vl.outbound['tls']['utls']['fingerprint'], 'chrome');
    });
  });

  group('sing-box JSON subscription', () {
    test('parses supported outbounds, ignores direct/dns, strips tag', () {
      final body = jsonEncode({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'vless-out',
            'server': 'v.example.com',
            'server_port': 443,
            'uuid': 'json-uuid',
            'tls': {'enabled': true, 'server_name': 'v.example.com'},
          },
          {
            'type': 'shadowsocks',
            'tag': 'ss-out',
            'server': 's.example.com',
            'server_port': 8388,
            'method': 'aes-256-gcm',
            'password': 'p',
          },
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'dns', 'tag': 'dns-out'},
        ],
      });

      final res = Subscription.parse(body);
      expect(res.errors, isEmpty);
      expect(res.profiles.length, 2);

      final byName = {for (final p in res.profiles) p.name: p};

      final vless = byName['vless-out']!;
      expect(vless.protocol, 'vless');
      expect(vless.server, 'v.example.com');
      expect(vless.port, 443);
      expect(vless.outbound['uuid'], 'json-uuid');
      // tag re-assigned at build time, so it must be stripped here.
      expect(vless.outbound.containsKey('tag'), isFalse);

      final ss = byName['ss-out']!;
      expect(ss.protocol, 'shadowsocks');
      expect(ss.outbound.containsKey('tag'), isFalse);
      expect(ss.outbound['method'], 'aes-256-gcm');
    });

    test('shadowtls chain carries referenced outbound in extraOutbounds', () {
      final body = jsonEncode({
        'outbounds': [
          {
            'type': 'shadowsocks',
            'tag': 'ss-out',
            'method': 'aes-256-gcm',
            'password': 'p',
            'detour': 'shadowtls-out',
          },
          {
            'type': 'shadowtls',
            'tag': 'shadowtls-out',
            'server': 'stls.example.com',
            'server_port': 443,
            'version': 3,
            'password': 'stls-pass',
            'tls': {'enabled': true, 'server_name': 'cloudflare.com'},
          },
        ],
      });

      final res = Subscription.parse(body);
      // The chain yields ONE profile: the shadowtls half is a chain target,
      // not a usable server, so it rides along in extraOutbounds only.
      expect(res.profiles.length, 1);
      final ss = res.profiles.firstWhere((p) => p.name == 'ss-out');
      expect(ss.server, 'stls.example.com');
      expect(ss.port, 443);
      expect(ss.outbound['detour'], 'shadowtls-out');
      expect(ss.extraOutbounds.length, 1);
      expect(ss.extraOutbounds.first['tag'], 'shadowtls-out');
      expect(ss.extraOutbounds.first['type'], 'shadowtls');
    });
  });

  group('existing formats still work', () {
    test('plain link list', () {
      final res = Subscription.parse(
        'vless://uuid-a@a.example.com:443?security=tls#A\n'
        'trojan://pass@b.example.com:443#B',
      );
      expect(res.profiles.length, 2);
      expect(res.errors, isEmpty);
    });

    test('base64 blob', () {
      final links = 'vless://uuid-a@a.example.com:443?security=tls#A\n'
          'trojan://pass@b.example.com:443#B';
      final body = base64.encode(utf8.encode(links));
      final res = Subscription.parse(body);
      expect(res.profiles.length, 2);
    });
  });
}
