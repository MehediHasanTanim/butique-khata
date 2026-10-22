import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A photo reduced for storage: a full image and a thumbnail, both JPEG.
class ProcessedImage {
  const ProcessedImage({
    required this.full,
    required this.thumb,
    required this.width,
    required this.height,
  });

  final Uint8List full;
  final Uint8List thumb;
  final int width;
  final int height;
}

/// Shrinks a picked photo so a busy shop's storage and backups stay small
/// (TD §11): longest side at most [maxSide] px, JPEG re-encoded until it is
/// at most [maxBytes] (reducing quality, then size down to [minSide] px),
/// plus a [thumbSide] px thumbnail.
///
/// Pure function so it can run on a background isolate. Throws
/// [FormatException] if [bytes] is not a readable image.
ProcessedImage processImage(
  Uint8List bytes, {
  int maxSide = 1280,
  int thumbSide = 200,
  int maxBytes = 300 * 1024,
  int minSide = 640,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not a readable image');
  // Apply the camera's rotation flag so photos are not sideways.
  var image = img.bakeOrientation(decoded);

  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }

  var quality = 82;
  var full = Uint8List.fromList(img.encodeJpg(image, quality: quality));
  while (full.length > maxBytes && quality > 48) {
    quality -= 8;
    full = Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
  // Very detailed photos may still be too big: shrink them step by step, but
  // never below [minSide] so they stay usable as a reference picture.
  while (full.length > maxBytes &&
      math.max(image.width, image.height) * 0.85 >= minSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: (image.width * 0.85).round())
        : img.copyResize(image, height: (image.height * 0.85).round());
    full = Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  final thumbImage = image.width >= image.height
      ? img.copyResize(image, width: math.min(thumbSide, image.width))
      : img.copyResize(image, height: math.min(thumbSide, image.height));
  final thumb = Uint8List.fromList(img.encodeJpg(thumbImage, quality: 70));

  return ProcessedImage(
    full: full,
    thumb: thumb,
    width: image.width,
    height: image.height,
  );
}
