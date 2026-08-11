import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/ip_lookup.dart';

void main() {
  test('only first-party HTTPS endpoints are allowed', () {
    expect(isAllowedIpEndpoint(Uri.parse('https://hideip.net/api/ip')), isTrue);
    expect(
      isAllowedIpEndpoint(Uri.parse('https://api.hideip.net:8443/ip')),
      isTrue,
    );
    expect(isAllowedIpEndpoint(Uri.parse('http://hideip.net/api/ip')), isFalse);
    expect(isAllowedIpEndpoint(Uri.parse('https://ipwho.is/')), isFalse);
    expect(isAllowedIpEndpoint(Uri.parse('https://hideip.net.evil.test/ip')), isFalse);
  });

  test('parses a bounded first-party response shape', () {
    final result = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":44.81,"longitude":20.46,"city":"Belgrade"}',
    );
    expect(result?.ip, '203.0.113.7');
    expect(result?.geo?.city, 'Belgrade');
    expect(result?.geo?.lat, 44.81);
  });

  test('rejects malformed IP and impossible coordinates', () {
    expect(parseIpLookupBody('{"ip":"not-an-ip"}'), isNull);
    final noGeo = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":100,"longitude":20}',
    );
    expect(noGeo?.ip, '203.0.113.7');
    expect(noGeo?.geo, isNull);
  });
}
