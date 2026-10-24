import 'package:google_sign_in/google_sign_in.dart';
import 'package:tailor_khata/core/logging/app_log.dart';

/// Signs in to Google and hands out the headers Drive requests need. The
/// app only ever asks for the hidden app-data folder, never the user's files.
abstract class DriveAuth {
  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';

  /// Request headers, or null when signed out. With [interactive] Google's
  /// sign-in and consent screens may be shown.
  Future<Map<String, String>?> headers({bool interactive = false});

  /// The signed-in account, if any.
  Future<String?> email();

  Future<void> signOut();
}

class GoogleDriveAuth implements DriveAuth {
  GoogleDriveAuth([GoogleSignIn? signIn])
    : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  Future<void>? _initialized;
  GoogleSignInAccount? _account;

  Future<void> _init() => _initialized ??= _signIn.initialize();

  @override
  Future<Map<String, String>?> headers({bool interactive = false}) async {
    try {
      await _init();
      _account ??= await _signIn.attemptLightweightAuthentication();
      if (_account == null && interactive) {
        _account = await _signIn.authenticate(scopeHint: [DriveAuth.scope]);
      }
      final account = _account;
      if (account == null) return null;
      return await account.authorizationClient.authorizationHeaders([
        DriveAuth.scope,
      ], promptIfNecessary: interactive);
    } on Object catch (error) {
      AppLog.w('drive', 'Google sign-in failed: $error');
      return null;
    }
  }

  @override
  Future<String?> email() async {
    try {
      await _init();
      _account ??= await _signIn.attemptLightweightAuthentication();
      return _account?.email;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _init();
      await _signIn.signOut();
    } on Object catch (error) {
      AppLog.w('drive', 'Sign-out failed: $error');
    }
    _account = null;
  }
}
