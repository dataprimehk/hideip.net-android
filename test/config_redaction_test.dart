import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/config_redaction.dart';

void main() {
  test('default config export redacts replayable values at every depth', () {
    final source = <String, dynamic>{
      'type': 'vless',
      'server': 'vpn.example.com',
      'server_port': 443,
      'uuid': 'uuid-secret',
      'username': 'proxy-user',
      'password': 'proxy-pass',
      'private_key': 'wg-private',
      'token': 'subscription-token',
      'subscription_url': 'https://sub.example/secret',
      'tls': {
        'enabled': true,
        'reality': {'public_key': 'safe-public', 'short_id': 'safe-short'},
      },
      'peers': [
        {'pre_shared_key': 'peer-secret', 'public_key': 'peer-public'},
      ],
    };

    final redacted = redactConfig(source) as Map<String, dynamic>;
    final rendered = redacted.toString();

    for (final secret in [
      'uuid-secret',
      'proxy-user',
      'proxy-pass',
      'wg-private',
      'subscription-token',
      'https://sub.example/secret',
      'peer-secret',
    ]) {
      expect(rendered, isNot(contains(secret)));
    }
    expect(redacted['server'], 'vpn.example.com');
    expect((redacted['tls'] as Map)['reality']['public_key'], 'safe-public');
    expect((redacted['peers'] as List).single['public_key'], 'peer-public');
    expect(source['uuid'], 'uuid-secret', reason: 'source must not be mutated');
  });

  test('key normalization covers camelCase and punctuation variants', () {
    final redacted =
        redactConfig({
              'privateKey': 'a',
              'pre-shared-key': 'b',
              'subUrl': 'c',
              'authorization': 'd',
            })
            as Map<String, dynamic>;

    expect(redacted.values.toSet(), {'[REDACTED]'});
  });
}
