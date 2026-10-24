import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/backup/backup_bundle.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/backup/data/backup_key_store.dart';
import 'package:tailor_khata/features/backup/domain/backup_models.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

/// Makes and restores encrypted backups (B-2, B-3, TD §8).
///
/// A backup is one `.tkbackup` file: a bundle of `manifest.json`, a snapshot
/// of the database and the photos, encrypted with a key derived from the
/// backup passphrase. The database snapshot is written *already encrypted*
/// with that same key (SQLCipher export), so no readable copy of the data
/// ever touches the disk, and it is re-keyed for the local phone on restore.
class BackupService {
  BackupService({
    required this.db,
    required this.mediaDir,
    required this.backupDir,
    required this.clock,
    required this.keyStore,
    required this.settings,
    this.appVersion = '1.0.0',
    this.deviceId = 'device',
    this.useIsolate = true,
    this.kdfParams = KdfParams.standard,
  });

  final AppDatabase db;
  final Directory mediaDir;
  final Directory backupDir;
  final Clock clock;
  final BackupKeyStore keyStore;
  final SettingsRepository settings;
  final String appVersion;
  final String deviceId;

  /// Run heavy work (key derivation, encryption, SQL export) on a background
  /// isolate. Tests switch this off.
  final bool useIsolate;
  final KdfParams kdfParams;

  static const String keyLastAt = 'backup.last_at';
  static const String keyAutoEnabled = 'backup.auto';
  static const String extension = '.tkbackup';

  /// A backup older than this is made again on the next app start.
  static const Duration autoInterval = Duration(hours: 24);

  /// How many automatic backups are kept on the phone.
  static const int keepAutomatic = 5;

  static const Duration safetyCopyLife = Duration(days: 7);

  // ---- passphrase ---------------------------------------------------------

  Future<bool> hasKey() async => (await keyStore.load()) != null;

  /// Derives and stores the key for [passphrase]. Backups made earlier with
  /// another passphrase still need that old one to be restored.
  Future<void> setPassphrase(String passphrase) async {
    final params = kdfParams;
    final key = useIsolate
        ? await Isolate.run(
            () => BackupCrypto.deriveKey(passphrase, params: params),
          )
        : await BackupCrypto.deriveKey(passphrase, params: params);
    await keyStore.save(key);
  }

  // ---- status -------------------------------------------------------------

  Future<BackupStatus> status() async {
    final raw = await settings.read(keyLastAt);
    final millis = int.tryParse(raw ?? '');
    return BackupStatus(
      lastAt: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis),
      hasKey: await hasKey(),
    );
  }

  Future<bool> autoEnabled() async =>
      (await settings.read(keyAutoEnabled)) != 'false';

  Future<void> setAutoEnabled(bool value) =>
      settings.write(keyAutoEnabled, '$value');

  /// Backup files kept on this phone, newest first.
  List<BackupFileInfo> listBackups() {
    if (!backupDir.existsSync()) return const [];
    final files =
        backupDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(extension))
            .map(
              (f) => BackupFileInfo(
                file: f,
                modified: f.lastModifiedSync(),
                sizeBytes: f.lengthSync(),
              ),
            )
            .toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  // ---- create -------------------------------------------------------------

  /// Makes a backup now. Throws [BackupFailure] (`backup.no_key` until a
  /// passphrase is set).
  Future<BackupResult> createBackup({int? keep}) async {
    final key = await keyStore.load();
    if (key == null) throw const BackupFailure(BackupFailure.noKey);

    final work = Directory.systemTemp.createTempSync('tk_backup_work');
    try {
      final snapshot = File(p.join(work.path, 'db.sqlite'));
      await _snapshotDatabase(snapshot, key.hex);

      final counts = await _counts(db);
      final media = <File>[
        if (mediaDir.existsSync()) ...mediaDir.listSync().whereType<File>(),
      ].where((f) => BackupBundle.isAllowedName('media/${p.basename(f.path)}'));

      final hashes = <String, String>{
        'db.sqlite': await BackupBundle.sha256Of(snapshot),
        for (final f in media)
          'media/${p.basename(f.path)}': await BackupBundle.sha256Of(f),
      };
      final manifest = BackupManifest(
        schemaVersion: await _userVersion(db),
        appVersion: appVersion,
        createdAt: clock.now(),
        deviceId: deviceId,
        counts: counts,
        files: hashes,
      );

      final bundle = File(p.join(work.path, 'bundle.bin'));
      BackupBundle.write(bundle, [
        BundleEntry.bytes('manifest.json', utf8.encode(manifest.encode())),
        BundleEntry.file('db.sqlite', snapshot),
        for (final f in media)
          BundleEntry.file('media/${p.basename(f.path)}', f),
      ]);

      backupDir.createSync(recursive: true);
      final out = File(p.join(backupDir.path, _fileName(manifest.createdAt)));
      await BackupCrypto.encryptFile(bundle, out, key, inIsolate: useIsolate);

      await settings.write(
        keyLastAt,
        '${manifest.createdAt.millisecondsSinceEpoch}',
      );
      if (keep != null) _prune(keep);
      return BackupResult(file: out, manifest: manifest);
    } on BackupFailure {
      rethrow;
    } on Object catch (error) {
      AppLog.e('backup', 'Backup failed', error);
      throw const BackupFailure(BackupFailure.failed);
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  /// Makes a backup if a passphrase is set, automatic backups are on, and the
  /// last one is more than a day old (opportunistic: run at app start and when
  /// the app returns to the foreground). Returns null when nothing was needed.
  Future<BackupResult?> maybeAutoBackup() async {
    if (!await autoEnabled() || !await hasKey()) return null;
    final last = (await status()).lastAt;
    if (last != null && clock.now().difference(last) < autoInterval) {
      return null;
    }
    try {
      return await createBackup(keep: keepAutomatic);
    } on BackupFailure catch (e) {
      AppLog.w('backup', 'Automatic backup skipped (${e.code})');
      return null;
    }
  }

  String _fileName(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tailor_khata_${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}$extension';
  }

  void _prune(int keep) {
    final files = listBackups();
    for (final old in files.skip(keep)) {
      try {
        old.file.deleteSync();
      } on FileSystemException {
        // A backup we cannot delete is not worth failing over.
      }
    }
  }

  /// Writes an encrypted copy of the live database to [target], keyed with
  /// [keyHex], using the app's own connection (a consistent snapshot).
  Future<void> _snapshotDatabase(File target, String keyHex) async {
    final version = await _userVersion(db);
    final path = target.path.replaceAll("'", "''");
    await db.customStatement(
      "ATTACH DATABASE '$path' AS bk KEY \"x'$keyHex'\"",
    );
    try {
      await db.customSelect("SELECT sqlcipher_export('bk')").get();
      await db.customStatement('PRAGMA bk.user_version = $version');
    } finally {
      await db.customStatement('DETACH DATABASE bk');
    }
  }

  static Future<int> _userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      );

  static Future<Map<String, int>> _counts(AppDatabase db) async {
    final row = await db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM customer WHERE deleted_at IS NULL) AS customers, '
          '(SELECT COUNT(*) FROM customer_order WHERE deleted_at IS NULL) AS orders, '
          '(SELECT COUNT(*) FROM measurement_set) AS measurements, '
          '(SELECT COUNT(*) FROM payment) AS payments, '
          '(SELECT COUNT(*) FROM attachment) AS attachments',
        )
        .getSingle();
    return {
      for (final name in const [
        'customers',
        'orders',
        'measurements',
        'payments',
        'attachments',
      ])
        name: row.read<int>(name),
    };
  }

  // ---- restore ------------------------------------------------------------

  /// Replaces the data on this phone with the contents of [backupFile].
  ///
  /// Nothing is touched until the file has been decrypted, unpacked, checked
  /// against its manifest and opened successfully by this version of the app.
  /// Then the live database is swapped for the restored one (the old one is
  /// kept as `pre_restore_<time>.db` for a week). [closeDatabase] must close
  /// the app's connection; the caller reopens the database afterwards.
  ///
  /// Throws [BackupFailure]; the current data is untouched in every case but
  /// an I/O error during the final swap, which is rolled back.
  Future<RestoreResult> restore({
    required File backupFile,
    required String passphrase,
    required File liveDbFile,
    required String deviceKeyHex,
    required Future<void> Function() closeDatabase,
  }) async {
    final work = Directory.systemTemp.createTempSync('tk_restore_work');
    try {
      // 1. Decrypt.
      final bundleFile = File(p.join(work.path, 'bundle.bin'));
      final BackupKey key;
      try {
        key = await BackupCrypto.decryptFile(
          backupFile,
          bundleFile,
          passphrase,
          inIsolate: useIsolate,
        );
      } on BackupCryptoException catch (e) {
        throw BackupFailure(switch (e.error) {
          BackupCryptoError.notABackup => BackupFailure.notABackup,
          BackupCryptoError.unsupportedVersion => BackupFailure.newerVersion,
          BackupCryptoError.authenticationFailed =>
            BackupFailure.wrongPassphrase,
          BackupCryptoError.truncated => BackupFailure.corrupt,
          BackupCryptoError.badParameters => BackupFailure.corrupt,
        });
      } on FileSystemException {
        throw const BackupFailure(BackupFailure.notABackup);
      }

      // 2. Unpack and check against the manifest.
      final unpacked = Directory(p.join(work.path, 'unpacked'))..createSync();
      final BackupManifest manifest;
      try {
        final names = BackupBundle.read(bundleFile, unpacked);
        if (names.isEmpty || names.first != 'manifest.json') {
          throw const BackupFailure(BackupFailure.corrupt);
        }
        manifest = BackupManifest.decode(
          File(p.join(unpacked.path, 'manifest.json')).readAsStringSync(),
        );
        if (manifest.format != BackupManifest.currentFormat) {
          throw const BackupFailure(BackupFailure.newerVersion);
        }
        final listed = manifest.files.keys.toSet();
        final present = names.where((n) => n != 'manifest.json').toSet();
        if (!listed.containsAll(present) ||
            !present.containsAll(listed) ||
            !present.contains('db.sqlite')) {
          throw const BackupFailure(BackupFailure.corrupt);
        }
        for (final entry in manifest.files.entries) {
          final actual = await BackupBundle.sha256Of(
            File(p.join(unpacked.path, entry.key)),
          );
          if (actual != entry.value) {
            throw const BackupFailure(BackupFailure.corrupt);
          }
        }
      } on BundleException {
        throw const BackupFailure(BackupFailure.corrupt);
      } on FormatException {
        throw const BackupFailure(BackupFailure.corrupt);
      } on TypeError {
        throw const BackupFailure(BackupFailure.corrupt);
      }
      if (manifest.schemaVersion > AppDatabase.currentSchemaVersion) {
        throw const BackupFailure(BackupFailure.newerVersion);
      }

      // 3. Re-key the snapshot for this phone, next to the live database so
      //    the final swap is a same-folder rename.
      liveDbFile.parent.createSync(recursive: true);
      final incoming = File('${liveDbFile.path}.incoming');
      if (incoming.existsSync()) incoming.deleteSync();
      final job = _RekeyJob(
        source: p.join(unpacked.path, 'db.sqlite'),
        sourceKeyHex: key.hex,
        target: incoming.path,
        targetKeyHex: deviceKeyHex,
        userVersion: manifest.schemaVersion,
      );
      try {
        if (useIsolate) {
          await Isolate.run(() => _rekey(job));
        } else {
          _rekey(job);
        }

        // 4. Open it like the app will: runs forward migrations and proves
        //    it is a usable database with the expected contents.
        final trial = await DatabaseOpener.open(
          incoming,
          hexKey: deviceKeyHex,
          inBackground: false,
        );
        try {
          final counts = await _counts(trial);
          for (final entry in manifest.counts.entries) {
            if (counts[entry.key] != entry.value) {
              throw const BackupFailure(BackupFailure.corrupt);
            }
          }
        } finally {
          await trial.close();
        }
      } on BackupFailure {
        _deleteQuietly(incoming);
        rethrow;
      } on Object catch (error) {
        _deleteQuietly(incoming);
        AppLog.e('backup', 'Restore check failed', error);
        throw const BackupFailure(BackupFailure.corrupt);
      }

      // 5. Swap. From here on, failures roll back.
      await closeDatabase();
      File? safety;
      final stamp = _stamp(clock.now());
      try {
        if (liveDbFile.existsSync()) {
          safety = File(
            p.join(liveDbFile.parent.path, 'pre_restore_$stamp.db'),
          );
          liveDbFile.renameSync(safety.path);
        }
        for (final extra in const ['-wal', '-shm', '-journal']) {
          _deleteQuietly(File('${liveDbFile.path}$extra'));
        }
        incoming.renameSync(liveDbFile.path);
      } on Object catch (error) {
        AppLog.e('backup', 'Swap failed, rolling back', error);
        if (safety != null && safety.existsSync() && !liveDbFile.existsSync()) {
          safety.renameSync(liveDbFile.path);
        }
        _deleteQuietly(incoming);
        throw const BackupFailure(BackupFailure.failed);
      }

      // 6. Photos: add the ones this phone does not have.
      final restoredMedia = Directory(p.join(unpacked.path, 'media'));
      if (restoredMedia.existsSync()) {
        mediaDir.createSync(recursive: true);
        for (final f in restoredMedia.listSync().whereType<File>()) {
          final target = File(p.join(mediaDir.path, p.basename(f.path)));
          if (!target.existsSync()) f.copySync(target.path);
        }
      }

      _pruneSafetyCopies(liveDbFile.parent);
      return RestoreResult(manifest: manifest, safetyCopy: safety);
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }

  void _pruneSafetyCopies(Directory dir) {
    final cutoff = clock.now().subtract(safetyCopyLife);
    for (final f in dir.listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (name.startsWith('pre_restore_') &&
          name.endsWith('.db') &&
          f.lastModifiedSync().isBefore(cutoff)) {
        _deleteQuietly(f);
      }
    }
  }

  static void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Best effort.
    }
  }
}

class _RekeyJob {
  const _RekeyJob({
    required this.source,
    required this.sourceKeyHex,
    required this.target,
    required this.targetKeyHex,
    required this.userVersion,
  });

  final String source;
  final String sourceKeyHex;
  final String target;
  final String targetKeyHex;
  final int userVersion;
}

/// Copies the snapshot into a new database encrypted with the local key.
void _rekey(_RekeyJob job) {
  final src = sqlite.sqlite3.open(job.source);
  try {
    src.execute("PRAGMA key = \"x'${job.sourceKeyHex}'\"");
    // Reading proves the key is right before anything else happens.
    src.select('SELECT count(*) FROM sqlite_master');
    final target = job.target.replaceAll("'", "''");
    src.execute(
      "ATTACH DATABASE '$target' AS dst KEY \"x'${job.targetKeyHex}'\"",
    );
    src.select("SELECT sqlcipher_export('dst')");
    src.execute('PRAGMA dst.user_version = ${job.userVersion}');
    src.execute('DETACH DATABASE dst');
  } finally {
    src.close();
  }
}
