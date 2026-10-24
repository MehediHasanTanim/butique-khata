import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';
import 'package:tailor_khata/features/backup/data/backup_key_store.dart';
import 'package:tailor_khata/features/backup/data/backup_service.dart';
import 'package:tailor_khata/features/backup/data/drive_auth.dart';
import 'package:tailor_khata/features/backup/data/drive_backup_store.dart';
import 'package:tailor_khata/features/backup/domain/backup_models.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

/// Where this phone keeps its files. Set in `bootstrap`; left null in tests
/// that do not exercise backups, which turns every backup feature off.
class BackupEnvironment {
  const BackupEnvironment({
    required this.backupDir,
    required this.mediaDir,
    required this.dbFile,
    required this.deviceKeyHex,
    this.appVersion = '1.0.0',
    this.useIsolate = true,
  });

  final Directory backupDir;
  final Directory mediaDir;
  final File dbFile;
  final String deviceKeyHex;
  final String appVersion;

  /// Heavy work runs on a background isolate; tests switch this off.
  final bool useIsolate;
}

final backupEnvironmentProvider = Provider<BackupEnvironment?>((ref) => null);

final backupKeyStoreProvider = Provider<BackupKeyStore>(
  (ref) => SecureBackupKeyStore(),
);

/// Null when the app runs without a backup environment (some tests).
final backupServiceProvider = Provider<BackupService?>((ref) {
  final env = ref.watch(backupEnvironmentProvider);
  if (env == null) return null;
  return BackupService(
    db: ref.watch(appDatabaseProvider),
    mediaDir: env.mediaDir,
    backupDir: env.backupDir,
    clock: ref.watch(clockProvider),
    keyStore: ref.watch(backupKeyStoreProvider),
    settings: ref.watch(settingsRepositoryProvider),
    appVersion: env.appVersion,
    deviceId: env.dbFile.path.hashCode.toRadixString(16),
    useIsolate: env.useIsolate,
    kdfParams: ref.watch(backupKdfParamsProvider),
  );
});

/// Tests lower the key-derivation cost; the app always uses the default.
final backupKdfParamsProvider = Provider<KdfParams>(
  (ref) => KdfParams.standard,
);

/// Bumped after every backup, so status and file lists reload.
class BackupRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final backupRevisionProvider = NotifierProvider<BackupRevision, int>(
  BackupRevision.new,
);

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((
  ref,
) async {
  ref.watch(backupRevisionProvider);
  final service = ref.watch(backupServiceProvider);
  if (service == null) return const BackupStatus(hasKey: true);
  return service.status();
});

final backupFilesProvider = Provider.autoDispose<List<BackupFileInfo>>((ref) {
  ref.watch(backupRevisionProvider);
  return ref.watch(backupServiceProvider)?.listBackups() ?? const [];
});

final backupAutoEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(backupRevisionProvider);
  return await ref.watch(backupServiceProvider)?.autoEnabled() ?? false;
});

/// Chooses a backup file to restore from.
abstract class BackupFilePicker {
  Future<File?> pick();
}

class SystemBackupFilePicker implements BackupFilePicker {
  const SystemBackupFilePicker();

  @override
  Future<File?> pick() async {
    // The share sheet and file managers often drop the custom extension, so
    // any file may be chosen; the app checks what it really is.
    final file = await openFile();
    return file == null ? null : File(file.path);
  }
}

final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => const SystemBackupFilePicker(),
);

/// Re-runs app start-up after a restore, so every screen reads the restored
/// database. Replaced in `bootstrap`.
final appRestartProvider = Provider<void Function()>((ref) => () {});

final backupPassphraseGeneratorProvider = Provider<String Function()>(
  (ref) =>
      () => generatePassphrase(),
);

/// Easy to read out and write down: five groups from an alphabet without
/// look-alike characters.
String generatePassphrase([Random? random]) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  final rng = random ?? Random.secure();
  String group() =>
      List.generate(4, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
  return List.generate(5, (_) => group()).join('-');
}

// ---- Google Drive copy (S6-02) ----------------------------------------------

final driveAuthProvider = Provider<DriveAuth>((ref) => GoogleDriveAuth());

final driveStoreProvider = Provider<DriveBackupStore>(
  (ref) => DriveBackupStore(ref.watch(driveAuthProvider)),
);

/// Setting key: copy every backup to Drive too.
const String driveEnabledKey = 'backup.drive';

final driveEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(backupRevisionProvider);
  return (await ref.watch(settingsRepositoryProvider).read(driveEnabledKey)) ==
      'true';
});

final driveEmailProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.watch(backupRevisionProvider);
  if (!(await ref.watch(driveEnabledProvider.future))) return null;
  return ref.watch(driveAuthProvider).email();
});

/// Copies [file] to Drive when the person turned that on. Never throws: a
/// backup that exists on the phone must not be reported as failed because the
/// internet was down. Returns whether the copy reached Drive (null if Drive
/// is off).
Future<bool?> copyToDriveIfEnabled({
  required SettingsRepository settings,
  required DriveBackupStore store,
  required File file,
}) async {
  if ((await settings.read(driveEnabledKey)) != 'true') return null;
  try {
    await store.upload(file);
    await store.prune();
    return true;
  } on DriveException {
    return false;
  }
}
