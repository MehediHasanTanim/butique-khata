import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the system share sheet (WhatsApp, print, save...).
abstract class FileSharer {
  /// Shares [bytes] as a file called [fileName].
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    String? text,
  });
}

class SharePlusFileSharer implements FileSharer {
  const SharePlusFileSharer();

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  }
}
