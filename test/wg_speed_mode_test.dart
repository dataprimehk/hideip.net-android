import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/location.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/wg_profile.dart';
import 'package:hideip_vpn/core/wg_speed_mode.dart';

const _ams = WgServer(
  serverId: 'srv_1',
  label: 'Amsterdam',
  countryCode: 'NL',
  city: 'Amsterdam',
  host: '1.2.3.4',
  port: 51820,
  serverPubkey: 'a',
);
const _fra = WgServer(
  serverId: 'srv_2',
  label: 'Frankfurt',
  countryCode: 'DE',
  city: 'Frankfurt',
  host: '5.6.7.8',
  port: 51820,
  serverPubkey: 'b',
);

WgProfile _profile({List<WgServer> servers = const [_ams, _fra]}) => WgProfile(
      address: '10.66.0.10/32',
      dns: const ['1.1.1.1'],
      mtu: 1280,
      persistentKeepalive: 25,
      allowedIps: const ['0.0.0.0/0'],
      servers: servers,
      fetchedAt: DateTime.utc(2026, 7, 30),
    );

void main() {
  group('SpeedModeDecision', () {
    test('uses WireGuard when everything lines up', () {
      final d = SpeedModeDecision.decide(
          enabled: true, premium: true, profile: _profile());
      expect(d.useWireGuard, isTrue);
      expect(d.reason, SpeedFallbackReason.none);
      expect(d.server, isNotNull);
    });

    test('Speed mode off means stealth, with nothing to report', () {
      final d = SpeedModeDecision.decide(
          enabled: false, premium: true, profile: _profile());
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.off);
    });

    test('no subscription means stealth', () {
      final d = SpeedModeDecision.decide(
          enabled: true, premium: false, profile: _profile());
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.noSubscription);
    });

    test('no cached profile means stealth', () {
      final d = SpeedModeDecision.decide(
          enabled: true, premium: true, profile: null);
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.noProfile);
    });

    test('a profile with no servers is not usable', () {
      final d = SpeedModeDecision.decide(
          enabled: true, premium: true, profile: _profile(servers: const []));
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.noProfile);
    });

    test('a network already known to block WireGuard skips the probe', () {
      final d = SpeedModeDecision.decide(
          enabled: true,
          premium: true,
          profile: _profile(),
          blockedHere: true);
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.blocked);
    });

    test('the device limit means stealth', () {
      final d = SpeedModeDecision.decide(
          enabled: true,
          premium: true,
          profile: _profile(),
          deviceLimited: true);
      expect(d.useWireGuard, isFalse);
      expect(d.reason, SpeedFallbackReason.deviceLimit);
    });

    test('WireGuard is never a regression: every no falls back cleanly', () {
      // Whatever the reason, a "no" must still leave a usable stealth path,
      // i.e. it never surfaces as an error state.
      for (final d in [
        SpeedModeDecision.decide(
            enabled: false, premium: true, profile: _profile()),
        SpeedModeDecision.decide(
            enabled: true, premium: false, profile: _profile()),
        SpeedModeDecision.decide(enabled: true, premium: true, profile: null),
        SpeedModeDecision.decide(
            enabled: true,
            premium: true,
            profile: _profile(),
            blockedHere: true),
      ]) {
        expect(d.useWireGuard, isFalse);
        expect(d.server, isNull);
      }
    });
  });

  group('server selection', () {
    test('matches the country the user already picked', () {
      final s = SpeedModeDecision.pickServer(const [_ams, _fra], 'DE');
      expect(s, _fra);
    });

    test('is case insensitive on the country code', () {
      expect(SpeedModeDecision.pickServer(const [_ams, _fra], 'de'), _fra);
    });

    test('falls back to the first server the backend listed', () {
      // The backend controls that order through sort_weight, so preference
      // stays a server-side decision rather than a guess baked into the app.
      expect(SpeedModeDecision.pickServer(const [_ams, _fra], 'US'), _ams);
      expect(SpeedModeDecision.pickServer(const [_ams, _fra], null), _ams);
      expect(SpeedModeDecision.pickServer(const [_ams, _fra], ''), _ams);
    });

    test('an empty list yields no server', () {
      expect(SpeedModeDecision.pickServer(const [], 'NL'), isNull);
    });

    test('the decision honours the preferred country end to end', () {
      final d = SpeedModeDecision.decide(
          enabled: true,
          premium: true,
          profile: _profile(),
          preferredCountry: 'DE');
      expect(d.server, _fra);
    });
  });

  group('handshake detection', () {
    test('no downlink bytes after the probe window means blocked', () {
      // A blocked tunnel still sends (handshake initiations go out into the
      // void); it is the absence of inbound bytes that gives it away.
      expect(WgHandshakeMemory.looksBlocked(downlinkTotal: 0), isTrue);
      expect(WgHandshakeMemory.looksBlocked(downlinkTotal: 1), isFalse);
      expect(WgHandshakeMemory.looksBlocked(downlinkTotal: 4096), isFalse);
    });

    test('the probe window is long enough for a slow mobile handshake', () {
      expect(WgHandshakeMemory.probeWindow.inSeconds, greaterThanOrEqualTo(5));
      expect(WgHandshakeMemory.probeWindow.inSeconds, lessThanOrEqualTo(10));
    });

    test('a blocked network is remembered and can recover', () {
      final mem = WgHandshakeMemory();
      expect(mem.isBlocked('net-a'), isFalse);
      mem.markBlocked('net-a');
      expect(mem.isBlocked('net-a'), isTrue);
      // Other networks are unaffected.
      expect(mem.isBlocked('net-b'), isFalse);
      mem.markWorking('net-a');
      expect(mem.isBlocked('net-a'), isFalse);
    });

    test('an unknown network is never treated as blocked', () {
      // Null means "we could not identify the network", which must retry
      // WireGuard rather than write it off.
      final mem = WgHandshakeMemory();
      mem.markBlocked(null);
      expect(mem.isBlocked(null), isFalse);
    });

    test('clear forgets every network', () {
      final mem = WgHandshakeMemory()
        ..markBlocked('net-a')
        ..markBlocked('net-b');
      mem.clear();
      expect(mem.isBlocked('net-a'), isFalse);
      expect(mem.isBlocked('net-b'), isFalse);
    });
  });

  group('tunnel chip', () {
    // The chip is the new signature: a Location comes in, and something
    // always comes out. See test/tunnel_chip_test.dart for the full matrix.
    final loc = Location.derive(
      const ProxyProfile(
        name: 'de-fra-reality-01',
        protocol: 'vless',
        server: '198.51.100.24',
        port: 443,
        outbound: {'type': 'vless'},
      ),
      0,
    );

    test('names the speed path while WireGuard carries the traffic', () {
      expect(
        tunnelChipLabel(TunnelPath.speed, SpeedFallbackReason.none, loc),
        'Speed mode · WireGuard',
      );
    });

    test('names the network only when the network is the reason', () {
      expect(
        tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.blocked, loc),
        'Stealth · WireGuard blocked here',
      );
      expect(
        tunnelChipLabel(
            TunnelPath.stealth, SpeedFallbackReason.deviceLimit, loc),
        'Stealth · VLESS',
      );
      expect(
        tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.noProfile, loc),
        'Stealth · VLESS',
      );
    });

    test('never goes quiet, including for users who never turned it on', () {
      for (final reason in SpeedFallbackReason.values) {
        expect(tunnelChipLabel(TunnelPath.stealth, reason, loc), isNotEmpty);
      }
      expect(
        tunnelChipLabel(TunnelPath.stealth, SpeedFallbackReason.off, loc),
        'Stealth · VLESS',
      );
      expect(
        tunnelChipLabel(
            TunnelPath.stealth, SpeedFallbackReason.noSubscription, loc),
        'Stealth · VLESS',
      );
    });
  });
}
