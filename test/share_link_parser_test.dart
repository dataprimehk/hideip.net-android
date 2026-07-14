import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/share_link_parser.dart';
import 'package:hideip_vpn/core/subscription.dart';
import 'package:hideip_vpn/core/singbox_config.dart';

void main() {
  group('vless', () {
    test('basic tls + ws', () {
      final p = ShareLinkParser.parse(
        'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '?type=ws&security=tls&sni=cdn.example.com&path=%2Fws&host=cdn.example.com&flow=#My%20Node',
      )!;
      expect(p.protocol, 'vless');
      expect(p.server, 'example.com');
      expect(p.port, 443);
      expect(p.name, 'My Node');
      final o = p.outbound;
      expect(o['type'], 'vless');
      expect(o['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(o['tls']['enabled'], true);
      expect(o['tls']['server_name'], 'cdn.example.com');
      expect(o['transport']['type'], 'ws');
      expect(o['transport']['path'], '/ws');
      expect(o['transport']['headers']['Host'], 'cdn.example.com');
    });

    test('reality', () {
      final p = ShareLinkParser.parse(
        'vless://uuid-x@1.2.3.4:443?security=reality&pbk=PUBKEY&sid=ab&fp=chrome&sni=apple.com&flow=xtls-rprx-vision#R',
      )!;
      final tls = p.outbound['tls'];
      expect(tls['reality']['enabled'], true);
      expect(tls['reality']['public_key'], 'PUBKEY');
      expect(tls['reality']['short_id'], 'ab');
      expect(tls['utls']['fingerprint'], 'chrome');
      expect(p.outbound['flow'], 'xtls-rprx-vision');
    });
  });

  test('vmess base64 json', () {
    final json = jsonEncode({
      'v': '2',
      'ps': 'VM',
      'add': 'host.example',
      'port': '443',
      'id': 'abc-uuid',
      'aid': '0',
      'net': 'ws',
      'path': '/p',
      'host': 'sni.example',
      'tls': 'tls',
      'scy': 'auto',
    });
    final link = 'vmess://${base64.encode(utf8.encode(json))}';
    final p = ShareLinkParser.parse(link)!;
    expect(p.protocol, 'vmess');
    expect(p.server, 'host.example');
    expect(p.port, 443);
    expect(p.name, 'VM');
    expect(p.outbound['uuid'], 'abc-uuid');
    expect(p.outbound['tls']['enabled'], true);
    expect(p.outbound['transport']['type'], 'ws');
    expect(p.outbound['transport']['path'], '/p');
  });

  group('shadowsocks', () {
    test('SIP002 form', () {
      final creds = base64.encode(utf8.encode('aes-256-gcm:secretpass'));
      final p = ShareLinkParser.parse('ss://$creds@1.2.3.4:8388#SS')!;
      expect(p.protocol, 'shadowsocks');
      expect(p.server, '1.2.3.4');
      expect(p.port, 8388);
      expect(p.outbound['method'], 'aes-256-gcm');
      expect(p.outbound['password'], 'secretpass');
    });

    test('legacy fully-encoded form', () {
      final blob = base64.encode(utf8.encode('chacha20-ietf-poly1305:pw@5.6.7.8:9999'));
      final p = ShareLinkParser.parse('ss://$blob#Legacy')!;
      expect(p.server, '5.6.7.8');
      expect(p.port, 9999);
      expect(p.outbound['method'], 'chacha20-ietf-poly1305');
      expect(p.outbound['password'], 'pw');
    });
  });

  test('trojan tls default', () {
    final p = ShareLinkParser.parse('trojan://mypass@trojan.example:443?sni=trojan.example#T')!;
    expect(p.protocol, 'trojan');
    expect(p.outbound['password'], 'mypass');
    expect(p.outbound['tls']['enabled'], true);
    expect(p.outbound['tls']['server_name'], 'trojan.example');
  });

  test('hysteria2 with obfs', () {
    final p = ShareLinkParser.parse(
      'hysteria2://pw@hy.example:8443?sni=hy.example&obfs=salamander&obfs-password=ob&insecure=1#H',
    )!;
    expect(p.protocol, 'hysteria2');
    expect(p.outbound['password'], 'pw');
    expect(p.outbound['obfs']['type'], 'salamander');
    expect(p.outbound['obfs']['password'], 'ob');
    expect(p.outbound['tls']['insecure'], true);
  });

  test('tuic uuid:password', () {
    final p = ShareLinkParser.parse(
      'tuic://uuid-1:pw-1@tuic.example:443?congestion_control=bbr&alpn=h3&sni=tuic.example#TU',
    )!;
    expect(p.protocol, 'tuic');
    expect(p.outbound['uuid'], 'uuid-1');
    expect(p.outbound['password'], 'pw-1');
    expect(p.outbound['congestion_control'], 'bbr');
    expect(p.outbound['tls']['alpn'], ['h3']);
  });

  group('errors', () {
    test('unsupported scheme throws', () {
      expect(() => ShareLinkParser.parse('ftp://x'), throwsA(isA<ProfileParseException>()));
    });
    test('comment/empty returns null', () {
      expect(ShareLinkParser.parse('   '), isNull);
      expect(ShareLinkParser.parse('# comment'), isNull);
    });
    test('missing port throws', () {
      expect(() => ShareLinkParser.parse('trojan://pw@host.example#x'),
          throwsA(isA<ProfileParseException>()));
    });
  });

  group('subscription', () {
    test('base64 blob of multiple links', () {
      final links = [
        'trojan://pw@a.example:443?sni=a.example#A',
        'ss://${base64.encode(utf8.encode('aes-256-gcm:p'))}@b.example:8388#B',
        '# a comment line',
        'garbage-not-a-link',
      ].join('\n');
      final blob = base64.encode(utf8.encode(links));
      final res = Subscription.parse(blob);
      expect(res.profiles.length, 2);
      expect(res.profiles[0].name, 'A');
      expect(res.profiles[1].name, 'B');
      expect(res.errors.length, 1); // only the garbage line
    });

    test('plain newline links (no base64)', () {
      final res = Subscription.parse('trojan://pw@a.example:443?sni=a.example#A');
      expect(res.profiles.length, 1);
    });
  });

  group('anytls', () {
    test('basic tls', () {
      final p = ShareLinkParser.parse(
        'anytls://mypw@any.example:8443?sni=any.example&insecure=1&alpn=h2#AT',
      )!;
      expect(p.protocol, 'anytls');
      expect(p.server, 'any.example');
      expect(p.port, 8443);
      expect(p.outbound['type'], 'anytls');
      expect(p.outbound['password'], 'mypw');
      expect(p.outbound['tls']['enabled'], true);
      expect(p.outbound['tls']['server_name'], 'any.example');
      expect(p.outbound['tls']['insecure'], true);
      expect(p.outbound['tls']['alpn'], ['h2']);
    });
  });

  group('socks', () {
    test('with credentials', () {
      final p = ShareLinkParser.parse('socks5://user:pass@10.0.0.1:1080#S')!;
      expect(p.protocol, 'socks');
      expect(p.outbound['type'], 'socks');
      expect(p.outbound['server'], '10.0.0.1');
      expect(p.outbound['server_port'], 1080);
      expect(p.outbound['version'], '5');
      expect(p.outbound['username'], 'user');
      expect(p.outbound['password'], 'pass');
    });

    test('without credentials', () {
      final p = ShareLinkParser.parse('socks://127.0.0.1:1080')!;
      expect(p.outbound['type'], 'socks');
      expect(p.outbound.containsKey('username'), false);
    });

    test('with base64-encoded credentials (SIP002-style userinfo)', () {
      // socks://base64("hideip:secretpw")@host:port, emitted by some clients.
      // Regression: the whole blob used to land in `username` with no password,
      // so auth silently failed against any SOCKS server with credentials.
      const userinfo = 'aGlkZWlwOnNlY3JldHB3'; // base64("hideip:secretpw")
      final p = ShareLinkParser.parse('socks://$userinfo@10.0.0.1:1080#S')!;
      expect(p.outbound['username'], 'hideip');
      expect(p.outbound['password'], 'secretpw');
    });
  });

  group('http proxy', () {
    test('plain http with auth', () {
      final p = ShareLinkParser.parse('http://u:p@proxy.example:8080#HP')!;
      expect(p.protocol, 'http');
      expect(p.outbound['type'], 'http');
      expect(p.outbound['username'], 'u');
      expect(p.outbound['password'], 'p');
      expect(p.outbound.containsKey('tls'), false);
    });

    test('https adds tls', () {
      final p = ShareLinkParser.parse('https://proxy.example:8443')!;
      expect(p.outbound['type'], 'http');
      expect(p.outbound['tls']['enabled'], true);
      expect(p.outbound['tls']['server_name'], 'proxy.example');
    });
  });

  group('shadowtls', () {
    test('ss link with shadow-tls plugin builds chained outbounds', () {
      final creds = base64.encode(utf8.encode('aes-256-gcm:sspass'));
      final plugin = Uri.encodeQueryComponent(
        'shadow-tls;host=cloudflare.com;password=stlspw;version=3',
      );
      final p = ShareLinkParser.parse(
        'ss://$creds@1.2.3.4:443?plugin=$plugin#STLS',
      )!;
      expect(p.protocol, 'shadowtls');
      // SS rides on top: it detours into the shadowtls outbound, no direct dial.
      expect(p.outbound['type'], 'shadowsocks');
      expect(p.outbound['detour'], 'shadowtls-out');
      expect(p.outbound.containsKey('server'), false);
      // The shadowtls outbound carries the real server/port + TLS camouflage.
      expect(p.extraOutbounds.length, 1);
      final stls = p.extraOutbounds.first;
      expect(stls['type'], 'shadowtls');
      expect(stls['tag'], 'shadowtls-out');
      expect(stls['server'], '1.2.3.4');
      expect(stls['server_port'], 443);
      expect(stls['version'], 3);
      expect(stls['password'], 'stlspw');
      expect(stls['tls']['server_name'], 'cloudflare.com');
    });

    test('extraOutbounds land in the full config', () {
      final creds = base64.encode(utf8.encode('aes-256-gcm:sspass'));
      final plugin = Uri.encodeQueryComponent('shadow-tls;host=apple.com;version=3');
      final p = ShareLinkParser.parse('ss://$creds@1.2.3.4:443?plugin=$plugin#STLS')!;
      final outs = SingboxConfig.build(p)['outbounds'] as List;
      // proxy (ss) + shadowtls-out + direct
      expect(outs.length, 3);
      expect(outs[0]['tag'], 'proxy');
      expect(outs[1]['tag'], 'shadowtls-out');
      expect(outs[2]['tag'], 'direct');
    });
  });

  test('SingboxConfig builds a full config with proxy final', () {
    final p = ShareLinkParser.parse('trojan://pw@a.example:443?sni=a.example#A')!;
    final cfg = SingboxConfig.build(p);
    expect(cfg['inbounds'][0]['type'], 'tun');
    expect(cfg['inbounds'][0]['stack'], 'system');
    expect(cfg['inbounds'][0]['mtu'], 1280);
    final outs = cfg['outbounds'] as List;
    expect(outs.first['tag'], SingboxConfig.proxyTag);
    expect(outs.first['type'], 'trojan');
    expect(cfg['route']['final'], SingboxConfig.proxyTag);
    // Round-trips to valid JSON
    final json = SingboxConfig.buildJson(p);
    expect(jsonDecode(json)['route']['final'], 'proxy');
  });
}
