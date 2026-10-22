import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/logging/app_log.dart';

/// The database file could not be decrypted with the stored key.
class WrongDatabaseKeyFailure extends Failure {
  const WrongDatabaseKeyFailure()
    : super('db.wrong_key', 'Database cannot be opened with the stored key');
}

/// The linked SQLite is not SQLCipher, so data would be stored unencrypted.
class EncryptionUnavailableFailure extends Failure {
  const EncryptionUnavailableFailure()
    : super('db.no_encryption', 'SQLCipher is not available in this build');
}

/// Supplies the 256-bit database key as 64 hex characters.
abstract class DatabaseKeyStore {
  /// Returns the existing key, generating and persisting one on first run.
  Future<String> loadOrCreateKey();
}

/// Keeps the key in the Android Keystore / iOS Keychain (TD §6).
class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyName = 'tk_db_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String> loadOrCreateKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null && existing.length == 64) return existing;
    final key = generateKey();
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  /// 32 random bytes from the OS CSPRNG, hex encoded.
  static String generateKey([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// Opens the encrypted application database.
class DatabaseOpener {
  const DatabaseOpener._();

  /// Default on-device location of the database file.
  static Future<File> defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'tailor_khata.db'));
  }

  /// Opens [file] with SQLCipher using [hexKey].
  ///
  /// By default the connection runs on a background isolate (TD §11); pass
  /// [inBackground] = false to fall back to the main isolate. Throws
  /// [WrongDatabaseKeyFailure] if the file exists but the key does not match,
  /// and [EncryptionUnavailableFailure] if SQLCipher is not linked.
  static Future<AppDatabase> open(
    File file, {
    required String hexKey,
    bool inBackground = true,
  }) async {
    void setup(sqlite.Database raw) => _applyKey(raw, hexKey);

    final executor = inBackground
        ? NativeDatabase.createInBackground(file, setup: setup)
        : NativeDatabase(file, setup: setup);
    final db = AppDatabase(executor);
    try {
      await db.customSelect('SELECT count(*) FROM sqlite_master').get();
    } catch (error) {
      await db.close();
      final failure = _mapOpenError(error);
      AppLog.e('db', 'Open failed (${failure.code})', error);
      throw failure;
    }
    return db;
  }

  static void _applyKey(sqlite.Database raw, String hexKey) {
    final version = raw.select('PRAGMA cipher_version');
    if (version.isEmpty || version.first.values.first == null) {
      throw const EncryptionUnavailableFailure();
    }
    raw.execute("PRAGMA key = \"x'$hexKey'\"");
  }

  static Failure _mapOpenError(Object error) {
    if (error is Failure) return error;
    if (error is sqlite.SqliteException) {
      // "file is not a database" (26) / "not authorized" (23) on a bad key.
      if (error.resultCode == 26 || error.resultCode == 23) {
        return const WrongDatabaseKeyFailure();
      }
    }
    final text = error.toString();
    if (text.contains('EncryptionUnavailableFailure')) {
      return const EncryptionUnavailableFailure();
    }
    if (text.contains('file is not a database')) {
      return const WrongDatabaseKeyFailure();
    }
    return Failure('db.open_failed', error.runtimeType.toString());
  }
}
