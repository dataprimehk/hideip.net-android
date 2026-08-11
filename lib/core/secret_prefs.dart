import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'async_gate.dart';

abstract interface class SecureKeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecureKeyVault implements SecureKeyVault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'hideip_vpn_secrets_v1'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Authenticated encrypted values backed by SharedPreferences.
///
/// Large profile/subscription documents do not fit reliably in iOS Keychain,
/// so every logical value gets its own random AES-256 key in Keychain/Keystore
/// while only nonce + ciphertext + authentication tag live in preferences.
/// A legacy plaintext value is removed only after encrypted read-back matches.
class SecretPrefs {
  SecretPrefs._();

  static final _cipher = AesGcm.with256bits();
  static final Map<String, AsyncGate> _gates = {};
  static SecureKeyVault _vault = PlatformSecureKeyVault();

  @visibleForTesting
  static void installKeyVaultForTesting(SecureKeyVault vault) {
    _vault = vault;
    _gates.clear();
  }

  static String encryptedPreferenceKey(String logicalKey) =>
      'encrypted_value_v1_$logicalKey';

  static String _vaultKey(String logicalKey) => 'hideip.dek.v1.$logicalKey';

  static AsyncGate _gate(String logicalKey) =>
      _gates.putIfAbsent(logicalKey, AsyncGate.new);

  static Future<String?> readString(
    String logicalKey, {
    String? legacyPreferenceKey,
  }) => _gate(logicalKey).run(
    () => _readOrMigrate(
      logicalKey,
      legacyPreferenceKey: legacyPreferenceKey ?? logicalKey,
    ),
  );

  static Future<void> writeString(
    String logicalKey,
    String value, {
    String? legacyPreferenceKey,
  }) => _gate(logicalKey).run(() async {
    await _writeEncrypted(logicalKey, value);
    final verified = await _readEncrypted(logicalKey);
    if (verified != value) {
      throw StateError('Secure write verification failed.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPreferenceKey ?? logicalKey);
  });

  static Future<void> deleteString(
    String logicalKey, {
    String? legacyPreferenceKey,
  }) => _gate(logicalKey).run(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(encryptedPreferenceKey(logicalKey));
    await prefs.remove(legacyPreferenceKey ?? logicalKey);
    await _vault.delete(_vaultKey(logicalKey));
  });

  static Future<String?> _readOrMigrate(
    String logicalKey, {
    required String legacyPreferenceKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(encryptedPreferenceKey(logicalKey));
    if (encrypted != null) {
      try {
        final value = await _decrypt(logicalKey, encrypted);
        await prefs.remove(legacyPreferenceKey);
        return value;
      } catch (_) {
        // A legacy value may still be present after an interrupted migration.
        // It remains the recovery source until a verified rewrite succeeds.
      }
    }

    final legacy = prefs.getString(legacyPreferenceKey);
    if (legacy == null) return null;
    try {
      await _writeEncrypted(logicalKey, legacy);
      final verified = await _readEncrypted(logicalKey);
      if (verified == legacy) {
        await prefs.remove(legacyPreferenceKey);
        return verified;
      }
    } catch (_) {
      // Fail open for the one migration read: availability is preserved and
      // plaintext is deliberately left in place for the next retry.
    }
    return legacy;
  }

  static Future<void> _writeEncrypted(String logicalKey, String value) async {
    final key = await _getOrCreateKey(logicalKey);
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode(logicalKey),
    );
    final envelope = jsonEncode({
      'v': 1,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
    final prefs = await SharedPreferences.getInstance();
    final written = await prefs.setString(
      encryptedPreferenceKey(logicalKey),
      envelope,
    );
    if (!written) throw StateError('Encrypted preference write failed.');
  }

  static Future<String?> _readEncrypted(String logicalKey) async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = prefs.getString(encryptedPreferenceKey(logicalKey));
    if (envelope == null) return null;
    return _decrypt(logicalKey, envelope);
  }

  static Future<String> _decrypt(String logicalKey, String envelope) async {
    final decoded = jsonDecode(envelope) as Map<String, dynamic>;
    if (decoded['v'] != 1) throw const FormatException('Unknown envelope');
    final key = await _loadKey(logicalKey);
    if (key == null) throw const FormatException('Missing secure key');
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(decoded['c'] as String),
        nonce: base64Decode(decoded['n'] as String),
        mac: Mac(base64Decode(decoded['m'] as String)),
      ),
      secretKey: SecretKey(key),
      aad: utf8.encode(logicalKey),
    );
    return utf8.decode(clear);
  }

  static Future<List<int>> _getOrCreateKey(String logicalKey) async {
    final held = await _loadKey(logicalKey);
    if (held != null) return held;
    final fresh = SecretKeyData.random(length: 32).bytes;
    final encoded = base64Encode(fresh);
    await _vault.write(_vaultKey(logicalKey), encoded);
    final verified = await _vault.read(_vaultKey(logicalKey));
    if (verified != encoded) throw StateError('Secure key write failed.');
    return fresh;
  }

  static Future<List<int>?> _loadKey(String logicalKey) async {
    final raw = await _vault.read(_vaultKey(logicalKey));
    if (raw == null) return null;
    final bytes = base64Decode(raw);
    if (bytes.length != 32) throw const FormatException('Invalid secure key');
    return bytes;
  }
}

@visibleForTesting
class MemorySecureKeyVault implements SecureKeyVault {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Injected secure storage failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
