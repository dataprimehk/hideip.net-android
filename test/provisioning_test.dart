import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/provisioning.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';

ProxyProfile _p(String name) => ProxyProfile(
      name: name,
      protocol: 'vless',
      server: '1.2.3.4',
      port: 443,
      outbound: const {'type': 'vless'},
    );

void main() {
  test('premium profiles are recognized by the managed name prefix', () {
    expect(isPremiumProfile(_p('hideip.net Premium')), isTrue);
    expect(isPremiumProfile(_p('hideip.net NL')), isTrue);
    expect(isPremiumProfile(_p('my server')), isFalse);
    // A user profile that merely mentions the brand is not managed.
    expect(isPremiumProfile(_p('hideip-review')), isFalse);
  });

  test('merge replaces managed profiles and keeps user imports in place', () {
    final current = [
      _p('my server'),
      _p('hideip.net Premium'),
      _p('work vpn'),
    ];
    final fresh = [_p('hideip.net NL'), _p('hideip.net US')];
    final merged = mergePremiumProfiles(current, fresh);
    expect(merged.map((p) => p.name).toList(),
        ['my server', 'work vpn', 'hideip.net NL', 'hideip.net US']);
  });

  test('merge with no fresh profiles drops the managed ones', () {
    final current = [_p('hideip.net Premium'), _p('my server')];
    final merged = mergePremiumProfiles(current, const []);
    expect(merged.map((p) => p.name).toList(), ['my server']);
  });
}
