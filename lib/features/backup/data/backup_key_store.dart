import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';

/// Keeps the key derived from the backup passphrase so backups can be made
/// without asking for the passphrase each time. Only the *key* is stored (in
/// the Keystore/Keychain), never the passphrase: restoring on another phone
/// needs the passphrase typed again.
abstract class BackupKeyStore {
  Future<BackupKey?> load();
  Future<void> save(BackupKey key);
  Future<void> clear();
}

class SecureBackupKeyStore implements BackupKeyStore {
  SecureBackupKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _name = 'tk_backup_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<BackupKey?> load() async {
    final raw = await _storage.read(key: _name);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BackupKey(
        salt: Uint8List.fromList(base64Decode(json['salt'] as String)),
        bytes: Uint8List.fromList(base64Decode(json['key'] as String)),
        params: KdfParams(
          memoryKiB: json['mem'] as int,
          iterations: json['it'] as int,
          parallelism: json['par'] as int,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(BackupKey key) => _storage.write(
    key: _name,
    value: jsonEncode({
      'salt': base64Encode(key.salt),
      'key': base64Encode(key.bytes),
      'mem': key.params.memoryKiB,
      'it': key.params.iterations,
      'par': key.params.parallelism,
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _name);
}

/// For tests.
class InMemoryBackupKeyStore implements BackupKeyStore {
  BackupKey? _key;

  @override
  Future<BackupKey?> load() async => _key;

  @override
  Future<void> save(BackupKey key) async => _key = key;

  @override
  Future<void> clear() async => _key = null;
}
