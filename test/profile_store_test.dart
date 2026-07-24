import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/profile_store.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('premium flag survives a save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    await ProfileStore.save([
      const ProxyProfile(
          name: 'Frankfurt',
          protocol: 'vless',
          server: '1.2.3.4',
          port: 443,
          outbound: {'type': 'vless'},
          premium: true),
      const ProxyProfile(
          name: 'my server',
          protocol: 'vless',
          server: '5.6.7.8',
          port: 443,
          outbound: {'type': 'vless'}),
    ]);
    final loaded = await ProfileStore.load();
    expect(loaded.map((p) => p.premium).toList(), [true, false]);
  });

  test('subUrl survives a save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    await ProfileStore.save([
      const ProxyProfile(
          name: 'provider node',
          protocol: 'vless',
          server: '1.2.3.4',
          port: 443,
          outbound: {'type': 'vless'},
          subUrl: 'https://provider.example/sub/abc'),
      const ProxyProfile(
          name: 'pasted link',
          protocol: 'vless',
          server: '5.6.7.8',
          port: 443,
          outbound: {'type': 'vless'}),
    ]);
    final loaded = await ProfileStore.load();
    expect(loaded.map((p) => p.subUrl).toList(),
        ['https://provider.example/sub/abc', null]);
  });

  test('lists saved before the flag migrate via the old name prefix',
      () async {
    SharedPreferences.setMockInitialValues({
      'profiles_v1': jsonEncode([
        {
          'name': 'hideip.net Premium',
          'protocol': 'vless',
          'server': '1.2.3.4',
          'port': 443,
          'outbound': {'type': 'vless'},
        },
        {
          'name': 'my server',
          'protocol': 'vless',
          'server': '5.6.7.8',
          'port': 443,
          'outbound': {'type': 'vless'},
        },
      ]),
    });
    final loaded = await ProfileStore.load();
    expect(loaded.map((p) => p.premium).toList(), [true, false]);
  });
}
