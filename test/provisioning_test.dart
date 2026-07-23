import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/provisioning.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';

ProxyProfile _p(String name, {bool premium = false}) => ProxyProfile(
      name: name,
      protocol: 'vless',
      server: '1.2.3.4',
      port: 443,
      outbound: const {'type': 'vless'},
      premium: premium,
    );

void main() {
  test('premium profiles are recognized by the flag, never by name', () {
    expect(isPremiumProfile(_p('Frankfurt', premium: true)), isTrue);
    expect(isPremiumProfile(_p('my server')), isFalse);
    // A user profile that merely mentions the brand is not managed.
    expect(isPremiumProfile(_p('hideip.net Premium')), isFalse);
    expect(isPremiumProfile(_p('hideip-review')), isFalse);
  });

  test('merge replaces managed profiles and keeps user imports in place', () {
    final current = [
      _p('my server'),
      _p('Frankfurt', premium: true),
      _p('work vpn'),
    ];
    final fresh = [
      _p('Amsterdam', premium: true),
      _p('New York', premium: true),
    ];
    final merged = mergePremiumProfiles(current, fresh);
    expect(merged.map((p) => p.name).toList(),
        ['my server', 'work vpn', 'Amsterdam', 'New York']);
  });

  test('merge with no fresh profiles drops the managed ones', () {
    final current = [_p('Frankfurt', premium: true), _p('my server')];
    final merged = mergePremiumProfiles(current, const []);
    expect(merged.map((p) => p.name).toList(), ['my server']);
  });
}
