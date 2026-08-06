import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/catalog.dart';
import 'package:hideip_vpn/core/provisioning.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testSeed = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
];
const _backendFixtureSignature =
    '3MPjAVtPnwAe+V5I55IZ9Tt+SsBAulzk0DOOc2xcHw29HjNc9Dis9XO7s3lCooznpcqUDwVrpGQQ4gEc+XwBDA==';

Map<String, dynamic> _catalogPayload({int epoch = 7}) => {
  'epoch': epoch,
  'generated_at': '2026-08-06T22:00:00Z',
  'servers': [
    {
      'id': 'node-b',
      'label': 'Beograd',
      'host': '203.0.113.20',
      'sort_weight': 20,
      'audience': 'all',
      'endpoints': [
        {
          'protocol': 'vless-reality',
          'port': 443,
          'public_key': 'PUBLIC-B',
          'short_id': 'bb22',
          'sni': 'b.test.invalid',
          'flow': 'xtls-rprx-vision',
        },
      ],
    },
    {
      'id': 'node-a',
      'label': 'Zürich',
      'host': '203.0.113.10',
      'sort_weight': 10,
      'audience': 'phone,desktop',
      'endpoints': [
        {
          'protocol': 'vless-reality',
          'port': 8443,
          'public_key': 'PUBLIC-A',
          'short_id': 'aa11',
          'sni': 'a.test.invalid',
          'flow': '',
        },
      ],
    },
  ],
};

Future<String> _signedCatalog({int epoch = 7}) async {
  final payload = _catalogPayload(epoch: epoch);
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_testSeed);
  final signature = await algorithm.sign(
    utf8.encode(canonicalCatalogJson(payload)),
    keyPair: keyPair,
  );
  return jsonEncode({...payload, 'signature': base64Encode(signature.bytes)});
}

ProxyProfile _cachedProfile({String uuid = 'uuid-local'}) => ProxyProfile(
  name: 'Cached',
  protocol: 'vless',
  server: '192.0.2.10',
  port: 443,
  outbound: {'type': 'vless', 'uuid': uuid},
  premium: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('canonical catalog JSON sorts keys without ASCII escaping', () {
    expect(
      canonicalCatalogJson({
        'z': 1,
        'a': {'ž': true, 'b': 2},
      }),
      '{"a":{"b":2,"ž":true},"z":1}',
    );
  });

  test(
    'embedded verifier key is the public half of the fixed test seed',
    () async {
      final keyPair = await Ed25519().newKeyPairFromSeed(_testSeed);
      final publicKey = await keyPair.extractPublicKey();
      expect(base64Encode(publicKey.bytes), catalogVerificationPublicKey);
    },
  );

  test(
    'signature fixture matches the backend canonical JSON contract',
    () async {
      final document =
          jsonDecode(await _signedCatalog()) as Map<String, dynamic>;
      expect(document['signature'], _backendFixtureSignature);
    },
  );

  test(
    'valid signature is accepted and a one-byte change is rejected',
    () async {
      final body = await _signedCatalog();
      final catalog = await decodeVerifiedCatalog(
        body,
        catalogVerificationPublicKey,
      );
      expect(catalog?.epoch, 7);
      expect(catalog?.servers.last.label, 'Zürich');

      final tampered = body.replaceFirst('203.0.113.20', '203.0.113.21');
      expect(
        await decodeVerifiedCatalog(tampered, catalogVerificationPublicKey),
        isNull,
      );
    },
  );

  test('catalog client stops at the first verified source', () async {
    final requests = <Uri>[];
    final sources = [
      Uri.parse('https://first.test/catalog'),
      Uri.parse('https://second.test/catalog'),
    ];
    final body = await _signedCatalog();
    final client = CatalogClient(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(body, 200);
      }),
      sources: sources,
      publicKey: catalogVerificationPublicKey,
    );

    expect((await client.fetch())?.epoch, 7);
    expect(requests, [sources.first]);
  });

  test(
    'catalog client tries the second source after the first fails',
    () async {
      final requests = <Uri>[];
      final sources = [
        Uri.parse('https://first.test/catalog'),
        Uri.parse('https://second.test/catalog'),
      ];
      final body = await _signedCatalog();
      final client = CatalogClient(
        client: MockClient((request) async {
          requests.add(request.url);
          return request.url == sources.first
              ? http.Response('', 503)
              : http.Response(body, 200);
        }),
        sources: sources,
        publicKey: catalogVerificationPublicKey,
      );

      expect((await client.fetch())?.epoch, 7);
      expect(requests, sources);
    },
  );

  test(
    'catalog client applies its timeout separately to each source',
    () async {
      final requests = <Uri>[];
      final sources = [
        Uri.parse('https://slow.test/catalog'),
        Uri.parse('https://fast.test/catalog'),
      ];
      final body = await _signedCatalog();
      final never = Completer<http.Response>();
      final client = CatalogClient(
        client: MockClient((request) {
          requests.add(request.url);
          if (request.url == sources.first) return never.future;
          return Future.value(http.Response(body, 200));
        }),
        sources: sources,
        publicKey: catalogVerificationPublicKey,
        timeout: const Duration(milliseconds: 1),
      );

      expect((await client.fetch())?.epoch, 7);
      expect(requests, sources);
    },
  );

  test(
    'bad signatures are discarded even when the response is otherwise OK',
    () async {
      final body = jsonDecode(await _signedCatalog()) as Map<String, dynamic>;
      body['signature'] = base64Encode(List<int>.filled(64, 0));
      final client = CatalogClient(
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
        sources: [Uri.parse('https://only.test/catalog')],
        publicKey: catalogVerificationPublicKey,
      );

      expect(await client.fetch(), isNull);
    },
  );

  test(
    'catalog client rejects rollback epochs and continues in order',
    () async {
      final requests = <Uri>[];
      final sources = [
        Uri.parse('https://stale.test/catalog'),
        Uri.parse('https://current.test/catalog'),
      ];
      final stale = await _signedCatalog(epoch: 5);
      final current = await _signedCatalog(epoch: 9);
      final client = CatalogClient(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            request.url == sources.first ? stale : current,
            200,
          );
        }),
        sources: sources,
        publicKey: catalogVerificationPublicKey,
      );

      expect((await client.fetch(minimumEpoch: 7))?.epoch, 9);
      expect(requests, sources);
    },
  );

  test('identity is recovered only from one consistent premium UUID', () {
    final identity = catalogIdentityFromProfiles(
      'https://api.test/v1/sub/sub-token',
      [_cachedProfile()],
    );
    expect(identity?.uuid, 'uuid-local');
    expect(identity?.subToken, 'sub-token');
    expect(
      catalogIdentityMatchesSubscription(
        identity!,
        'https://api.test/v1/sub/sub-token',
      ),
      isTrue,
    );
    expect(
      catalogIdentityMatchesSubscription(
        identity,
        'https://api.test/v1/sub/other-token',
      ),
      isFalse,
    );

    expect(
      catalogIdentityFromProfiles('https://api.test/v1/sub/sub-token', [
        _cachedProfile(),
        _cachedProfile(uuid: 'different'),
      ]),
      isNull,
    );
    expect(
      catalogIdentityFromProfiles('http://api.test/v1/sub/token', [
        _cachedProfile(),
      ]),
      isNull,
    );
  });

  test(
    'local assembly filters audience and protocol and preserves ordering',
    () async {
      final parsed = await decodeVerifiedCatalog(
        await _signedCatalog(),
        catalogVerificationPublicKey,
      );
      final servers = [
        ...parsed!.servers,
        const CatalogServer(
          id: 'extension-only',
          label: 'Extension',
          host: '203.0.113.30',
          sortWeight: 0,
          audience: 'extension',
          endpoints: [
            CatalogEndpoint(
              protocol: 'vless-reality',
              port: 443,
              publicKey: 'PUBLIC-C',
              shortId: '',
              sni: 'c.test.invalid',
              flow: '',
            ),
          ],
        ),
        const CatalogServer(
          id: 'wireguard-only',
          label: 'WireGuard',
          host: '203.0.113.40',
          sortWeight: 1,
          audience: 'phone',
          endpoints: [
            CatalogEndpoint(
              protocol: 'wireguard',
              port: 51820,
              publicKey: 'WG-PUBLIC',
              shortId: '',
              sni: '',
              flow: '',
            ),
          ],
        ),
      ];
      final catalog = CatalogDocument(
        epoch: parsed.epoch,
        generatedAt: parsed.generatedAt,
        servers: servers,
      );

      final profiles = profilesFromCatalog(
        catalog,
        const CatalogIdentity(uuid: 'uuid-local', subToken: 'token-local'),
      );
      expect(profiles.map((profile) => profile.name), ['Zürich', 'Beograd']);
      expect(profiles.every((profile) => profile.premium), isTrue);
      expect(profiles.first.outbound['uuid'], 'uuid-local');
      expect(profiles.first.outbound['server'], '203.0.113.10');
      expect(profiles.first.outbound['server_port'], 8443);
      expect(profiles.first.outbound['tls'], {
        'enabled': true,
        'server_name': 'a.test.invalid',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {
          'enabled': true,
          'public_key': 'PUBLIC-A',
          'short_id': 'aa11',
        },
      });
    },
  );

  test(
    'premium identity and catalog epoch persist and clear together',
    () async {
      const identity = CatalogIdentity(uuid: 'uuid-local', subToken: 'token');
      await PremiumSub.saveIdentity(identity);
      await PremiumSub.saveCatalogEpoch(12);
      expect((await PremiumSub.identity())?.uuid, 'uuid-local');
      expect((await PremiumSub.identity())?.subToken, 'token');
      expect(await PremiumSub.catalogEpoch(), 12);

      await PremiumSub.saveIdentity(
        const CatalogIdentity(uuid: 'uuid-next', subToken: 'next-token'),
      );
      expect(await PremiumSub.catalogEpoch(), isNull);

      await PremiumSub.clear();
      expect(await PremiumSub.identity(), isNull);
      expect(await PremiumSub.catalogEpoch(), isNull);
    },
  );

  test(
    'provisioning falls back to the unchanged legacy subscription path',
    () async {
      await PremiumSub.saveIdentity(
        const CatalogIdentity(uuid: 'uuid-local', subToken: 'sub-token'),
      );
      final source = Uri.parse('https://mirror.test/catalog');
      final legacy = Uri.parse('https://api.test/v1/sub/sub-token');
      final requests = <Uri>[];
      final service = ProvisioningService(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url == source) return http.Response('', 503);
          return http.Response(
            'vless://uuid-local@203.0.113.50:443'
            '?security=reality&pbk=LEGACY&sni=legacy.test.invalid#Legacy',
            200,
          );
        }),
        catalogSources: [source],
        catalogPublicKey: catalogVerificationPublicKey,
      );

      final refresh = await service.refreshProfiles(legacy.toString());
      expect(refresh?.profiles?.single.name, 'Legacy');
      expect(refresh?.catalogEpoch, isNull);
      expect(requests, [source, legacy]);
    },
  );

  test(
    'existing premium cache bootstraps identity and local catalog profiles',
    () async {
      final source = Uri.parse('https://mirror.test/catalog');
      final requests = <Uri>[];
      final service = ProvisioningService(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(await _signedCatalog(), 200);
        }),
        catalogSources: [source],
        catalogPublicKey: catalogVerificationPublicKey,
      );

      final refresh = await service.refreshProfiles(
        'https://api.test/v1/sub/sub-token',
        cachedProfiles: [_cachedProfile()],
      );
      expect(refresh?.catalogEpoch, 7);
      expect(refresh?.profiles?.map((profile) => profile.name), [
        'Zürich',
        'Beograd',
      ]);
      expect((await PremiumSub.identity())?.uuid, 'uuid-local');
      expect((await PremiumSub.identity())?.subToken, 'sub-token');
      expect(requests, [source]);
    },
  );

  test(
    'all catalog and legacy failures leave the profile cache in use',
    () async {
      await PremiumSub.saveIdentity(
        const CatalogIdentity(uuid: 'uuid-local', subToken: 'sub-token'),
      );
      final cached = [_cachedProfile()];
      final service = ProvisioningService(
        client: MockClient((_) async => http.Response('', 503)),
        catalogSources: [
          Uri.parse('https://first.test/catalog'),
          Uri.parse('https://second.test/catalog'),
        ],
        catalogPublicKey: catalogVerificationPublicKey,
      );

      final refresh = await service.refreshProfiles(
        'https://api.test/v1/sub/sub-token',
        cachedProfiles: cached,
      );
      final effectiveProfiles = refresh?.profiles ?? cached;
      expect(refresh, isNull);
      expect(effectiveProfiles, same(cached));
    },
  );

  test('bad signature plus legacy failure preserves cache and epoch', () async {
    await PremiumSub.saveIdentity(
      const CatalogIdentity(uuid: 'uuid-local', subToken: 'sub-token'),
    );
    await PremiumSub.saveCatalogEpoch(7);
    final badDocument =
        jsonDecode(await _signedCatalog(epoch: 8)) as Map<String, dynamic>;
    badDocument['signature'] = base64Encode(List<int>.filled(64, 0));
    final cached = [_cachedProfile()];
    final source = Uri.parse('https://mirror.test/catalog');
    final legacy = Uri.parse('https://api.test/v1/sub/sub-token');
    final requests = <Uri>[];
    final service = ProvisioningService(
      client: MockClient((request) async {
        requests.add(request.url);
        return request.url == source
            ? http.Response(jsonEncode(badDocument), 200)
            : http.Response('', 503);
      }),
      catalogSources: [source],
      catalogPublicKey: catalogVerificationPublicKey,
    );

    final refresh = await service.refreshProfiles(
      legacy.toString(),
      cachedProfiles: cached,
    );
    final effectiveProfiles = refresh?.profiles ?? cached;
    expect(refresh, isNull);
    expect(effectiveProfiles, same(cached));
    expect(await PremiumSub.catalogEpoch(), 7);
    expect(requests, [source, legacy]);
  });

  test('an unchanged verified epoch does not call the legacy path', () async {
    await PremiumSub.saveIdentity(
      const CatalogIdentity(uuid: 'uuid-local', subToken: 'sub-token'),
    );
    await PremiumSub.saveCatalogEpoch(7);
    final requests = <Uri>[];
    final source = Uri.parse('https://mirror.test/catalog');
    final service = ProvisioningService(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(await _signedCatalog(), 200);
      }),
      catalogSources: [source],
      catalogPublicKey: catalogVerificationPublicKey,
    );

    final refresh = await service.refreshProfiles(
      'https://api.test/v1/sub/sub-token',
      cachedProfiles: [_cachedProfile()],
    );
    expect(refresh?.changed, isFalse);
    expect(refresh?.catalogEpoch, 7);
    expect(requests, [source]);
  });
}
