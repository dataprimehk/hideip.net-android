import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hideip_vpn/core/app_version.dart';

void main() {
  test('version constant stays in sync with pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(appVersion, m!.group(1));
    expect(subscriptionUserAgent, 'hideip/$appVersion');
    expect(subscriptionHeaders['User-Agent'], subscriptionUserAgent);
  });

  test('a subscription fetch sends the hideip User-Agent header', () async {
    String? seenUserAgent;
    final client = MockClient((req) async {
      seenUserAgent = req.headers['User-Agent'];
      return http.Response('proxies:\n', 200);
    });

    // Mirror the call sites: every subscription fetch merges [subscriptionHeaders].
    await client.get(
      Uri.parse('https://panel.example.com/sub'),
      headers: subscriptionHeaders,
    );

    expect(seenUserAgent, subscriptionUserAgent);
  });
}
