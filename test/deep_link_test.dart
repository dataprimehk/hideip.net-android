import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/deep_link.dart';

void main() {
  group('query style (install-config?url=)', () {
    test('urlencoded https subscription url + name', () {
      final r = parseDeepLink(
        'hideip://install-config'
        '?url=https%3A%2F%2Fsub.example.com%2Fmy%2Fpath%3Ftoken%3Dabc'
        '&name=Acme%20VPN',
      )!;
      expect(r.text, 'https://sub.example.com/my/path?token=abc');
      expect(r.name, 'Acme VPN');
    });

    test('name is optional', () {
      final r = parseDeepLink(
        'hideip://install-config?url=https%3A%2F%2Fsub.example.com%2Ffeed',
      )!;
      expect(r.text, 'https://sub.example.com/feed');
      expect(r.name, isNull);
    });

    test('urlencoded vless share link survives intact', () {
      final r = parseDeepLink(
        'hideip://install-config'
        '?url=vless%3A%2F%2Fuuid%40host%3A443%3Fsecurity%3Dtls%23Tokyo',
      )!;
      expect(r.text, 'vless://uuid@host:443?security=tls#Tokyo');
      expect(r.name, isNull);
    });

    test('empty url= is rejected', () {
      expect(parseDeepLink('hideip://install-config?url='), isNull);
    });
  });

  group('path-append style (import/...)', () {
    test('carries a bare https subscription url', () {
      final r = parseDeepLink(
        'hideip://import/https://sub.example.com/feed',
      )!;
      expect(r.text, 'https://sub.example.com/feed');
      expect(r.name, isNull);
    });

    test('carries a urlencoded https subscription url', () {
      final r = parseDeepLink(
        'hideip://import/https%3A%2F%2Fsub.example.com%2Ffeed%3Ftoken%3Dx',
      )!;
      expect(r.text, 'https://sub.example.com/feed?token=x');
    });

    test('carries a vless:// share link with its own fragment', () {
      final r = parseDeepLink(
        'hideip://import/vless://uuid@host:443?security=reality&pbk=KEY#Berlin',
      )!;
      // The share link owns its fragment; it must not be stripped as a name.
      expect(r.text, 'vless://uuid@host:443?security=reality&pbk=KEY#Berlin');
      expect(r.name, isNull);
    });

    test('urlencoded vless share link', () {
      final r = parseDeepLink(
        'hideip://import/vless%3A%2F%2Fuuid%40host%3A443%3Fsecurity%3Dtls%23JP',
      )!;
      expect(r.text, 'vless://uuid@host:443?security=tls#JP');
    });

    test('fragment carries a display name for a non-link payload', () {
      final r = parseDeepLink(
        'hideip://import/c3Vic2NyaXB0aW9uYmxvYg==#My%20Provider',
      )!;
      expect(r.text, 'c3Vic2NyaXB0aW9uYmxvYg==');
      expect(r.name, 'My Provider');
    });

    test('path-only normalization (hideip:/import/...) works', () {
      final r = parseDeepLink('hideip:/import/https://sub.example.com/feed')!;
      expect(r.text, 'https://sub.example.com/feed');
    });

    test('empty remainder is rejected', () {
      expect(parseDeepLink('hideip://import/'), isNull);
    });
  });

  group('garbage / non-matching input', () {
    test('non-hideip scheme returns null', () {
      expect(parseDeepLink('https://sub.example.com/feed'), isNull);
      expect(parseDeepLink('vless://uuid@host:443'), isNull);
    });

    test('unknown hideip action returns null', () {
      expect(parseDeepLink('hideip://connect/now'), isNull);
    });

    test('empty and non-uri input returns null', () {
      expect(parseDeepLink(''), isNull);
      expect(parseDeepLink('   '), isNull);
      expect(parseDeepLink('not a uri at all'), isNull);
    });

    test('scheme match is case-insensitive', () {
      final r = parseDeepLink('HIDEIP://import/https://sub.example.com/feed')!;
      expect(r.text, 'https://sub.example.com/feed');
    });
  });
}
