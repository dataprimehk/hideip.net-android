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

  test('parses every location field of a full response', () {
    final result = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":44.81,"longitude":20.46,'
      '"city":"Belgrade","cc":"rs","country":"Serbia","isp":"Example ISP"}',
    );
    expect(result?.ip, '203.0.113.7');
    expect(result?.geo?.lat, 44.81);
    expect(result?.geo?.lon, 20.46);
    expect(result?.geo?.city, 'Belgrade');
    expect(result?.geo?.cc, 'RS');
    expect(result?.geo?.country, 'Serbia');
    expect(result?.geo?.isp, 'Example ISP');
    expect(result?.cc, 'RS');
    expect(result?.country, 'Serbia');
    expect(result?.isp, 'Example ISP');
  });

  test('null and absent location fields are tolerated', () {
    final withNulls = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":null,"longitude":null,"city":null,'
      '"cc":null,"country":null,"isp":null}',
    );
    expect(withNulls?.ip, '203.0.113.7');
    expect(withNulls?.geo, isNull);
    expect(withNulls?.cc, isNull);
    expect(withNulls?.country, isNull);
    expect(withNulls?.isp, isNull);

    final ipOnly = parseIpLookupBody('{"ip":"203.0.113.7"}');
    expect(ipOnly?.ip, '203.0.113.7');
    expect(ipOnly?.geo, isNull);
    expect(ipOnly?.cc, isNull);
    expect(ipOnly?.country, isNull);
    expect(ipOnly?.isp, isNull);
  });

  test('text fields survive a body without coordinates', () {
    final result = parseIpLookupBody(
      '{"ip":"203.0.113.7","city":"Belgrade","cc":"RS","country":"Serbia",'
      '"isp":"Example ISP"}',
    );
    expect(result?.geo, isNull);
    expect(result?.cc, 'RS');
    expect(result?.country, 'Serbia');
    expect(result?.isp, 'Example ISP');
  });

  test('a country code that is not two ASCII letters is dropped', () {
    for (final raw in ['usa', '1A', '', 'R', 'RŠ', '12']) {
      final result = parseIpLookupBody(
        '{"ip":"203.0.113.7","latitude":44.81,"longitude":20.46,"cc":"$raw"}',
      );
      expect(result?.cc, isNull, reason: 'cc "$raw" should be dropped');
      expect(result?.geo?.cc, isNull, reason: 'cc "$raw" should be dropped');
    }
    final numeric = parseIpLookupBody('{"ip":"203.0.113.7","cc":42}');
    expect(numeric?.cc, isNull);
  });

  test('empty and overlong text fields are dropped', () {
    final long = 'x' * 129;
    final result = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":44.81,"longitude":20.46,'
      '"city":"$long","country":"   ","isp":"$long"}',
    );
    expect(result?.country, isNull);
    expect(result?.isp, isNull);
    expect(result?.geo?.city, 'you');
    expect(result?.geo?.isp, isNull);

    final atLimit = 'y' * 128;
    final kept = parseIpLookupBody(
      '{"ip":"203.0.113.7","country":"$atLimit"}',
    );
    expect(kept?.country, atLimit);
  });

  test('rejects malformed IP and impossible coordinates', () {
    expect(parseIpLookupBody('{"ip":"not-an-ip"}'), isNull);
    final noGeo = parseIpLookupBody(
      '{"ip":"203.0.113.7","latitude":100,"longitude":20}',
    );
    expect(noGeo?.ip, '203.0.113.7');
    expect(noGeo?.geo, isNull);
  });

  test('a body that is not JSON yields null', () {
    expect(parseIpLookupBody('not json at all'), isNull);
    expect(parseIpLookupBody(''), isNull);
    expect(parseIpLookupBody('[1,2,3]'), isNull);
  });
}
