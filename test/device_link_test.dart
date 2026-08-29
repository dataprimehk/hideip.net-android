import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/deep_link.dart';
import 'package:hideip_vpn/core/device_link.dart';
import 'package:hideip_vpn/state/app_state.dart';
import 'package:hideip_vpn/ui/redesign/hip_sheet.dart';
import 'package:hideip_vpn/ui/redesign/linked_devices_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A client that answers every request with [status]/[body] and records the
/// last request so the test can assert on the wire shape.
class _Recorder {
  http.Request? last;

  http.Client client(int status, [String body = '']) => MockClient((req) async {
        last = req;
        return http.Response(body, status,
            headers: {'content-type': 'application/json'});
      });

  Map<String, dynamic> get lastJson =>
      jsonDecode(last!.body) as Map<String, dynamic>;
}

void main() {
  group('subTokenOf', () {
    test('pulls the token out of the provisioned subscription URL', () {
      expect(subTokenOf('https://api.hideip.net:8444/v1/sub/abc123'), 'abc123');
    });

    test('tolerates a trailing slash and surrounding whitespace', () {
      expect(subTokenOf('  https://api.hideip.net:8444/v1/sub/tok/  '), 'tok');
    });

    test('rejects a URL that is not a /v1/sub/<token> shape', () {
      // A stray path segment must never be sent to the link API as a token.
      expect(subTokenOf('https://api.hideip.net:8444/v1/provision'), isNull);
      expect(subTokenOf('https://example.com/'), isNull);
      expect(subTokenOf('https://api.hideip.net:8444/v1/sub/'), isNull);
    });

    test('null URL yields no token', () {
      expect(subTokenOf(null), isNull);
    });
  });

  group('parsePairingLink', () {
    test('reads the link id out of a v1 pairing link', () {
      final p = parsePairingLink('hideip://link?v=1&id=AbC-123_x');
      expect(p, const DeepLinkPairing('AbC-123_x'));
    });

    test('accepts a link with no version (v defaults to 1)', () {
      expect(parsePairingLink('hideip://link?id=zz9'),
          const DeepLinkPairing('zz9'));
    });

    test('refuses a future version rather than approving a payload blind', () {
      expect(parsePairingLink('hideip://link?v=2&id=zz9'), isNull);
    });

    test('handles the path-only normalization some launchers emit', () {
      expect(parsePairingLink('hideip:/link?v=1&id=q1'),
          const DeepLinkPairing('q1'));
    });

    test('rejects a missing or empty id', () {
      expect(parsePairingLink('hideip://link?v=1'), isNull);
      expect(parsePairingLink('hideip://link?v=1&id='), isNull);
      expect(parsePairingLink('hideip://link?v=1&id=%20'), isNull);
    });

    test('rejects other schemes, other actions and empty input', () {
      expect(parsePairingLink('https://hideip.net/link?id=a'), isNull);
      expect(parsePairingLink('hideip://import/vless://x'), isNull);
      expect(parsePairingLink(''), isNull);
    });

    test('an import link and a pairing link never parse as each other', () {
      // Both parsers see every incoming link; neither may claim the other's.
      const pair = 'hideip://link?v=1&id=abc';
      const import =
          'https://hideip.net/add#url=https%3A%2F%2Fe.com%2Fs';
      expect(parseDeepLink(pair), isNull);
      expect(parsePairingLink(pair), isNotNull);
      expect(parseDeepLink(import), isNotNull);
      expect(parsePairingLink(import), isNull);

      // The transitional custom scheme carries imports as well, and sharing a
      // scheme with pairing is exactly why this cross-check exists: an import
      // must never be read as a request to hand out this phone's access.
      const legacy = 'hideip://install-config?url=https%3A%2F%2Fe.com%2Fs';
      expect(parseDeepLink(legacy), isNotNull);
      expect(parsePairingLink(legacy), isNull);
    });
  });

  group('approve', () {
    test('200 sends the contract body and reports ok', () async {
      final rec = _Recorder();
      final svc = DeviceLinkService(client: rec.client(200, '{"ok":true}'));
      final result = await svc.approve(
          linkId: 'lnk1', subToken: 'sub-tok', deviceName: 'iPhone');
      expect(result, LinkApproveResult.ok);
      expect(rec.last!.method, 'POST');
      expect(rec.last!.url.path, '/v1/link/approve');
      expect(rec.lastJson, {
        'link_id': 'lnk1',
        'token': 'sub-tok',
        'device_name': 'iPhone',
      });
    });

    test('409 is the device limit, which the sheet words differently',
        () async {
      final svc = DeviceLinkService(
          client: _Recorder()
              .client(409, '{"error":"device_limit_reached"}'));
      expect(
          await svc.approve(
              linkId: 'l', subToken: 't', deviceName: 'd'),
          LinkApproveResult.deviceLimit);
    });

    test('401 means the subscription token was rejected', () async {
      final svc = DeviceLinkService(client: _Recorder().client(401));
      expect(
          await svc.approve(linkId: 'l', subToken: 'bad', deviceName: 'd'),
          LinkApproveResult.notEntitled);
    });

    test('404 means the link expired or never existed', () async {
      final svc = DeviceLinkService(client: _Recorder().client(404));
      expect(await svc.approve(linkId: 'l', subToken: 't', deviceName: 'd'),
          LinkApproveResult.expired);
    });

    test('any other status, and a thrown request, land in failed', () async {
      final svc = DeviceLinkService(client: _Recorder().client(500));
      expect(await svc.approve(linkId: 'l', subToken: 't', deviceName: 'd'),
          LinkApproveResult.failed);

      final broken = DeviceLinkService(
          client: MockClient((_) async => throw const SocketFailure()));
      expect(
          await broken.approve(linkId: 'l', subToken: 't', deviceName: 'd'),
          LinkApproveResult.failed);
    });
  });

  group('mintCode', () {
    test('returns the code and its lifetime', () async {
      final rec = _Recorder();
      final svc = DeviceLinkService(
          client: rec.client(200, '{"code":"K7M4PQR9","expires_in":600}'));
      final code = await svc.mintCode('sub-tok');
      expect(code!.code, 'K7M4PQR9');
      expect(code.expiresIn, const Duration(seconds: 600));
      expect(rec.last!.url.path, '/v1/link/code/mint');
      expect(rec.lastJson, {'token': 'sub-tok'});
    });

    test('falls back to the contract default when expires_in is missing',
        () async {
      final svc =
          DeviceLinkService(client: _Recorder().client(200, '{"code":"ABCD2345"}'));
      expect((await svc.mintCode('t'))!.expiresIn, const Duration(seconds: 600));
    });

    test('a refusal, an empty code and junk all yield null', () async {
      expect(
          await DeviceLinkService(client: _Recorder().client(401)).mintCode('t'),
          isNull);
      expect(
          await DeviceLinkService(client: _Recorder().client(200, '{"code":""}'))
              .mintCode('t'),
          isNull);
      expect(
          await DeviceLinkService(client: _Recorder().client(200, 'not json'))
              .mintCode('t'),
          isNull);
    });
  });

  group('devices', () {
    const body = '''
{"devices":[
  {"id":"dev_1","kind":"extension","name":"Chrome on MacBook",
   "created_at":1754380800,"last_seen_at":1754467200},
  {"id":"dev_2","kind":"desktop","name":"Studio","created_at":1754380800}
]}''';

    test('parses the list and sends the token as a query parameter', () async {
      final rec = _Recorder();
      final svc = DeviceLinkService(client: rec.client(200, body));
      final list = (await svc.devices('sub-tok'))!;
      expect(list.length, 2);
      expect(list.first.id, 'dev_1');
      expect(list.first.kind, LinkedDeviceKind.extension);
      expect(list.first.name, 'Chrome on MacBook');
      expect(list.first.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1754380800 * 1000));
      expect(list.first.lastSeenAt, isNotNull);
      // A device that never checked in has no last_seen_at at all.
      expect(list[1].lastSeenAt, isNull);
      expect(list[1].kind, LinkedDeviceKind.desktop);
      expect(rec.last!.method, 'GET');
      expect(rec.last!.url.path, '/v1/link/devices');
      expect(rec.last!.url.queryParameters['token'], 'sub-tok');
    });

    test('an unknown kind stays readable instead of breaking the list', () {
      final list = parseDevices(
          '{"devices":[{"id":"d","kind":"toaster","name":"Kitchen"}]}')!;
      expect(list.single.kind, LinkedDeviceKind.unknown);
      expect(list.single.kindLabel, 'Device');
    });

    test('rows with no id are skipped and an unnamed device still shows', () {
      final list = parseDevices('{"devices":['
          '{"kind":"phone","name":"ghost"},'
          '{"id":"d2","kind":"phone"}]}')!;
      expect(list.length, 1);
      expect(list.single.id, 'd2');
      expect(list.single.name, 'Unnamed device');
    });

    test('an empty list parses as no devices, not as a failure', () {
      expect(parseDevices('{"devices":[]}'), isEmpty);
    });

    test('timestamps tolerate a numeric string and drop unusable values', () {
      final list = parseDevices('{"devices":[{"id":"d","kind":"phone",'
          '"name":"n","created_at":"1754380800","last_seen_at":0}]}')!;
      expect(list.single.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1754380800 * 1000));
      // 0 is "no value" on the wire, not 1970.
      expect(list.single.lastSeenAt, isNull);
    });

    test('every kind maps to the label the rows show', () {
      expect(LinkedDevice.kindOf('extension'), LinkedDeviceKind.extension);
      expect(LinkedDevice.kindOf('DESKTOP'), LinkedDeviceKind.desktop);
      expect(LinkedDevice.kindOf(' phone '), LinkedDeviceKind.phone);
      expect(LinkedDevice.kindOf(null), LinkedDeviceKind.unknown);
      const names = {
        LinkedDeviceKind.extension: 'Browser',
        LinkedDeviceKind.desktop: 'Desktop',
        LinkedDeviceKind.phone: 'Phone',
        LinkedDeviceKind.unknown: 'Device',
      };
      for (final entry in names.entries) {
        expect(
            LinkedDevice(id: 'x', kind: entry.key, name: 'n').kindLabel,
            entry.value);
      }
    });

    test('a body of the wrong shape is a failure, not an empty list', () {
      // The screen must be able to say "could not load" rather than claim
      // the subscription has no linked devices.
      expect(parseDevices('nonsense'), isNull);
      expect(parseDevices('{"devices":"none"}'), isNull);
      expect(parseDevices('[]'), isNull);
    });

    test('a non-200 answer yields null', () async {
      final svc = DeviceLinkService(client: _Recorder().client(500, body));
      expect(await svc.devices('t'), isNull);
    });
  });

  group('revoke', () {
    test('200 confirms, and the body carries token plus device id', () async {
      final rec = _Recorder();
      final svc = DeviceLinkService(client: rec.client(200, '{"ok":true}'));
      expect(await svc.revoke(subToken: 'sub-tok', deviceId: 'dev_1'), isTrue);
      expect(rec.last!.url.path, '/v1/link/revoke');
      expect(rec.lastJson, {'token': 'sub-tok', 'device_id': 'dev_1'});
    });

    test('anything else is a failure the screen can retry', () async {
      expect(
          await DeviceLinkService(client: _Recorder().client(404))
              .revoke(subToken: 't', deviceId: 'd'),
          isFalse);
      final broken = DeviceLinkService(
          client: MockClient((_) async => throw const SocketFailure()));
      expect(await broken.revoke(subToken: 't', deviceId: 'd'), isFalse);
    });
  });

  group('the approval sheet rides the shared sheet', () {
    Widget host(void Function(bool?) onClosed) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async => onClosed(await showLinkApprovalSheet(
                    context,
                    state: AppState(),
                    pairing: const DeepLinkPairing('abc'),
                  )),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('it is a HipSheet, not a private copy of one', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(host((_) {}));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(HipSheet), findsOneWidget);
      expect(find.text('Link this device?'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('cancelling answers no', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final answers = <bool?>[];
      await tester.pumpWidget(host(answers.add));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(answers, [false]);
      expect(find.byType(HipSheet), findsNothing);
    });
  });
}

/// Stand-in for a transport failure (the real one is platform-specific).
class SocketFailure implements Exception {
  const SocketFailure();
}
