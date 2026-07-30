import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hideip_vpn/core/wg_register.dart';
import 'package:hideip_vpn/core/wg_profile.dart';

/// A valid 44-character key, so the client's own validation lets the request
/// through to the mocked transport.
final _pubkey = base64.encode(List<int>.filled(32, 3));

const _okBody = '''
{
  "address": "10.66.0.10/32",
  "dns": ["1.1.1.1", "1.0.0.1"],
  "mtu": 1280,
  "persistent_keepalive": 25,
  "allowed_ips": ["0.0.0.0/0", "::/0"],
  "servers": [
    {"server_id": "srv_a1b2c3d4", "label": "Amsterdam", "country_code": "NL",
     "city": "Amsterdam", "host": "1.2.3.4", "port": 51820,
     "server_pubkey": "c2VydmVycHVia2V5MDAwMDAwMDAwMDAwMDAwMDAwMDA="}
  ]
}
''';

WgRegisterService _service(MockClient client) =>
    WgRegisterService(client: client, baseUrl: 'https://api.example.test');

void main() {
  group('register', () {
    test('sends the contract body and parses a 200 into a profile', () async {
      late http.Request seen;
      final svc = _service(MockClient((req) async {
        seen = req;
        return http.Response(_okBody, 200);
      }));

      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);

      expect(seen.url.path, '/v1/wg/register');
      expect(seen.method, 'POST');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      // Exactly the two contract fields, snake_case, and never the private key.
      expect(body, {'sub_token': 'tok-1', 'client_pubkey': _pubkey});

      expect(res.status, WgRegisterStatus.ok);
      expect(res.isOk, isTrue);
      final p = res.profile!;
      expect(p.address, '10.66.0.10/32');
      expect(p.dns, ['1.1.1.1', '1.0.0.1']);
      expect(p.persistentKeepalive, 25);
      expect(p.allowedIps, ['0.0.0.0/0', '::/0']);
      expect(p.servers.single.host, '1.2.3.4');
      expect(p.servers.single.port, 51820);
      expect(p.servers.single.countryCode, 'NL');
    });

    test('is idempotent: repeating the call returns the same address', () async {
      // The backend guarantees a stable address for the same
      // (sub_token, client_pubkey); the client must simply re-run it on every
      // refresh rather than caching a "already registered" flag.
      var calls = 0;
      final svc = _service(MockClient((req) async {
        calls++;
        return http.Response(_okBody, 200);
      }));

      final first = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      final second = await svc.register(subToken: 'tok-1', publicKey: _pubkey);

      expect(calls, 2);
      expect(first.profile!.address, second.profile!.address);
      expect(first.isOk && second.isOk, isTrue);
    });

    test('409 reports the device limit and asks the caller to forget', () async {
      final svc = _service(MockClient(
          (_) async => http.Response('{"error":"device_limit"}', 409)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.deviceLimit);
      expect(res.profile, isNull);
      expect(res.shouldForget, isTrue);
      expect(res.message, contains('5 devices'));
    });

    test('410 is treated as a lapsed subscription', () async {
      final svc = _service(MockClient((_) async => http.Response('', 410)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.gone);
      expect(res.shouldForget, isTrue);
      // Nothing to say: the premium path already tells the user about this.
      expect(res.message, isNull);
    });

    test('404 is treated the same as 410', () async {
      final svc = _service(MockClient((_) async => http.Response('', 404)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.gone);
    });

    test('400 reports a bad key', () async {
      final svc = _service(MockClient((_) async => http.Response('', 400)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.badKey);
    });

    test('a malformed key never reaches the network', () async {
      var called = false;
      final svc = _service(MockClient((_) async {
        called = true;
        return http.Response(_okBody, 200);
      }));
      final res = await svc.register(subToken: 'tok-1', publicKey: 'nope');
      expect(called, isFalse);
      expect(res.status, WgRegisterStatus.badKey);
    });

    test('a server error is transient, so the cached profile survives', () async {
      final svc = _service(MockClient((_) async => http.Response('', 500)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.transient);
      expect(res.shouldForget, isFalse);
    });

    test('a thrown transport error is transient, not a crash', () async {
      final svc = _service(MockClient((_) async => throw const SocketFailure()));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.transient);
    });

    test('a 200 with no usable servers is not accepted as a profile', () async {
      final svc = _service(MockClient((_) async =>
          http.Response('{"address":"10.66.0.10/32","servers":[]}', 200)));
      final res = await svc.register(subToken: 'tok-1', publicKey: _pubkey);
      expect(res.status, WgRegisterStatus.transient);
      expect(res.profile, isNull);
    });
  });

  group('revoke', () {
    test('posts the same body to the revoke path', () async {
      late http.Request seen;
      final svc = _service(MockClient((req) async {
        seen = req;
        return http.Response('{"ok":true}', 200);
      }));
      final ok = await svc.revoke(subToken: 'tok-1', publicKey: _pubkey);
      expect(ok, isTrue);
      expect(seen.url.path, '/v1/wg/revoke');
      expect(jsonDecode(seen.body),
          {'sub_token': 'tok-1', 'client_pubkey': _pubkey});
    });

    test('a failure is reported without throwing', () async {
      final svc = _service(MockClient((_) async => throw const SocketFailure()));
      expect(await svc.revoke(subToken: 'tok-1', publicKey: _pubkey), isFalse);
    });
  });

  group('subTokenFromUrl', () {
    test('pulls the token out of the subscription URL', () {
      expect(subTokenFromUrl('https://api.hideip.net:8444/v1/sub/abc123'),
          'abc123');
    });

    test('rejects anything that is not a /sub/<token> URL', () {
      expect(subTokenFromUrl(null), isNull);
      expect(subTokenFromUrl(''), isNull);
      expect(subTokenFromUrl('https://api.hideip.net:8444/v1/provision'), isNull);
      expect(subTokenFromUrl('https://api.hideip.net:8444/'), isNull);
    });
  });

  group('WgProfile', () {
    test('caps the MTU at 1280 even when the backend says otherwise', () {
      // The expensive lesson from the TUN inbound: an MTU sized for the
      // physical link silently drops large packets once anything is
      // encapsulated on top of it.
      final p = WgProfile.tryParse(
          jsonDecode(_okBody.replaceFirst('"mtu": 1280', '"mtu": 1420'))
              as Map<String, dynamic>)!;
      expect(p.mtu, 1420);
      expect(p.effectiveMtu, 1280);
    });

    test('a missing or absurd MTU still resolves to 1280', () {
      final p = WgProfile.tryParse(
          jsonDecode(_okBody.replaceFirst('"mtu": 1280,', ''))
              as Map<String, dynamic>)!;
      expect(p.effectiveMtu, 1280);
      final zero = WgProfile.tryParse(
          jsonDecode(_okBody.replaceFirst('"mtu": 1280', '"mtu": 0'))
              as Map<String, dynamic>)!;
      expect(zero.effectiveMtu, 1280);
    });

    test('round-trips through the local cache format', () {
      final p =
          WgProfile.tryParse(jsonDecode(_okBody) as Map<String, dynamic>)!;
      final back = WgProfile.decode(WgProfile.encode(p))!;
      expect(back.address, p.address);
      expect(back.servers.single.serverPubkey, p.servers.single.serverPubkey);
      expect(back.effectiveMtu, 1280);
      expect(back.fetchedAt.millisecondsSinceEpoch,
          p.fetchedAt.millisecondsSinceEpoch);
    });

    test('a server missing its host, port or key is dropped', () {
      final m = jsonDecode(_okBody) as Map<String, dynamic>;
      (m['servers'] as List).add({'label': 'broken'});
      final p = WgProfile.tryParse(m)!;
      expect(p.servers.length, 1);
    });
  });
}

/// Stand-in for a transport failure; MockClient has no built-in way to throw.
class SocketFailure implements Exception {
  const SocketFailure();
}
