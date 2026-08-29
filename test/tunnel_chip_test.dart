import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/core/location.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/wg_speed_mode.dart';

Location _location({
  String name = 'de-fra-reality-01',
  String protocol = 'vless',
  Map<String, dynamic> outbound = const {
    'type': 'vless',
    'tls': {
      'reality': {'enabled': true}
    },
  },
}) =>
    Location.derive(
      ProxyProfile(
        name: name,
        protocol: protocol,
        server: '198.51.100.24',
        port: 443,
        outbound: outbound,
      ),
      0,
    );

void main() {
  test('WireGuard carrying the session names Speed mode', () {
    expect(
      tunnelChipLabel(
          TunnelPath.speed, SpeedFallbackReason.none, _location()),
      'Speed mode · WireGuard',
    );
  });

  test('a blocked handshake says so, and says it about the network', () {
    expect(
      tunnelChipLabel(
          TunnelPath.stealth, SpeedFallbackReason.blocked, _location()),
      'Stealth · WireGuard blocked here',
    );
  });

  test('the common case names the stealth protocol instead of saying nothing',
      () {
    // This is what the old quiet line returned null for, so most sessions
    // said nothing at all about what was carrying them.
    expect(
      tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.off, _location()),
      'Stealth · VLESS',
    );
    expect(
      tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.noSubscription,
          _location(name: 'it-mil-trojan-02', protocol: 'trojan', outbound: const {
            'type': 'trojan'
          })),
      'Stealth · Trojan',
    );
  });

  test('reasons about the account do not make claims about the network', () {
    // "WireGuard blocked here" would be untrue: the network was never tried.
    expect(
      tunnelChipLabel(
          TunnelPath.stealth, SpeedFallbackReason.deviceLimit, _location()),
      'Stealth · VLESS',
    );
    expect(
      tunnelChipLabel(
          TunnelPath.stealth, SpeedFallbackReason.noProfile, _location()),
      'Stealth · VLESS',
    );
  });

  test('with no location at all it still says something', () {
    expect(
      tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.off, null),
      'Stealth · VLESS',
    );
  });

  test('Advanced view carries the full chain instead', () {
    expect(
      tunnelChipLabel(TunnelPath.speed, SpeedFallbackReason.none, _location(),
          advanced: true),
      'vless · reality · 198.51.100.24:443',
    );
    // Advanced with nothing selected falls back to the plain wording.
    expect(
      tunnelChipLabel(TunnelPath.speed, SpeedFallbackReason.none, null,
          advanced: true),
      'Speed mode · WireGuard',
    );
  });

  test('protoShort maps the chain head to the human name', () {
    expect(protoShort(_location()), 'VLESS');
    expect(protoShort(null), isNull);
  });
}
