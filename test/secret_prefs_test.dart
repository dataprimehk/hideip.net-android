import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/secret_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates plaintext only after authenticated read-back', () async {
    const key = 'profile_blob';
    const secret = 'trojan://password@example.com:443';
    SharedPreferences.setMockInitialValues({'profiles_v1': secret});
    final vault = MemorySecureKeyVault();
    SecretPrefs.installKeyVaultForTesting(vault);

    expect(
      await SecretPrefs.readString(key, legacyPreferenceKey: 'profiles_v1'),
      secret,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('profiles_v1'), isFalse);
    final envelope = prefs.getString(SecretPrefs.encryptedPreferenceKey(key));
    expect(envelope, isNotNull);
    expect(envelope, isNot(contains('password')));
    expect(jsonDecode(envelope!)['v'], 1);
  });

  test('a secure-store failure preserves the legacy value for retry', () async {
    SharedPreferences.setMockInitialValues({'legacy': 'keep-me'});
    final vault = MemorySecureKeyVault()..failWrites = true;
    SecretPrefs.installKeyVaultForTesting(vault);

    expect(
      await SecretPrefs.readString('logical', legacyPreferenceKey: 'legacy'),
      'keep-me',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('legacy'), 'keep-me');
  });

  test(
    'tampering fails authentication instead of returning changed data',
    () async {
      SharedPreferences.setMockInitialValues({});
      SecretPrefs.installKeyVaultForTesting(MemorySecureKeyVault());
      await SecretPrefs.writeString('token', 'original');
      final prefs = await SharedPreferences.getInstance();
      final prefKey = SecretPrefs.encryptedPreferenceKey('token');
      final envelope =
          jsonDecode(prefs.getString(prefKey)!) as Map<String, dynamic>;
      final cipher = base64Decode(envelope['c'] as String);
      cipher[0] ^= 1;
      envelope['c'] = base64Encode(cipher);
      await prefs.setString(prefKey, jsonEncode(envelope));

      expect(await SecretPrefs.readString('token'), isNull);
    },
  );

  test(
    'each logical value receives a different device-protected key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final vault = MemorySecureKeyVault();
      SecretPrefs.installKeyVaultForTesting(vault);
      await SecretPrefs.writeString('one', 'same');
      await SecretPrefs.writeString('two', 'same');

      expect(vault.values, hasLength(2));
      expect(vault.values.values.toSet(), hasLength(2));
    },
  );
}
