import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/deep_link.dart';

String _appLink(String payload, {String? name, String host = 'hideip.net'}) {
  final fragment = Uri(queryParameters: {'url': payload, 'name': ?name}).query;
  return 'https://$host/add#$fragment';
}

void main() {
  // Where import links are headed: an app link the OS verifies against
  // hideip.net, with the payload in the fragment so no request line or server
  // log ever carries a subscription credential.
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

    test('accepts the shapes of the same link people actually send', () {
      // A www. prefix, a trailing slash and a tracking parameter a seller's
      // analytics appended all name the same destination. Refusing them buys
      // nothing and produces a dead button nobody can explain.
      const share = 'vless://uuid@host:443';
      final fragment = Uri(queryParameters: {'url': share}).query;
      for (final value in [
        'https://www.hideip.net/add#$fragment',
        'https://hideip.net/add/#$fragment',
        'https://hideip.net/add?utm_source=panel#$fragment',
        'https://HIDEIP.net/ADD#$fragment',
      ]) {
        expect(parseDeepLink(value)?.text, share, reason: value);
      }
    });

    test('falls back to the query when the fragment was dropped', () {
      // Some launchers and messaging apps strip fragments. The payload is
      // less private there, but a link that arrives without one is still a
      // link the user asked to open.
      final result = parseDeepLink(
        'https://hideip.net/add?url=vless%3A%2F%2Fuuid%40host%3A443',
      );
      expect(result?.text, 'vless://uuid@host:443');
    });

    test('refuses a host that is not ours', () {
      final fragment = Uri(queryParameters: {'url': 'vless://secret'}).query;
      for (final value in [
        'http://hideip.net/add#$fragment',
        'https://hideip.net.evil.test/add#$fragment',
        'https://evil.test/add#$fragment',
        'https://hideip.net/other#$fragment',
      ]) {
        expect(parseDeepLink(value), isNull, reason: value);
      }
    });

    test('rejects empty and malformed payloads', () {
      expect(parseDeepLink('https://hideip.net/add'), isNull);
      expect(parseDeepLink('https://hideip.net/add#name=NoPayload'), isNull);
      expect(parseDeepLink('https://hideip.net/add#%zz'), isNull);
      expect(parseDeepLink('https://hideip.net/add#url=%20'), isNull);
    });
  });

  // The transitional shape. Any app may register a custom scheme, which is
  // why it is not the destination, but the snippets on hideip.net/sellers are
  // already inside third-party panels nobody can edit for us, and the app
  // link cannot take over until assetlinks.json carries a real fingerprint.
  // Dropping this would break those buttons, not move them somewhere safer.
  group('transitional custom scheme', () {
    test('accepts both conventions that circulate among proxy clients', () {
      expect(
        parseDeepLink(
          'hideip://add?url=vless%3A%2F%2Fuuid%40host%3A443',
        )?.text,
        'vless://uuid@host:443',
      );
      expect(
        parseDeepLink(
          'hideip://install-config?url=https%3A%2F%2Fsub.example%2Ffeed',
        )?.text,
        'https://sub.example/feed',
      );
      expect(
        parseDeepLink('hideip://import/vless://uuid@host:443')?.text,
        'vless://uuid@host:443',
      );
    });

    test('survives the launcher that normalizes away the double slash', () {
      expect(
        parseDeepLink('hideip:/import/https://sub.example/feed')?.text,
        'https://sub.example/feed',
      );
    });

    test('keeps a share link whole, fragment and all', () {
      // The payload's own #Berlin names the server; taking it as this link's
      // display name would silently rename what the user imported.
      const share = 'vless://uuid@host:443?security=reality#Berlin';
      final result = parseDeepLink('hideip://import/$share');
      expect(result?.text, share);
      expect(result?.name, isNull);
    });

    test('reads a trailing name only off a payload that owns no fragment', () {
      // A bare blob has no fragment of its own, so #Provider is a label.
      final labelled = parseDeepLink('hideip://import/dmxlc3M6Ly9ibG9i#Provider');
      expect(labelled?.text, 'dmxlc3M6Ly9ibG9i');
      expect(labelled?.name, 'Provider');

      // Anything that reads as a link keeps everything: a subscription URL is
      // allowed a fragment, and eating it would import a different address.
      const url = 'https://sub.example/feed#Provider';
      expect(parseDeepLink('hideip://import/$url')?.text, url);
    });

    test('carries the name a seller attached', () {
      final result = parseDeepLink(
        'hideip://add?url=https%3A%2F%2Fsub.example%2Ffeed&name=Provider',
      );
      expect(result?.name, 'Provider');
    });

    test('ignores a link with nothing to import', () {
      for (final value in [
        'hideip://add',
        'hideip://add?url=',
        'hideip://import/',
        'hideip://unknown-action?url=vless%3A%2F%2Fx',
        'other://add?url=vless%3A%2F%2Fx',
      ]) {
        expect(parseDeepLink(value), isNull, reason: value);
      }
    });
  });

  group('pairing links', () {
    test('are never mistaken for an import', () {
      const value = 'hideip://link?v=1&id=opaque-id';
      expect(parseDeepLink(value), isNull);
      expect(parsePairingLink(value)?.linkId, 'opaque-id');
    });

    test('refuse a version this build cannot be trusted to understand', () {
      expect(parsePairingLink('hideip://link?v=2&id=opaque-id'), isNull);
    });
  });

  test('an absurdly long link is not parsed at all', () {
    final huge = 'hideip://add?url=${'a' * (256 * 1024)}';
    expect(parseDeepLink(huge), isNull);
    expect(parsePairingLink(huge), isNull);
  });
}
