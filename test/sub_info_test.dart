import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/sub_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final fetchedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  group('SubInfo.fromHeaders', () {
    test('full header set parses every field', () {
      final info = SubInfo.fromHeaders({
        'subscription-userinfo':
            'upload=1024; download=2048; total=10737418240; expire=1800000000',
        'profile-title': 'QuietProxy Pro',
        'profile-update-interval': '12',
        'profile-web-page-url': 'https://panel.example/account',
        'support-url': 'https://t.me/quietproxy',
      }, fetchedAt: fetchedAt);
      expect(info, isNotNull);
      expect(info!.title, 'QuietProxy Pro');
      expect(info.uploadBytes, 1024);
      expect(info.downloadBytes, 2048);
      expect(info.totalBytes, 10737418240);
      expect(info.usedBytes, 1024 + 2048);
      expect(info.hasQuota, isTrue);
      expect(info.expire,
          DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000));
      expect(info.updateIntervalHours, 12);
      expect(info.webPageUrl, 'https://panel.example/account');
      expect(info.supportUrl, 'https://t.me/quietproxy');
      expect(info.fetchedAt, fetchedAt);
    });

    test('subset: only userinfo', () {
      final info = SubInfo.fromHeaders({
        'subscription-userinfo': 'download=500; total=1000',
      }, fetchedAt: fetchedAt);
      expect(info, isNotNull);
      expect(info!.title, isNull);
      expect(info.uploadBytes, isNull);
      expect(info.downloadBytes, 500);
      expect(info.totalBytes, 1000);
      expect(info.usedBytes, 500);
      expect(info.expire, isNull);
      expect(info.webPageUrl, isNull);
    });

    test('base64 profile-title is decoded', () {
      final encoded = base64.encode(utf8.encode('Провайдер'));
      final info = SubInfo.fromHeaders({
        'profile-title': 'base64:$encoded',
      }, fetchedAt: fetchedAt);
      expect(info!.title, 'Провайдер');
    });

    test('malformed userinfo pairs are ignored, valid ones kept', () {
      final info = SubInfo.fromHeaders({
        'subscription-userinfo':
            'upload= ; download=abc; total=2048; ; garbage; expire=0',
      }, fetchedAt: fetchedAt);
      expect(info, isNotNull);
      expect(info!.uploadBytes, isNull);
      expect(info.downloadBytes, isNull);
      expect(info.totalBytes, 2048);
      // expire=0 is the "no expiry" convention: not a date.
      expect(info.expire, isNull);
    });

    test('whitespace around values is tolerated', () {
      final info = SubInfo.fromHeaders({
        'subscription-userinfo': ' upload = 10 ;  total = 20 ',
      }, fetchedAt: fetchedAt);
      expect(info!.uploadBytes, 10);
      expect(info.totalBytes, 20);
    });

    test('no relevant headers returns null', () {
      expect(
          SubInfo.fromHeaders({
            'content-type': 'text/plain',
            'server': 'nginx',
          }, fetchedAt: fetchedAt),
          isNull);
    });
  });

  group('SubInfo.formatBytes', () {
    test('renders GB with one decimal', () {
      expect(SubInfo.formatBytes(1610612736), '1.5 GB');
      expect(SubInfo.formatBytes(0), '0.0 GB');
    });
  });

  group('SubInfoStore', () {
    test('round-trips a map keyed by subscription url', () async {
      SharedPreferences.setMockInitialValues({});
      const url = 'https://provider.example/sub/abc';
      final info = SubInfo.fromHeaders({
        'subscription-userinfo':
            'upload=1; download=2; total=100; expire=1800000000',
        'profile-title': 'My Plan',
        'profile-web-page-url': 'https://panel.example',
      }, fetchedAt: fetchedAt)!;
      await SubInfoStore.put(url, info);

      final loaded = await SubInfoStore.load();
      expect(loaded.keys, [url]);
      final r = loaded[url]!;
      expect(r.title, 'My Plan');
      expect(r.uploadBytes, 1);
      expect(r.downloadBytes, 2);
      expect(r.totalBytes, 100);
      expect(r.expire, info.expire);
      expect(r.webPageUrl, 'https://panel.example');
      expect(r.fetchedAt, fetchedAt);
    });

    test('put preserves other urls', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SubInfo(title: 'A', fetchedAt: fetchedAt);
      final b = SubInfo(title: 'B', fetchedAt: fetchedAt);
      await SubInfoStore.put('https://a.example', a);
      await SubInfoStore.put('https://b.example', b);
      final loaded = await SubInfoStore.load();
      expect(loaded.length, 2);
      expect(loaded['https://a.example']!.title, 'A');
      expect(loaded['https://b.example']!.title, 'B');
    });
  });
}
