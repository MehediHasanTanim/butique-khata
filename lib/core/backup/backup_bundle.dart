import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One file to put in a bundle: from disk, or from memory.
class BundleEntry {
  const BundleEntry.file(this.name, this.file) : bytes = null;
  const BundleEntry.bytes(this.name, this.bytes) : file = null;

  final String name;
  final File? file;
  final Uint8List? bytes;
}

/// The bundle held something that must never be written to disk, such as a
/// path that escapes the target folder.
class BundleException implements Exception {
  const BundleException(this.message);

  final String message;

  @override
  String toString() => 'BundleException($message)';
}

/// A deliberately tiny container for the files of a backup (manifest, the
/// database snapshot, photos). It replaces a zip file so that unpacking a
/// backup can never write outside its folder: only a fixed set of names is
/// accepted, and the reader checks every length against what is really there.
///
/// Layout, repeated per entry: `nameLength u16 | name | size u64 | bytes`,
/// ended by `nameLength = 0`.
class BackupBundle {
  const BackupBundle._();

  /// Names the app writes: `manifest.json`, `db.sqlite`, `media/<file>`.
  static final RegExp _allowed = RegExp(
    r'^(manifest\.json|db\.sqlite|media/[A-Za-z0-9][A-Za-z0-9._-]{0,127})$',
  );

  static bool isAllowedName(String name) => _allowed.hasMatch(name);

  static void write(File output, Iterable<BundleEntry> entries) {
    final sink = output.openSync(mode: FileMode.write);
    try {
      for (final entry in entries) {
        if (!isAllowedName(entry.name)) {
          throw BundleException('Name not allowed: ${entry.name}');
        }
        final name = utf8.encode(entry.name);
        final size = entry.bytes?.length ?? entry.file!.lengthSync();
        final head = Uint8List(2 + name.length + 8);
        final view = ByteData.sublistView(head);
        view.setUint16(0, name.length);
        head.setAll(2, name);
        view.setUint64(2 + name.length, size);
        sink.writeFromSync(head);
        if (entry.bytes != null) {
          sink.writeFromSync(entry.bytes!);
        } else {
          final input = entry.file!.openSync();
          try {
            var remaining = size;
            while (remaining > 0) {
              final chunk = input.readSync(
                remaining < 1 << 20 ? remaining : 1 << 20,
              );
              if (chunk.isEmpty) {
                throw BundleException(
                  'File shrank while reading: ${entry.name}',
                );
              }
              sink.writeFromSync(chunk);
              remaining -= chunk.length;
            }
          } finally {
            input.closeSync();
          }
        }
      }
      sink.writeFromSync(Uint8List(2)); // end marker
    } finally {
      sink.closeSync();
    }
  }

  /// Unpacks [input] into [outDir] and returns the entry names in order.
  /// Throws [BundleException] on any unexpected name or inconsistent length.
  static List<String> read(File input, Directory outDir) {
    final raf = input.openSync();
    final names = <String>[];
    try {
      final total = raf.lengthSync();
      while (true) {
        if (raf.positionSync() + 2 > total) {
          throw const BundleException('Unexpected end of bundle');
        }
        final nameLength = ByteData.sublistView(
          Uint8List.fromList(raf.readSync(2)),
        ).getUint16(0);
        if (nameLength == 0) break;
        if (nameLength > 200 || raf.positionSync() + nameLength + 8 > total) {
          throw const BundleException('Bad entry header');
        }
        final name = utf8.decode(
          raf.readSync(nameLength),
          allowMalformed: false,
        );
        if (!isAllowedName(name)) {
          throw BundleException('Name not allowed: $name');
        }
        if (names.contains(name)) {
          throw BundleException('Duplicate entry: $name');
        }
        final size = ByteData.sublistView(Uint8List.fromList(raf.readSync(8)))
            .getUint64(0);
        if (size > total - raf.positionSync()) {
          throw const BundleException('Entry larger than the bundle');
        }
        final target = File('${outDir.path}/$name')
          ..parent.createSync(recursive: true);
        final out = target.openSync(mode: FileMode.write);
        try {
          var remaining = size;
          while (remaining > 0) {
            final chunk = raf.readSync(
              remaining < 1 << 20 ? remaining : 1 << 20,
            );
            if (chunk.isEmpty) {
              throw const BundleException('Unexpected end of bundle');
            }
            out.writeFromSync(chunk);
            remaining -= chunk.length;
          }
        } finally {
          out.closeSync();
        }
        names.add(name);
      }
      if (raf.positionSync() != total) {
        throw const BundleException('Unexpected data after the end marker');
      }
      return names;
    } finally {
      raf.closeSync();
    }
  }

  /// SHA-256 of a file, as lower-case hex.
  static Future<String> sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
