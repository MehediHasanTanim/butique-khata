import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/media/image_processor.dart';

/// A saved photo: paths are relative to the media folder.
class StoredImage {
  const StoredImage({required this.path, required this.thumbPath});

  final String path;
  final String thumbPath;

  @override
  bool operator ==(Object other) =>
      other is StoredImage &&
      other.path == path &&
      other.thumbPath == thumbPath;

  @override
  int get hashCode => Object.hash(path, thumbPath);
}

/// Where photos live. Photos are kept in the app's private folder (not the
/// gallery), so they are included in backups and not visible to other apps.
abstract class MediaStore {
  /// Compresses [bytes] and stores the image and its thumbnail.
  Future<StoredImage> saveImage(Uint8List bytes);

  /// Deletes both files; missing files are ignored.
  Future<void> delete(StoredImage image);

  /// Absolute file for a stored relative [path].
  File resolve(String path);
}

class FileMediaStore implements MediaStore {
  FileMediaStore(this._root, [this._ids = const UuidV7Generator()]);

  /// Standard location: `<app support>/media`.
  static Future<FileMediaStore> inAppSupport() async {
    final dir = await getApplicationSupportDirectory();
    return FileMediaStore(Directory(p.join(dir.path, 'media')));
  }

  final Directory _root;
  final IdGenerator _ids;

  @override
  Future<StoredImage> saveImage(Uint8List bytes) async {
    final processed = await compute(processImage, bytes);
    await _root.create(recursive: true);
    final id = _ids.newId();
    final full = '$id.jpg';
    final thumb = '$id.thumb.jpg';
    await File(p.join(_root.path, full)).writeAsBytes(processed.full);
    await File(p.join(_root.path, thumb)).writeAsBytes(processed.thumb);
    return StoredImage(path: full, thumbPath: thumb);
  }

  @override
  Future<void> delete(StoredImage image) async {
    for (final path in [image.path, image.thumbPath]) {
      final file = resolve(path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  File resolve(String path) => File(p.join(_root.path, path));
}
