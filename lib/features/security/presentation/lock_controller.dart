import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/features/security/data/device_auth.dart';
import 'package:tailor_khata/features/security/data/lock_store.dart';
import 'package:tailor_khata/features/security/data/pin_hasher.dart';

/// What the lock screen and settings need to know.
class LockState {
  const LockState({
    this.configured = false,
    this.locked = false,
    this.biometric = false,
    this.timeoutSeconds = 60,
    this.failures = 0,
    this.lockedUntil,
  });

  /// A PIN is set.
  final bool configured;

  /// The lock screen is showing.
  final bool locked;
  final bool biometric;
  final int timeoutSeconds;
  final int failures;

  /// After too many wrong PINs, no attempt is accepted before this time.
  final DateTime? lockedUntil;

  Duration lockoutLeft(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  LockState copyWith({
    bool? configured,
    bool? locked,
    bool? biometric,
    int? timeoutSeconds,
    int? failures,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) => LockState(
    configured: configured ?? this.configured,
    locked: locked ?? this.locked,
    biometric: biometric ?? this.biometric,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    failures: failures ?? this.failures,
    lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
  );
}

enum PinCheck { ok, wrong, lockedOut }

enum ResetResult { done, failed, noDeviceLock }

/// The PIN, as read before `runApp`, so a cold start is locked from the
/// first frame.
final initialLockConfigProvider = Provider<LockConfig?>((ref) => null);

final lockStoreProvider = Provider<LockStore>((ref) => InMemoryLockStore());

final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

final deviceAuthProvider = Provider<DeviceAuth>((ref) => LocalAuthDeviceAuth());

class LockController extends Notifier<LockState> {
  /// Wrong PINs allowed before the lockout starts.
  static const int freeAttempts = 5;
  static const Duration firstLockout = Duration(seconds: 30);
  static const Duration longestLockout = Duration(minutes: 15);

  /// Timeouts offered in settings, in seconds.
  static const List<int> timeouts = [0, 60, 300, 900];

  DateTime? _leftAt;

  LockStore get _store => ref.read(lockStoreProvider);
  PinHasher get _hasher => ref.read(pinHasherProvider);
  DateTime get _now => ref.read(clockProvider).now();

  // The stored config is only read to verify and to save changes.
  LockConfig? _config;

  @override
  LockState build() {
    _config = ref.watch(initialLockConfigProvider);
    final c = _config;
    if (c == null) return const LockState();
    return LockState(
      configured: true,
      locked: true,
      biometric: c.biometric,
      timeoutSeconds: c.timeoutSeconds,
      failures: c.failures,
      lockedUntil: c.lockedUntil,
    );
  }

  Future<void> setupPin(String pin) async {
    final config = LockConfig(
      pin: await _hasher.hash(pin),
      biometric: _config?.biometric ?? false,
      timeoutSeconds: _config?.timeoutSeconds ?? 60,
    );
    _config = config;
    await _store.save(config);
    state = LockState(
      configured: true,
      biometric: config.biometric,
      timeoutSeconds: config.timeoutSeconds,
    );
  }

  /// Checks [pin]. A right PIN unlocks and clears the failure count; wrong
  /// ones count towards a growing lockout. A locked-out controller does not
  /// even look at the PIN.
  Future<PinCheck> verifyPin(String pin) async {
    final config = _config;
    if (config == null) return PinCheck.ok;
    if (state.lockoutLeft(_now) > Duration.zero) return PinCheck.lockedOut;

    if (await _hasher.verify(pin, config.pin)) {
      _config = config.copyWith(failures: 0, clearLockedUntil: true);
      await _store.save(_config!);
      state = state.copyWith(
        locked: false,
        failures: 0,
        clearLockedUntil: true,
      );
      return PinCheck.ok;
    }

    final failures = state.failures + 1;
    DateTime? until;
    if (failures >= freeAttempts) {
      final steps = failures - freeAttempts;
      final seconds = min(
        firstLockout.inSeconds * pow(2, steps).toInt(),
        longestLockout.inSeconds,
      );
      until = _now.add(Duration(seconds: seconds));
    }
    _config = config.copyWith(failures: failures, lockedUntil: until);
    await _store.save(_config!);
    state = state.copyWith(failures: failures, lockedUntil: until);
    return until == null ? PinCheck.wrong : PinCheck.lockedOut;
  }

  Future<bool> unlockWithBiometrics(String reason) async {
    if (!state.configured || !state.biometric) return false;
    final ok = await ref
        .read(deviceAuthProvider)
        .authenticate(reason: reason, biometricOnly: true);
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  void lock() {
    if (state.configured) state = state.copyWith(locked: true);
  }

  Future<void> setBiometric(bool value) async {
    final config = _config;
    if (config == null) return;
    _config = config.copyWith(biometric: value);
    await _store.save(_config!);
    state = state.copyWith(biometric: value);
  }

  Future<void> setTimeout(int seconds) async {
    final config = _config;
    if (config == null) return;
    _config = config.copyWith(timeoutSeconds: seconds);
    await _store.save(_config!);
    state = state.copyWith(timeoutSeconds: seconds);
  }

  /// Turns the lock off. The caller has already checked the PIN.
  Future<void> disable() async {
    _config = null;
    await _store.clear();
    state = const LockState();
  }

  /// Forgot the PIN: the phone's own screen lock proves it is the owner, then
  /// the lock is removed. The database is never touched, so nothing is lost.
  Future<ResetResult> resetViaDeviceCredential(String reason) async {
    final auth = ref.read(deviceAuthProvider);
    if (!await auth.deviceCredentialAvailable()) {
      return ResetResult.noDeviceLock;
    }
    if (!await auth.authenticate(reason: reason)) return ResetResult.failed;
    await disable();
    return ResetResult.done;
  }

  // ---- background timeout -------------------------------------------------

  /// The app left the foreground.
  void didLeave() {
    if (!state.configured || state.locked) return;
    _leftAt ??= _now;
    if (state.timeoutSeconds == 0) lock();
  }

  /// The app came back: lock if it was away longer than the timeout.
  void didReturn() {
    final left = _leftAt;
    _leftAt = null;
    if (!state.configured || state.locked || left == null) return;
    if (_now.difference(left).inSeconds >= state.timeoutSeconds) lock();
  }
}

final lockControllerProvider = NotifierProvider<LockController, LockState>(
  LockController.new,
);
