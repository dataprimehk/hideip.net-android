import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/config_redaction.dart';
import 'package:hideip_vpn/core/import_payload.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/share_link_parser.dart';
import 'package:hideip_vpn/core/singbox_config.dart';
import 'package:hideip_vpn/core/wg_import.dart';
import 'package:hideip_vpn/core/wg_profile.dart' show wgMtu;

/// Valid 32-byte base64 keys. Content is irrelevant, shape is not: the parser
/// checks every key the way the core will.
const _priv = 'aGlkZWlwLm5ldCB0ZXN0IHByaXZhdGUga2V5IDAwMDE=';
const _pub = 'aGlkZWlwLm5ldCB0ZXN0IHB1YmxpYyBrZXkgMDAwMDE=';
const _psk = 'aGlkZWlwLm5ldCB0ZXN0IHByZXNoYXJlZCBrZXkgMDE=';

String _conf({
  String address = '10.66.0.10/32',
  String allowedIps = '0.0.0.0/0, ::/0',
  String mtu = '1420',
  String endpoint = 'wg.example.com:51820',
  String? preamble,
}) =>
    '''
${preamble ?? ''}[Interface]
PrivateKey = $_priv
Address = $address
DNS = 1.1.1.1, 1.0.0.1
MTU = $mtu

[Peer]
PublicKey = $_pub
AllowedIPs = $allowedIps
Endpoint = $endpoint
PersistentKeepalive = 25
''';

void main() {
  group('WireGuard config file', () {
    test('parses into an endpoint profile', () {
      final p = WgImport.parseConfig(_conf());

      expect(p.protocol, 'wireguard');
      expect(p.server, 'wg.example.com');
      expect(p.port, 51820);
      expect(p.isEndpoint, isTrue);
      expect(p.outbound['type'], 'wireguard');
      expect(p.outbound['system'], false);
      expect(p.outbound['address'], ['10.66.0.10/32']);
      expect(p.outbound['private_key'], _priv);

      final peers = (p.outbound['peers'] as List).cast<Map<String, dynamic>>();
      expect(peers, hasLength(1));
      expect(peers.single['address'], 'wg.example.com');
      expect(peers.single['port'], 51820);
      expect(peers.single['public_key'], _pub);
      expect(peers.single['allowed_ips'], ['0.0.0.0/0', '::/0']);
      expect(peers.single['persistent_keepalive_interval'], 25);
      expect(peers.single.containsKey('pre_shared_key'), isFalse);
    });

    test('caps the MTU the file declares', () {
      // 1420 is what almost every generator writes, and it is the value that
      // silently drops large packets once the tunnel is encapsulated.
      expect(WgImport.parseConfig(_conf()).outbound['mtu'], wgMtu);
      expect(WgImport.parseConfig(_conf(mtu: '1280')).outbound['mtu'], 1280);
      expect(WgImport.parseConfig(_conf(mtu: '1200')).outbound['mtu'], 1200);
      expect(WgImport.parseConfig(_conf(mtu: '')).outbound['mtu'], wgMtu);
    });

    test('keeps a pre-shared key and rejects a malformed one', () {
      final withPsk = _conf().replaceFirst(
          'PublicKey = $_pub', 'PublicKey = $_pub\nPresharedKey = $_psk');
      final peers =
          (WgImport.parseConfig(withPsk).outbound['peers'] as List).cast<Map>();
      expect(peers.single['pre_shared_key'], _psk);

      final bad = _conf().replaceFirst(
          'PublicKey = $_pub', 'PublicKey = $_pub\nPresharedKey = nope');
      expect(() => WgImport.parseConfig(bad),
          throwsA(isA<ProfileParseException>()));
    });

    test('takes several addresses and several peers', () {
      final two = '''
${_conf(address: '10.66.0.10/32, fd00::a/128')}
[Peer]
PublicKey = $_pub
AllowedIPs = 0.0.0.0/0
Endpoint = backup.example.com:51821
''';
      final p = WgImport.parseConfig(two);
      expect(p.outbound['address'], ['10.66.0.10/32', 'fd00::a/128']);
      expect(p.outbound['peers'], hasLength(2));
      // The first usable peer names the profile's server.
      expect(p.server, 'wg.example.com');
    });

    test('skips a peer with no Endpoint instead of failing', () {
      final withDialer = '''
${_conf()}
[Peer]
PublicKey = $_pub
AllowedIPs = 10.66.0.20/32
''';
      expect(WgImport.parseConfig(withDialer).outbound['peers'], hasLength(1));
    });

    test('refuses a split-tunnel config rather than building a dead tunnel',
        () {
      expect(
        () => WgImport.parseConfig(_conf(allowedIps: '10.66.0.0/24')),
        throwsA(isA<ProfileParseException>().having(
            (e) => e.message, 'message', contains('AllowedIPs'))),
      );
    });

    test('refuses missing or malformed required fields', () {
      expect(() => WgImport.parseConfig(_conf(address: '')),
          throwsA(isA<ProfileParseException>()));
      expect(
          () => WgImport.parseConfig(
              _conf().replaceFirst('PrivateKey = $_priv', 'PrivateKey = x')),
          throwsA(isA<ProfileParseException>()));
      expect(
          () => WgImport.parseConfig(
              _conf().replaceFirst('PublicKey = $_pub', 'PublicKey = x')),
          throwsA(isA<ProfileParseException>()));
      expect(() => WgImport.parseConfig(_conf(endpoint: 'wg.example.com')),
          throwsA(isA<ProfileParseException>()));
      expect(() => WgImport.parseConfig('[Interface]\nPrivateKey = $_priv\n'),
          throwsA(isA<ProfileParseException>()));
    });

    test('handles IPv6 endpoints and trailing comments', () {
      final p = WgImport.parseConfig(
          _conf(endpoint: '[2001:db8::1]:51820 # main exit'));
      expect(p.server, '2001:db8::1');
      expect(p.port, 51820);
    });

    test('takes a name from a leading comment, else names it after the host',
        () {
      expect(WgImport.parseConfig(_conf(preamble: '# Name = Berlin\n')).name,
          'Berlin');
      expect(WgImport.parseConfig(_conf(preamble: '# Berlin\n')).name, 'Berlin');
      expect(WgImport.parseConfig(_conf()).name, 'WireGuard wg.example.com');
      // A banner is not a label.
      expect(
        WgImport.parseConfig(
                _conf(preamble: '# Generated file, do not edit by hand ever\n'))
            .name,
        'WireGuard wg.example.com',
      );
    });
  });

  group('wireguard:// link', () {
    String link({String query = '', String frag = ''}) =>
        'wireguard://${Uri.encodeComponent(_priv)}@wg.example.com:51820'
        '?publickey=${Uri.encodeComponent(_pub)}&address=10.66.0.10/32$query$frag';

    test('parses with the key in the userinfo', () {
      final p = ShareLinkParser.parse(link(frag: '#Berlin'))!;
      expect(p.protocol, 'wireguard');
      expect(p.isEndpoint, isTrue);
      expect(p.name, 'Berlin');
      expect(p.outbound['private_key'], _priv);
      final peer = (p.outbound['peers'] as List).cast<Map>().single;
      expect(peer['public_key'], _pub);
      // A link that says nothing about routes means the whole internet.
      expect(peer['allowed_ips'], ['0.0.0.0/0', '::/0']);
    });

    test('parses with the key as a query parameter', () {
      final p = ShareLinkParser.parse(
          'wg://wg.example.com:51820?privatekey=${Uri.encodeComponent(_priv)}'
          '&publickey=${Uri.encodeComponent(_pub)}&address=10.66.0.10/32')!;
      expect(p.outbound['private_key'], _priv);
    });

    test('refuses a link missing what a tunnel needs', () {
      expect(
          () => ShareLinkParser.parse(
              'wireguard://wg.example.com:51820?address=10.66.0.10/32'),
          throwsA(isA<ProfileParseException>()));
      expect(
          () => ShareLinkParser.parse(link().replaceFirst(
              '&address=10.66.0.10/32', '')),
          throwsA(isA<ProfileParseException>()));
    });
  });

  group('wiring', () {
    test('the parser recognizes a whole file, comment first', () {
      final p = ShareLinkParser.parse(_conf(preamble: '# Berlin\n'))!;
      expect(p.protocol, 'wireguard');
    });

    test('a single subscription line never looks like a config', () {
      expect(WgImport.looksLikeConfig('[Interface]'), isFalse);
      expect(WgImport.looksLikeConfig('vless://u@h:443#a'), isFalse);
      expect(ShareLinkParser.parse('# just a comment'), isNull);
    });

    test('the importer classifies a config as one server, not a body', () {
      expect(classifyImportPayload(_conf()),
          const ImportPayload(ImportPayloadKind.shareLink, 'wireguard'));
    });

    test('wireguard is on the shared whitelist', () {
      expect(ShareLinkParser.supportedSchemes, contains('wireguard'));
      expect(ShareLinkParser.supportedSchemes, contains('wg'));
    });

    test('the built config puts the tunnel in endpoints, not outbounds', () {
      final config = SingboxConfig.build(WgImport.parseConfig(_conf()),
          tunStack: 'system');

      final endpoints = config['endpoints'] as List;
      expect(endpoints, hasLength(1));
      expect((endpoints.single as Map)['tag'], SingboxConfig.proxyTag);
      expect((endpoints.single as Map)['type'], 'wireguard');

      final outbounds = (config['outbounds'] as List).cast<Map>();
      expect(outbounds.map((o) => o['type']), ['direct']);
      expect((config['route'] as Map)['final'], SingboxConfig.proxyTag);
      // Still valid JSON for the core.
      expect(() => jsonEncode(config), returnsNormally);
    });

    test('the private and pre-shared keys never survive redaction', () {
      // An imported config carries a key the user cannot rotate as easily as
      // a provisioned one, so the copy action must not hand it out.
      final withPsk = _conf().replaceFirst(
          'PublicKey = $_pub', 'PublicKey = $_pub\nPresharedKey = $_psk');
      final redacted =
          redactConfig(WgImport.parseConfig(withPsk).outbound) as Map;

      expect(redacted['private_key'], '[REDACTED]');
      final peer = (redacted['peers'] as List).cast<Map>().single;
      expect(peer['pre_shared_key'], '[REDACTED]');
      // The peer's public key is not a secret and support needs it.
      expect(peer['public_key'], _pub);
      expect(jsonEncode(redacted), isNot(contains(_priv)));
      expect(jsonEncode(redacted), isNot(contains(_psk)));
    });

    test('a stealth profile still has no endpoints key', () {
      final vless = ShareLinkParser.parse(
          'vless://11111111-2222-3333-4444-555555555555@h.example.com:443'
          '?type=tcp&security=tls#x')!;
      final config = SingboxConfig.build(vless, tunStack: 'system');
      expect(config.containsKey('endpoints'), isFalse);
      expect((config['outbounds'] as List).cast<Map>().first['tag'],
          SingboxConfig.proxyTag);
    });
  });
}
