import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/state/app_state.dart';

ProxyProfile _profile(String name, {bool premium = false}) => ProxyProfile(
      name: name,
      protocol: 'vless',
      server: '198.51.100.24',
      port: 443,
      outbound: const {'type': 'vless'},
      premium: premium,
    );

void main() {
  test('no subscription is byo, whatever the list holds', () {
    expect(mixOf(const <ProxyProfile>[], premiumOn: false), Mix.byo);
    expect(
      mixOf([_profile('ch-zur-reality-03')], premiumOn: false),
      Mix.byo,
    );
    // Managed profiles left over from a lapsed subscription do not promote
    // the list; the entitlement decides, not the leftovers.
    expect(
      mixOf([_profile('de-fra-01', premium: true)], premiumOn: false),
      Mix.byo,
    );
  });

  test('a subscription plus servers of their own is mixed', () {
    expect(
      mixOf(
        [_profile('de-fra-01', premium: true), _profile('ch-zur-reality-03')],
        premiumOn: true,
      ),
      Mix.mixed,
    );
  });

  test('a subscription and nothing else is hip', () {
    expect(
      mixOf(
        [
          _profile('de-fra-01', premium: true),
          _profile('nl-ams-01', premium: true),
        ],
        premiumOn: true,
      ),
      Mix.hip,
    );
    // An empty list under a live subscription is still hip: the profiles are
    // on their way, and there is nothing of the user's to set apart.
    expect(mixOf(const <ProxyProfile>[], premiumOn: true), Mix.hip);
  });

  test('a server named after us is still the user own server', () {
    // The flag comes from provisioning, never from the name.
    expect(
      mixOf([_profile('hideip.net frankfurt')], premiumOn: true),
      Mix.mixed,
    );
  });
}
