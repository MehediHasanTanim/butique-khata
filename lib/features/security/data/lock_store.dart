import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tailor_khata/features/security/data/pin_hasher.dart';

/// Everything about the app lock that survives a restart.
class LockConfig {
  const LockConfig({
    required this.pin,
    this.biometric = false,
    this.timeoutSeconds = 60,
    this.failures = 0,
    this.lockedUntil,
  });

  final PinHash pin;
  final bool biometric;

  /// How long the app may stay in the background before it locks. Zero locks
  /// as soon as the app is left.
  final int timeoutSeconds;

  /// Wrong PINs since the last success; kept across restarts so closing the
  /// app does not reset the lockout.
  final int failures;
  final DateTime? lockedUntil;

  LockConfig copyWith({
    PinHash? pin,
    bool? biometric,
    int? timeoutSeconds,
    int? failures,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) => LockConfig(
    pin: pin ?? this.pin,
    biometric: biometric ?? this.biometric,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    failures: failures ?? this.failures,
    lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
  );
}

abstract class LockStore {
  /// Null when no PIN is set.
  Future<LockConfig?> load();
  Future<void> save(LockConfig config);
  Future<void> clear();
}

/// Keeps the PIN hash in the Keystore / Keychain, not in the database: the
/// database is what the lock protects.
class SecureLockStore implements LockStore {
  SecureLockStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _name = 'tk_lock_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<LockConfig?> load() async {
    final raw = await _storage.read(key: _name);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final until = j['until'] as int?;
      return LockConfig(
        pin: PinHash(
          salt: Uint8List.fromList(base64Decode(j['salt'] as String)),
          hash: Uint8List.fromList(base64Decode(j['hash'] as String)),
          iterations: j['it'] as int,
        ),
        biometric: j['bio'] as bool? ?? false,
        timeoutSeconds: j['timeout'] as int? ?? 60,
        failures: j['fail'] as int? ?? 0,
        lockedUntil: until == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(until),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(LockConfig c) => _storage.write(
    key: _name,
    value: jsonEncode({
      'salt': base64Encode(c.pin.salt),
      'hash': base64Encode(c.pin.hash),
      'it': c.pin.iterations,
      'bio': c.biometric,
      'timeout': c.timeoutSeconds,
      'fail': c.failures,
      'until': c.lockedUntil?.millisecondsSinceEpoch,
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _name);
}

class InMemoryLockStore implements LockStore {
  InMemoryLockStore([this.config]);

  LockConfig? config;

  @override
  Future<LockConfig?> load() async => config;

  @override
  Future<void> save(LockConfig value) async => config = value;

  @override
  Future<void> clear() async => config = null;
}
