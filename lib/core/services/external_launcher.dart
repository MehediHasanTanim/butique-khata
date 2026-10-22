import 'package:url_launcher/url_launcher.dart';

/// Opens links outside the app (SMS, WhatsApp), behind an interface so tests
/// can record what would have been opened.
abstract class ExternalLauncher {
  /// True if something handled [uri].
  Future<bool> open(Uri uri);
}

class UrlLauncher implements ExternalLauncher {
  const UrlLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
