import 'package:tailor_khata/core/media/media_store.dart';

/// A photo attached to something, e.g. a garment in an order (O-3).
class PhotoAttachment {
  const PhotoAttachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.image,
    required this.createdAt,
  });

  final String id;
  final String ownerType;
  final String ownerId;
  final StoredImage image;
  final DateTime createdAt;
}

/// Owner types used in the `attachment` table.
abstract class AttachmentOwner {
  static const orderItem = 'order_item';
}
