import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/deep_link.dart';

String _appLink(String payload, {String? name}) {
  final fragment = Uri(
    queryParameters: {'url': payload, 'name': ?name},
  ).query;
  return 'https://hideip.net/add#$fragment';
}

void main() {
  group('verified HTTPS import link', () {
    test('carries a subscription URL only in the fragment', () {
      final result = parseDeepLink(
        _appLink('https://sub.example.com/feed?token=secret', name: 'Provider'),
      );
      expect(result?.text, 'https://sub.example.com/feed?token=secret');
      expect(result?.name, 'Provider');
    });

    test('preserves an encoded share link and its own fragment', () {
      const share = 'vless://uuid@host:443?security=reality&pbk=KEY#Berlin';
      final result = parseDeepLink(_appLink(share));
      expect(result?.text, share);
      expect(result?.name, isNull);
    });

    test('requires exact scheme, host and path', () {
      final fragment = Uri(queryParameters: {'url': 'vless://secret'}).query;
      for (final value in [
        'http://hideip.net/add#$fragment',
        'https://www.hideip.net/add#$fragment',
        'https://hideip.net/other#$fragment',
        'https://evil.test/add#$fragment',
      ]) {
        expect(parseDeepLink(value), isNull);
      }
    });

    test('rejects query payloads because queries reach the web server', () {
      expect(
        parseDeepLink('https://hideip.net/add?url=vless%3A%2F%2Fsecret'),
        isNull,
      );
    });

    test('rejects empty and malformed fragment payloads', () {
      expect(parseDeepLink('https://hideip.net/add'), isNull);
      expect(parseDeepLink('https://hideip.net/add#name=NoPayload'), isNull);
      expect(parseDeepLink('https://hideip.net/add#%zz'), isNull);
    });
  });

  group('custom scheme isolation', () {
    test('rejects every credential-bearing hideip import convention', () {
      for (final value in [
        'hideip://install-config?url=https%3A%2F%2Fsub.example%2Fsecret',
        'hideip://add?url=vless%3A%2F%2Fuuid%40host%3A443',
        'hideip://import/vless://uuid@host:443',
        'hideip:/import/https://sub.example/secret',
      ]) {
        expect(parseDeepLink(value), isNull);
      }
    });

    test('does not confuse the retained pairing link with an import', () {
      const value = 'hideip://link?v=1&id=opaque-id';
      expect(parseDeepLink(value), isNull);
      expect(parsePairingLink(value)?.linkId, 'opaque-id');
    });
  });
}
