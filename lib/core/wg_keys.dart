import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A WireGuard identity: one Curve25519 keypair, generated on the device.
///
/// The private key never leaves the device. The backend only ever sees
/// [publicKey], which is an anonymous 32-byte random number: it identifies the
/// peer to the server without carrying anything personal. That is the whole
/// point of generating here instead of receiving a key from the server, and it
/// also lets two devices on one subscription run at the same time (one key
/// each) instead of fighting over a shared key.
///
/// Both halves are the WireGuard wire format: 32 raw bytes, base64 encoded,
/// which is always 44 characters ending in "=".
class WgKeyPair {
  final String privateKey;
  final String publicKey;

  const WgKeyPair({required this.privateKey, required this.publicKey});

  @override
  String toString() => 'WgKeyPair($publicKey)';
}

/// Generates and stores the device's WireGuard keypair.
class WgKeys {
  WgKeys._();

  /// Length of a raw Curve25519 key.
  static const int keyBytes = 32;

  /// Length of a base64 encoded 32-byte key, the form WireGuard and the
  /// backend contract both speak.
  static const int keyChars = 44;

  static final _x25519 = X25519();

  /// Generate a fresh keypair.
  ///
  /// The private key is clamped per the Curve25519 convention (clear the low
  /// three bits of the first byte, clear the top bit and set the second-highest
  /// bit of the last byte), which is what `wg genkey` does. Clamping is not
  /// cosmetic: an unclamped scalar can land on a small-order point, and peers
  /// that clamp at use time would derive a different public key than the one we
  /// registered, so the handshake would never complete.
  static Future<WgKeyPair> generate({Random? random}) async {
    final rnd = random ?? Random.secure();
    final priv = List<int>.generate(keyBytes, (_) => rnd.nextInt(256));
    clamp(priv);
    final pair = await _x25519.newKeyPairFromSeed(priv);
    final pub = await pair.extractPublicKey();
    return WgKeyPair(
      privateKey: base64.encode(priv),
      publicKey: base64.encode(pub.bytes),
    );
  }

  /// Apply the Curve25519 clamp to [key] in place (32 raw bytes).
  static void clamp(List<int> key) {
    key[0] &= 248;
    key[31] &= 127;
    key[31] |= 64;
  }

  /// Whether [value] is a well-formed WireGuard key: base64 of exactly 32
  /// bytes. The backend rejects anything else with a 400, so check before
  /// sending rather than after.
  static bool isValidKey(String value) {
    if (value.length != keyChars) return false;
    try {
      return base64.decode(value).length == keyBytes;
    } catch (_) {
      return false;
    }
  }
}

/// Persistence for the device keypair.
///
/// One keypair per install, created lazily the first time Speed mode is turned
/// on. It lives in shared_preferences next to the subscription pointers
/// ([PremiumSub]), which is the same storage class the app already trusts with
/// the purchase proof and the subscription URL, private to the app sandbox.
/// A key leaking off the device would only let someone else use the
/// subscription's WireGuard slot, not decrypt past traffic (WireGuard is
/// forward secret per session).
///
/// The identity must not be cloned across devices: two peers with one key
/// kick each other's connections off, which is the exact failure the
/// device-generated-key design exists to avoid. Android backup is disabled in
/// the manifest for that reason. iOS device restores can still carry
/// NSUserDefaults to a new phone; if both phones then run Speed mode at once,
/// the fallback probe degrades them to stealth rather than to a broken
/// tunnel, and turning Speed mode off and on mints a fresh identity.
class WgIdentity {
  static const _kPrivate = 'wg_private_key_v1';
  static const _kPublic = 'wg_public_key_v1';

  /// The stored keypair, or null when Speed mode has never been used.
  static Future<WgKeyPair?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final priv = prefs.getString(_kPrivate);
    final pub = prefs.getString(_kPublic);
    if (priv == null || pub == null) return null;
    if (!WgKeys.isValidKey(priv) || !WgKeys.isValidKey(pub)) return null;
    return WgKeyPair(privateKey: priv, publicKey: pub);
  }

  /// The stored keypair, generating and persisting one on first use.
  static Future<WgKeyPair> ensure() async {
    final held = await load();
    if (held != null) return held;
    final fresh = await WgKeys.generate();
    await save(fresh);
    return fresh;
  }

  static Future<void> save(WgKeyPair pair) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrivate, pair.privateKey);
    await prefs.setString(_kPublic, pair.publicKey);
  }

  /// Forget the keypair. Used when the subscription is gone for good, so the
  /// next subscriber on this device starts from a clean identity.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrivate);
    await prefs.remove(_kPublic);
  }
}
