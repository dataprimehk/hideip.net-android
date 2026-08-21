import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/deep_link.dart';
import 'package:hideip_vpn/core/import_payload.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/share_link_parser.dart';

/// The link the site hands a phone: payload in the fragment, so it never
/// reaches a web server's request line or its logs.
String appLink(String payload, {String? name, String path = '/import'}) {
  final fragment = Uri(queryParameters: {'url': payload, 'name': ?name}).query;
  return 'https://hideip.net$path#$fragment';
}

/// The custom scheme, which the seller channel already runs on.
String schemeLink(String payload) =>
    'hideip://import?url=${Uri.encodeComponent(payload)}';

/// What the shell does with an incoming link: read the shape, then hold the
/// payload to the importer's whitelist. Returns the text that would prefill
/// the import screen, or null when the link is refused.
String? admitted(String raw) {
  final parsed = parseDeepLink(raw);
  if (parsed == null) return null;
  return classifyImportPayload(parsed.text) == null ? null : parsed.text;
}

void main() {
  group('both link shapes carry the same payloads', () {
    const share = 'vless://uuid@host:443?security=reality&pbk=KEY#Berlin';
    const subscription = 'https://sub.example.com/feed?token=secret';

    test('a share link survives its own query and fragment', () {
      expect(admitted(appLink(share)), share);
      expect(admitted(schemeLink(share)), share);
      expect(admitted('hideip://import/$share'), share);
    });

    test('a subscription URL is admitted whole', () {
      expect(admitted(appLink(subscription)), subscription);
      expect(admitted(schemeLink(subscription)), subscription);
    });

    test('the app link answers to both of its paths', () {
      expect(admitted(appLink(share, path: '/import')), share);
      expect(admitted(appLink(share, path: '/add')), share);
      expect(admitted(appLink(share, path: '/import/')), share);
    });

    test('every protocol the parser supports may arrive by link', () {
      for (final scheme in ShareLinkParser.supportedSchemes) {
        final payload = '$scheme://uuid@host:443';
        expect(admitted(appLink(payload)), payload, reason: scheme);
        expect(admitted(schemeLink(payload)), payload, reason: scheme);
      }
    });
  });

  group('a link is refused rather than acted on', () {
    test('when the payload names a scheme the parser cannot build', () {
      // The wrapper is ours and well formed; only the payload is not
      // something the importer could ever turn into a server.
      for (final payload in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'data:text/html,<script>x</script>',
        'ftp://host/config',
        'content://com.other.app/files/config',
        // Was wireguard:// until the parser learned to build one; any scheme
        // used here has to be one the importer still has no branch for.
        'ssh://host:22',
      ]) {
        expect(admitted(appLink(payload)), isNull, reason: payload);
        expect(admitted(schemeLink(payload)), isNull, reason: payload);
      }
    });

    test('when the payload is malformed or empty', () {
      for (final raw in [
        'https://hideip.net/import',
        'https://hideip.net/import#url=',
        'https://hideip.net/import#url=%20',
        'https://hideip.net/import#%zz',
        'https://hideip.net/import#name=NoPayload',
        'hideip://import',
        'hideip://import/',
        appLink('not a link at all'),
        appLink('vless:/'),
        appLink('://host:443'),
      ]) {
        expect(admitted(raw), isNull, reason: raw);
      }
    });

    test('when the link is not ours', () {
      const share = 'vless://uuid@host:443';
      for (final raw in [
        'http://hideip.net/import#url=$share',
        'https://hideip.net.evil.test/import#url=$share',
        'https://evil.test/import#url=$share',
        'https://hideip.net/blog#url=$share',
        'other://import?url=$share',
      ]) {
        expect(admitted(raw), isNull, reason: raw);
      }
    });

    test('when it is a pairing link, which imports nothing', () {
      expect(admitted('hideip://link?v=1&id=opaque-id'), isNull);
    });
  });

  group('payload classification', () {
    test('separates the three things a provider sends', () {
      expect(classifyImportPayload('vless://uuid@host:443'),
          const ImportPayload(ImportPayloadKind.shareLink, 'vless'));
      expect(classifyImportPayload('HY2://host:443'),
          const ImportPayload(ImportPayloadKind.shareLink, 'hy2'));
      // http(s) reads as a subscription to fetch: that is what providers send.
      expect(classifyImportPayload('https://sub.example/feed'),
          const ImportPayload(ImportPayloadKind.subscriptionUrl, 'https'));
      expect(classifyImportPayload('vless://a@h:1\nss://b@h:2'),
          const ImportPayload(ImportPayloadKind.subscriptionBlob));
      expect(classifyImportPayload('dmxlc3M6Ly91dWlkQGhvc3Q6NDQzP3NlY3VyaXR5PXQ='),
          const ImportPayload(ImportPayloadKind.subscriptionBlob));
    });

    test('refuses text that is neither a link nor a body', () {
      for (final text in ['', '   ', 'hello', 'vless:uuid@host', '#comment']) {
        expect(classifyImportPayload(text), isNull, reason: text);
      }
    });

    test('the whitelist is the parser\'s own dispatch table', () {
      // A scheme listed as supported must reach a real parser branch: it may
      // still fail on its contents, but never as an unknown scheme.
      for (final scheme in ShareLinkParser.supportedSchemes) {
        try {
          ShareLinkParser.parse('$scheme://');
        } on ProfileParseException catch (e) {
          expect(e.message, isNot(contains('Unsupported scheme')), reason: scheme);
        } catch (_) {
          // Any other failure is about the contents, which is the point.
        }
      }
    });
  });

  group('the same link delivered twice', () {
    test('is acted on once', () {
      // Cold start reads the launch link and the stream replays it.
      final once = DeepLinkOnce();
      final start = DateTime(2026, 8, 16, 12);
      const link = 'hideip://import/vless://uuid@host:443';
      expect(once.accept(link, now: start), isTrue);
      expect(once.accept(link, now: start.add(const Duration(seconds: 1))),
          isFalse);
    });

    test('is acted on again when the user taps it later', () {
      final once = DeepLinkOnce();
      final start = DateTime(2026, 8, 16, 12);
      const link = 'hideip://import/vless://uuid@host:443';
      expect(once.accept(link, now: start), isTrue);
      expect(once.accept(link, now: start.add(const Duration(minutes: 2))),
          isTrue);
    });

    test('does not swallow a different link that follows it', () {
      final once = DeepLinkOnce();
      final start = DateTime(2026, 8, 16, 12);
      expect(once.accept('hideip://import/vless://a@host:443', now: start),
          isTrue);
      expect(
          once.accept('hideip://import/vless://b@host:443',
              now: start.add(const Duration(milliseconds: 200))),
          isTrue);
    });
  });
}
