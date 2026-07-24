import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/premium.dart';
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

  group('PurchasePayload', () {
    test('android payload round-trips through JSON', () {
      const p = PurchasePayload.android(
          purchaseToken: 'tok-123', productId: PremiumProducts.monthly);
      final back = PurchasePayload.tryParse(jsonEncode(p.toJson()))!;
      expect(back.platform, 'android');
      expect(back.purchaseToken, 'tok-123');
      expect(back.jws, isNull);
      expect(back.productId, PremiumProducts.monthly);
    });

    test('ios payload round-trips through JSON', () {
      const p =
          PurchasePayload.ios(jws: 'a.b.c', productId: PremiumProducts.yearly);
      final back = PurchasePayload.tryParse(jsonEncode(p.toJson()))!;
      expect(back.platform, 'ios');
      expect(back.jws, 'a.b.c');
      expect(back.purchaseToken, isNull);
      expect(back.productId, PremiumProducts.yearly);
    });

    test('legacy bare-JWS record migrates to an iOS payload', () {
      // Pre-Android persisted value: a raw StoreKit JWS, no JSON wrapper.
      final back = PurchasePayload.tryParse('header.payload.sig')!;
      expect(back.platform, 'ios');
      expect(back.jws, 'header.payload.sig');
      expect(back.purchaseToken, isNull);
      expect(back.productId, '');
    });

    test('empty persisted value parses to null', () {
      expect(PurchasePayload.tryParse(''), isNull);
    });
  });

  group('provisionBody', () {
    test('android body uses snake_case token and product id', () {
      const p = PurchasePayload.android(
          purchaseToken: 'tok-xyz', productId: PremiumProducts.yearly);
      expect(provisionBody(p), {
        'platform': 'android',
        'purchase_token': 'tok-xyz',
        'product_id': PremiumProducts.yearly,
      });
    });

    test('ios body is unchanged from the JWS-only contract', () {
      const p =
          PurchasePayload.ios(jws: 'a.b.c', productId: PremiumProducts.monthly);
      // iOS keeps exactly {platform, jws}: no product id, no token.
      expect(provisionBody(p), {'platform': 'ios', 'jws': 'a.b.c'});
    });
  });
}
