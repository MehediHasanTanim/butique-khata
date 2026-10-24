import 'package:local_auth/local_auth.dart';
import 'package:tailor_khata/core/logging/app_log.dart';

/// The phone's own fingerprint / face / screen-lock check.
abstract class DeviceAuth {
  /// A fingerprint or face is enrolled and usable.
  Future<bool> biometricsAvailable();

  /// The phone has any screen lock (PIN, pattern, biometrics).
  Future<bool> deviceCredentialAvailable();

  /// Shows the system prompt. With [biometricOnly] the screen-lock PIN is not
  /// accepted. Never throws: any failure is `false`.
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  });
}

class LocalAuthDeviceAuth implements DeviceAuth {
  LocalAuthDeviceAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> biometricsAvailable() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object catch (error) {
      AppLog.w('lock', 'Biometrics check failed: $error');
      return false;
    }
  }

  @override
  Future<bool> deviceCredentialAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
    } on Object catch (error) {
      AppLog.w('lock', 'Device authentication failed: $error');
      return false;
    }
  }
}
