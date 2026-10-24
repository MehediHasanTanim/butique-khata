import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/security/data/lock_store.dart';
import 'package:tailor_khata/features/security/data/pin_hasher.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';

import '../../support/fakes.dart';

void main() {
  late FixedClock clock;
  late InMemoryLockStore store;
  late FakeDeviceAuth auth;

  ProviderContainer container({LockConfig? initial}) {
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        lockStoreProvider.overrideWithValue(store),
        pinHasherProvider.overrideWithValue(const PinHasher.fast()),
        deviceAuthProvider.overrideWithValue(auth),
        initialLockConfigProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    clock = FixedClock(DateTime(2026, 3, 10, 9));
    store = InMemoryLockStore();
    auth = FakeDeviceAuth();
  });

  Future<(ProviderContainer, LockController)> withPin([
    String pin = '1234',
  ]) async {
    final c = container();
    final lock = c.read(lockControllerProvider.notifier);
    await lock.setupPin(pin);
    return (c, lock);
  }

  group('PIN storage', () {
    test('the PIN is hashed with a salt, never stored as typed', () async {
      await withPin('4821');
      final config = store.config!;
      expect(config.pin.hash, hasLength(32));
      expect(config.pin.salt, hasLength(16));
      expect(String.fromCharCodes(config.pin.hash), isNot(contains('4821')));
    });

    test('the same PIN hashes differently each time', () async {
      const hasher = PinHasher.fast();
      final a = await hasher.hash('1234');
      final b = await hasher.hash('1234');
      expect(a.hash, isNot(b.hash));
      expect(await hasher.verify('1234', a), isTrue);
      expect(await hasher.verify('1235', a), isFalse);
    });

    test('works on a background isolate too', () async {
      const hasher = PinHasher(iterations: 20);
      final h = await hasher.hash('99887766');
      expect(await hasher.verify('99887766', h), isTrue);
      expect(await hasher.verify('99887765', h), isFalse);
    });

    test('a cold start with a PIN begins locked', () async {
      await withPin();
      final c = container(initial: store.config);
      final state = c.read(lockControllerProvider);
      expect(state.configured, isTrue);
      expect(state.locked, isTrue);
    });

    test('no PIN means never locked', () {
      final state = container().read(lockControllerProvider);
      expect(state.configured, isFalse);
      expect(state.locked, isFalse);
    });
  });

  group('unlocking', () {
    test('the right PIN unlocks, a wrong one does not', () async {
      final (c, lock) = await withPin();
      lock.lock();
      expect(c.read(lockControllerProvider).locked, isTrue);
      expect(await lock.verifyPin('0000'), PinCheck.wrong);
      expect(c.read(lockControllerProvider).locked, isTrue);
      expect(await lock.verifyPin('1234'), PinCheck.ok);
      expect(c.read(lockControllerProvider).locked, isFalse);
    });

    test('five wrong PINs start a lockout that grows', () async {
      final (c, lock) = await withPin();
      lock.lock();
      for (var i = 0; i < 4; i++) {
        expect(await lock.verifyPin('0000'), PinCheck.wrong);
      }
      expect(await lock.verifyPin('0000'), PinCheck.lockedOut);
      expect(
        c.read(lockControllerProvider).lockoutLeft(clock.now()),
        const Duration(seconds: 30),
      );

      // Even the right PIN is refused during the lockout.
      expect(await lock.verifyPin('1234'), PinCheck.lockedOut);
      expect(c.read(lockControllerProvider).locked, isTrue);

      clock.advance(const Duration(seconds: 31));
      expect(await lock.verifyPin('0000'), PinCheck.lockedOut);
      expect(
        c.read(lockControllerProvider).lockoutLeft(clock.now()),
        const Duration(seconds: 60),
      );
    });

    test('the lockout never exceeds fifteen minutes', () async {
      final (c, lock) = await withPin();
      lock.lock();
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(hours: 1));
        await lock.verifyPin('0000');
      }
      expect(
        c.read(lockControllerProvider).lockoutLeft(clock.now()),
        const Duration(minutes: 15),
      );
    });

    test('a right PIN after the lockout clears the count', () async {
      final (c, lock) = await withPin();
      lock.lock();
      for (var i = 0; i < 5; i++) {
        await lock.verifyPin('0000');
      }
      clock.advance(const Duration(minutes: 1));
      expect(await lock.verifyPin('1234'), PinCheck.ok);
      expect(c.read(lockControllerProvider).failures, 0);
      expect(store.config!.failures, 0);
      expect(store.config!.lockedUntil, isNull);
    });

    test('closing the app does not reset the lockout', () async {
      final (_, lock) = await withPin();
      lock.lock();
      for (var i = 0; i < 5; i++) {
        await lock.verifyPin('0000');
      }
      final restarted = container(initial: store.config);
      final state = restarted.read(lockControllerProvider);
      expect(state.locked, isTrue);
      expect(state.lockoutLeft(clock.now()), const Duration(seconds: 30));
    });
  });

  group('biometrics', () {
    test('unlocks without the PIN when enabled', () async {
      final (c, lock) = await withPin();
      await lock.setBiometric(true);
      lock.lock();
      expect(await lock.unlockWithBiometrics('why'), isTrue);
      expect(c.read(lockControllerProvider).locked, isFalse);
      expect(auth.prompts.single.biometricOnly, isTrue);
    });

    test('a failed scan keeps it locked', () async {
      final (c, lock) = await withPin();
      await lock.setBiometric(true);
      lock.lock();
      auth.succeeds = false;
      expect(await lock.unlockWithBiometrics('why'), isFalse);
      expect(c.read(lockControllerProvider).locked, isTrue);
    });

    test('is not even asked when switched off', () async {
      final (_, lock) = await withPin();
      lock.lock();
      expect(await lock.unlockWithBiometrics('why'), isFalse);
      expect(auth.prompts, isEmpty);
    });
  });

  group('locking after the app was in the background', () {
    test('stays open for a short trip out of the app', () async {
      final (c, lock) = await withPin();
      lock.didLeave();
      clock.advance(const Duration(seconds: 30));
      lock.didReturn();
      expect(c.read(lockControllerProvider).locked, isFalse);
    });

    test('locks after the timeout', () async {
      final (c, lock) = await withPin();
      lock.didLeave();
      clock.advance(const Duration(seconds: 61));
      lock.didReturn();
      expect(c.read(lockControllerProvider).locked, isTrue);
    });

    test('immediately, when set to lock at once', () async {
      final (c, lock) = await withPin();
      await lock.setTimeout(0);
      lock.didLeave();
      expect(c.read(lockControllerProvider).locked, isTrue);
    });

    test('the timeout is remembered', () async {
      final (_, lock) = await withPin();
      await lock.setTimeout(900);
      expect(store.config!.timeoutSeconds, 900);
      final restarted = container(initial: store.config);
      expect(restarted.read(lockControllerProvider).timeoutSeconds, 900);
    });

    test('does nothing when no PIN is set', () {
      final c = container();
      final lock = c.read(lockControllerProvider.notifier);
      lock
        ..didLeave()
        ..didReturn()
        ..lock();
      expect(c.read(lockControllerProvider).locked, isFalse);
    });
  });

  group('changing and removing the PIN', () {
    test('a new PIN replaces the old one and keeps the settings', () async {
      final (_, lock) = await withPin();
      await lock.setBiometric(true);
      await lock.setTimeout(300);
      await lock.setupPin('5678');
      expect(await lock.verifyPin('1234'), PinCheck.wrong);
      expect(await lock.verifyPin('5678'), PinCheck.ok);
      expect(store.config!.biometric, isTrue);
      expect(store.config!.timeoutSeconds, 300);
    });

    test('turning it off removes everything stored', () async {
      final (c, lock) = await withPin();
      await lock.disable();
      expect(store.config, isNull);
      expect(c.read(lockControllerProvider).configured, isFalse);
    });
  });

  group('forgot the PIN (TD §6)', () {
    test('the phone screen lock removes the PIN', () async {
      final (c, lock) = await withPin();
      lock.lock();
      expect(await lock.resetViaDeviceCredential('why'), ResetResult.done);
      expect(store.config, isNull);
      expect(c.read(lockControllerProvider).locked, isFalse);
      expect(auth.prompts.single.biometricOnly, isFalse);
    });

    test('a failed check changes nothing', () async {
      final (c, lock) = await withPin();
      lock.lock();
      auth.succeeds = false;
      expect(await lock.resetViaDeviceCredential('why'), ResetResult.failed);
      expect(store.config, isNotNull);
      expect(c.read(lockControllerProvider).locked, isTrue);
    });

    test('a phone with no screen lock cannot reset', () async {
      final (_, lock) = await withPin();
      auth.deviceCredential = false;
      expect(
        await lock.resetViaDeviceCredential('why'),
        ResetResult.noDeviceLock,
      );
      expect(auth.prompts, isEmpty);
      expect(store.config, isNotNull);
    });
  });
}
