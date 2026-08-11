import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/safe_http.dart';
import 'package:hideip_vpn/core/subscription.dart';

String _link(int index) =>
    'trojan://password@server$index.example:443?sni=server$index.example#$index';

void main() {
  test('rejects raw and decoded payloads over the byte ceiling', () {
    expect(
      () => Subscription.parse('x' * (subscriptionMaxBytes + 1)),
      throwsA(isA<SubscriptionLimitException>()),
    );

    final decoded = List<int>.filled(subscriptionMaxBytes + 1, 0x61);
    final encoded = base64Encode(decoded);
    // The encoded form itself is also over the transport limit and must fail
    // before decoding allocates another large buffer.
    expect(
      () => Subscription.parse(encoded),
      throwsA(isA<SubscriptionLimitException>()),
    );
  });

  test('rejects excessive nesting, entries and profiles', () {
    final nested =
        '${'[' * (Subscription.maxNesting + 1)}0'
        '${']' * (Subscription.maxNesting + 1)}';
    expect(
      () => Subscription.parse('{"outbounds":$nested}'),
      throwsA(isA<SubscriptionLimitException>()),
    );

    final tooManyEntries = List.generate(
      Subscription.maxEntries + 1,
      (index) => '# $index',
    ).join('\n');
    expect(
      () => Subscription.parse(tooManyEntries),
      throwsA(isA<SubscriptionLimitException>()),
    );

    final tooManyProfiles = List.generate(
      Subscription.maxProfiles + 1,
      _link,
    ).join('\n');
    expect(
      () => Subscription.parse(tooManyProfiles),
      throwsA(isA<SubscriptionLimitException>()),
    );
  });

  test('caps parse errors without echoing credential-bearing input', () {
    final body = List.generate(150, (index) => 'bad-secret-$index').join('\n');
    final result = Subscription.parse(body);
    expect(result.errors, hasLength(Subscription.maxErrors));
    expect(result.errors.first, startsWith('Line 1 ->'));
    expect(result.errors.join(' '), isNot(contains('bad-secret')));
  });

  test(
    'async parsing returns the same profiles off the caller isolate',
    () async {
      final result = await Subscription.parseAsync(_link(1));
      expect(result.profiles.single.name, '1');
    },
  );
}
