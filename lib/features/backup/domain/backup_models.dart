import 'dart:convert';
import 'dart:io';

import 'package:tailor_khata/core/errors/result.dart';

/// Why a backup or restore did not happen. Codes are stable so the UI can
/// show a plain-language message for each.
class BackupFailure extends Failure {
  const BackupFailure(super.code, [super.message]);

  /// No backup passphrase has been set up yet.
  static const noKey = 'backup.no_key';

  /// The file is not a Tailor Khata backup.
  static const notABackup = 'backup.not_a_backup';

  /// Wrong passphrase, or the file was changed after it was made.
  static const wrongPassphrase = 'backup.wrong_passphrase';

  /// The file is damaged or incomplete.
  static const corrupt = 'backup.corrupt';

  /// Made by a newer version of the app: update first.
  static const newerVersion = 'backup.newer_version';

  /// Anything else; the current data was not touched.
  static const failed = 'backup.failed';
}

/// What a backup contains, written inside every backup file.
class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.deviceId,
    required this.counts,
    required this.files,
    this.format = currentFormat,
  });

  static const int currentFormat = 1;

  final int format;
  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final String deviceId;

  /// Row counts at backup time: `customers`, `orders`, `measurements`,
  /// `payments`, `attachments`.
  final Map<String, int> counts;

  /// SHA-256 (hex) of every file in the backup except the manifest.
  final Map<String, String> files;

  Map<String, Object?> toJson() => {
    'format': format,
    'schemaVersion': schemaVersion,
    'appVersion': appVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'counts': counts,
    'files': files,
  };

  String encode() => jsonEncode(toJson());

  /// Throws [FormatException] for anything that is not a valid manifest.
  factory BackupManifest.decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('manifest');
    final counts = (json['counts'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as int),
    );
    final files = (json['files'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    );
    return BackupManifest(
      format: json['format'] as int,
      schemaVersion: json['schemaVersion'] as int,
      appVersion: json['appVersion'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      deviceId: json['deviceId'] as String,
      counts: counts,
      files: files,
    );
  }
}

/// A backup file that was just made.
class BackupResult {
  const BackupResult({required this.file, required this.manifest});

  final File file;
  final BackupManifest manifest;

  int get sizeBytes => file.lengthSync();
}

/// A backup file on this phone.
class BackupFileInfo {
  const BackupFileInfo({
    required this.file,
    required this.modified,
    required this.sizeBytes,
  });

  final File file;
  final DateTime modified;
  final int sizeBytes;
}

/// A finished restore.
class RestoreResult {
  const RestoreResult({required this.manifest, required this.safetyCopy});

  final BackupManifest manifest;

  /// The data that was replaced, kept for a week in case it was the wrong
  /// backup. Null when there was no database to replace.
  final File? safetyCopy;
}

/// When the last backup was made, for the Home badge.
class BackupStatus {
  const BackupStatus({this.lastAt, this.hasKey = false});

  final DateTime? lastAt;

  /// A backup passphrase has been set up.
  final bool hasKey;

  /// Days since the last backup, or null if there never was one.
  int? daysSince(DateTime now) =>
      lastAt == null ? null : now.difference(lastAt!).inDays;

  /// Warn after a week, or when there has never been a backup (B-2).
  bool isStale(DateTime now, {int days = 7}) {
    final d = daysSince(now);
    return d == null || d >= days;
  }
}
