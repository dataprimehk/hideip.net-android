import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/wg_keys.dart';

void main() {
  group('WgKeys.generate', () {
    test('produces WireGuard-shaped base64 keys', () async {
      final pair = await WgKeys.generate();
      // The wire format both `wg` and the backend contract use: 32 raw bytes
      // base64 encoded, which is always 44 characters.
      expect(pair.privateKey.length, 44);
      expect(pair.publicKey.length, 44);
      expect(base64.decode(pair.privateKey).length, 32);
      expect(base64.decode(pair.publicKey).length, 32);
      expect(WgKeys.isValidKey(pair.privateKey), isTrue);
      expect(WgKeys.isValidKey(pair.publicKey), isTrue);
    });

    test('private key is clamped per the Curve25519 convention', () async {
      // Ten draws, because clamping only shows on the bits it touches and a
      // single random key could satisfy them by chance.
      for (var i = 0; i < 10; i++) {
        final pair = await WgKeys.generate();
        final priv = base64.decode(pair.privateKey);
        expect(priv[0] & 7, 0, reason: 'low three bits of byte 0 must be clear');
        expect(priv[31] & 128, 0, reason: 'top bit of byte 31 must be clear');
        expect(priv[31] & 64, 64, reason: 'bit 6 of byte 31 must be set');
      }
    });

    test('two generated keypairs differ', () async {
      final a = await WgKeys.generate();
      final b = await WgKeys.generate();
      expect(a.privateKey, isNot(b.privateKey));
      expect(a.publicKey, isNot(b.publicKey));
    });

    test('public key is the X25519 public key of the private key', () async {
      // The backend only ever receives the public half, so it must really be
      // derived from the private half we keep; otherwise the handshake fails
      // with no way to tell why from the client side.
      final pair = await WgKeys.generate();
      final priv = base64.decode(pair.privateKey);
      final derived =
          await (await X25519().newKeyPairFromSeed(priv)).extractPublicKey();
      expect(base64.encode(derived.bytes), pair.publicKey);
    });

    test('a seeded generator yields a reproducible key', () async {
      final a = await WgKeys.generate(random: Random(42));
      final b = await WgKeys.generate(random: Random(42));
      expect(a.privateKey, b.privateKey);
      expect(a.publicKey, b.publicKey);
    });
  });

  group('WgKeys.clamp', () {
    test('clears and sets exactly the WireGuard bits', () {
      final key = List<int>.filled(32, 0xFF);
      WgKeys.clamp(key);
      expect(key[0], 0xF8); // 255 & 248
      expect(key[31], 0x7F); // 255 & 127, bit 6 already set
      // Untouched bytes stay as they were.
      expect(key[15], 0xFF);
    });

    test('sets bit 6 on a zero key', () {
      final key = List<int>.filled(32, 0);
      WgKeys.clamp(key);
      expect(key[0], 0);
      expect(key[31], 64);
    });
  });

  group('WgKeys.isValidKey', () {
    test('rejects wrong lengths and non-base64', () {
      expect(WgKeys.isValidKey(''), isFalse);
      expect(WgKeys.isValidKey('short'), isFalse);
      // Base64 of 31 bytes, so the wrong number of raw bytes.
      expect(WgKeys.isValidKey(base64.encode(List.filled(31, 1))), isFalse);
      // Base64 of 33 bytes.
      expect(WgKeys.isValidKey(base64.encode(List.filled(33, 1))), isFalse);
      // Right length, but not valid base64 characters.
      expect(WgKeys.isValidKey('!' * 44), isFalse);
    });

    test('accepts a real 32-byte key', () {
      expect(WgKeys.isValidKey(base64.encode(List.filled(32, 7))), isTrue);
    });
  });
}
