import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/safe_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('public destination policy', () {
    test('rejects local, private, metadata and reserved IPv4 ranges', () {
      for (final value in [
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.169.254',
        '172.16.0.1',
        '192.168.1.1',
        '198.18.0.1',
        '224.0.0.1',
      ]) {
        expect(isPublicInternetAddress(InternetAddress(value)), isFalse);
      }
      expect(isPublicInternetAddress(InternetAddress('8.8.8.8')), isTrue);
    });

    test('rejects local IPv6 and IPv4-mapped private addresses', () {
      for (final value in [
        '::',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        'ff02::1',
        '2001:db8::1',
      ]) {
        expect(isPublicInternetAddress(InternetAddress(value)), isFalse);
      }
      expect(
        isPublicInternetAddress(InternetAddress('2606:4700:4700::1111')),
        isTrue,
      );
    });
  });

  group('bounded HTTPS fetch', () {
    test(
      'requires HTTPS and rejects local literals before a request',
      () async {
        var requests = 0;
        final fetcher = SafeHttpFetcher.forTesting(
          MockClient((_) async {
            requests++;
            return http.Response('unexpected', 200);
          }),
        );

        for (final uri in [
          Uri.parse('http://example.com/sub'),
          Uri.parse('https://localhost/sub'),
          Uri.parse('https://127.0.0.1/sub'),
          Uri.parse('https://169.254.169.254/latest/meta-data'),
        ]) {
          await expectLater(
            fetcher.get(uri),
            throwsA(isA<SafeHttpException>()),
          );
        }
        expect(requests, 0);
      },
    );

    test('revalidates redirects and rejects an HTTPS downgrade', () async {
      final fetcher = SafeHttpFetcher.forTesting(
        MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'http://example.com/plain'},
          ),
        ),
      );

      await expectLater(
        fetcher.get(Uri.parse('https://example.com/sub')),
        throwsA(isA<SafeHttpException>()),
      );
    });

    test('rejects compressed and oversized response bodies', () async {
      final compressed = SafeHttpFetcher.forTesting(
        MockClient(
          (_) async => http.Response(
            'small',
            200,
            headers: {'content-encoding': 'gzip'},
          ),
        ),
      );
      await expectLater(
        compressed.get(Uri.parse('https://example.com/sub')),
        throwsA(isA<SafeHttpException>()),
      );

      final oversized = SafeHttpFetcher.forTesting(
        MockClient((_) async => http.Response('x' * 33, 200)),
      );
      await expectLater(
        oversized.get(Uri.parse('https://example.com/sub'), maxBytes: 32),
        throwsA(isA<SafeHttpException>()),
      );
    });

    test('returns a bounded identity response', () async {
      final fetcher = SafeHttpFetcher.forTesting(
        MockClient((request) async {
          expect(request.headers['Accept-Encoding'], 'identity');
          return http.Response('ok', 200, headers: {'x-test': 'yes'});
        }),
      );
      final response = await fetcher.get(Uri.parse('https://example.com/sub'));
      expect(response.statusCode, 200);
      expect(response.body, 'ok');
      expect(response.headers['x-test'], 'yes');
    });
  });
}
