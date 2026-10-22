import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/domain/photo_attachment.dart';

/// Photos attached to orders (and later customers): rows in `attachment`
/// plus compressed files in the [MediaStore].
class AttachmentRepository {
  AttachmentRepository(this._db, this._media, this._clock, this._ids);

  final AppDatabase _db;
  final MediaStore _media;
  final Clock _clock;
  final IdGenerator _ids;

  static PhotoAttachment _map(AttachmentRow r) => PhotoAttachment(
    id: r.id,
    ownerType: r.ownerType,
    ownerId: r.ownerId,
    image: StoredImage(path: r.path, thumbPath: r.thumbPath ?? r.path),
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
  );

  Stream<List<PhotoAttachment>> watch(String ownerType, String ownerId) =>
      (_db.select(_db.attachment)
            ..where(
              (t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_map).toList());

  Future<List<PhotoAttachment>> list(String ownerType, String ownerId) async {
    final rows =
        await (_db.select(_db.attachment)..where(
              (t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId),
            ))
            .get();
    return rows.map(_map).toList();
  }

  /// Compresses and stores [bytes], then records it. Throws
  /// [FormatException] if the bytes are not an image.
  Future<PhotoAttachment> addBytes(
    String ownerType,
    String ownerId,
    Uint8List bytes,
  ) async {
    final stored = await _media.saveImage(bytes);
    try {
      final id = _ids.newId();
      await _db
          .into(_db.attachment)
          .insert(
            AttachmentCompanion.insert(
              id: id,
              ownerType: ownerType,
              ownerId: ownerId,
              path: stored.path,
              thumbPath: Value(stored.thumbPath),
              createdAt: _clock.now().millisecondsSinceEpoch,
            ),
          );
      return (await list(ownerType, ownerId)).firstWhere((a) => a.id == id);
    } on Object {
      await _media.delete(stored);
      rethrow;
    }
  }

  /// Picks a photo from [source] and attaches it; null if cancelled.
  Future<PhotoAttachment?> addFromSource(
    PhotoSource source,
    PhotoOrigin origin,
    String ownerType,
    String ownerId,
  ) async {
    final bytes = await source.pick(origin);
    if (bytes == null) return null;
    return addBytes(ownerType, ownerId, bytes);
  }

  /// Removes the row and deletes the files.
  Future<void> remove(PhotoAttachment photo) async {
    await (_db.delete(
      _db.attachment,
    )..where((t) => t.id.equals(photo.id))).go();
    try {
      await _media.delete(photo.image);
    } on Object catch (error) {
      AppLog.e('media', 'Could not delete photo files', error);
    }
  }
}
