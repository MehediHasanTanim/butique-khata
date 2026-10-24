import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';

/// A PIN as stored: never the PIN itself.
class PinHash {
  const PinHash({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;
}

/// Salted PBKDF2-HMAC-SHA256 hashing for the app-lock PIN (TD §6).
class PinHasher {
  const PinHasher({this.iterations = 100000, this.useIsolate = true});

  /// For tests: cheap and in-process.
  const PinHasher.fast() : iterations = 10, useIsolate = false;

  final int iterations;

  /// Hash on a background isolate so the keypad never freezes.
  final bool useIsolate;

  Future<PinHash> hash(String pin) async {
    final salt = BackupCrypto.randomBytes(16);
    final count = iterations;
    final bytes = useIsolate
        ? await Isolate.run(() => _derive(pin, salt, count))
        : await _derive(pin, salt, count);
    return PinHash(salt: salt, hash: bytes, iterations: count);
  }

  Future<bool> verify(String pin, PinHash stored) async {
    final salt = stored.salt;
    final count = stored.iterations;
    final candidate = useIsolate
        ? await Isolate.run(() => _derive(pin, salt, count))
        : await _derive(pin, salt, count);
    return _constantTimeEquals(candidate, stored.hash);
  }

  static Future<Uint8List> _derive(
    String pin,
    Uint8List salt,
    int iterations,
  ) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
