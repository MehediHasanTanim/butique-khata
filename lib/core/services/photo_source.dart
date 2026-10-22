import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

enum PhotoOrigin { camera, gallery }

/// Where new photos come from; an interface so tests can supply pictures.
abstract class PhotoSource {
  /// Bytes of the picked photo, or null if the user cancelled.
  Future<Uint8List?> pick(PhotoOrigin origin);
}

class ImagePickerSource implements PhotoSource {
  ImagePickerSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    final file = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Decode at a sane size up front; the store shrinks it further.
      maxWidth: 2000,
      maxHeight: 2000,
    );
    return file?.readAsBytes();
  }
}
