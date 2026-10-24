import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/features/security/data/lock_store.dart';
import 'package:tailor_khata/features/security/data/pin_hasher.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';

import '../../support/fakes.dart';
import '../../support/shop_fixture.dart';
import '../../support/test_app.dart';

void main() {
  late InMemoryLockStore store;
  late FakeDeviceAuth auth;

  /// Opens the app as it would start on a phone that already has a PIN.
  Future<void> openLocked(
    WidgetTester tester, {
    String pin = '1234',
    String route = AppRoutes.home,
    String locale = 'en',
    bool biometric = false,
    int timeoutSeconds = 60,
    bool withPin = true,
  }) async {
    auth = FakeDeviceAuth();
    store = InMemoryLockStore();
    LockConfig? config;
    if (withPin) {
      final hash = await tester.runAsync(
        () => const PinHasher.fast().hash(pin),
      );
      config = LockConfig(
        pin: hash!,
        biometric: biometric,
        timeoutSeconds: timeoutSeconds,
      );
      store.config = config;
    }
    await openShop(
      tester,
      route,
      locale: locale,
      overrides: [
        lockStoreProvider.overrideWithValue(store),
        initialLockConfigProvider.overrideWithValue(config),
        pinHasherProvider.overrideWithValue(const PinHasher.fast()),
        deviceAuthProvider.overrideWithValue(auth),
      ],
    );
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.byKey(ValueKey('pin-key-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('pin-key-submit')));
    await tester.pumpAndSettle();
  }

  final lockScreen = find.byKey(const ValueKey('lock-screen'));

  testWidgets('a locked app shows only the lock screen', (tester) async {
    await openLocked(tester);
    expect(lockScreen, findsOneWidget);
    expect(find.text('Tailor Khata is locked'), findsOneWidget);
    // Nothing underneath can be read by a screen reader or tapped.
    expect(find.bySemanticsLabel('Today'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('home-search')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-search-field')), findsNothing);
    await shutDown(tester, shopDb);
  });

  testWidgets('the right PIN opens the app, a wrong one says so', (
    tester,
  ) async {
    await openLocked(tester);
    await typePin(tester, '0000');
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(lockScreen, findsOneWidget);

    await typePin(tester, '1234');
    expect(lockScreen, findsNothing);
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    await shutDown(tester, shopDb);
  });

  testWidgets('too many wrong PINs show a countdown', (tester) async {
    await openLocked(tester);
    for (var i = 0; i < 5; i++) {
      await typePin(tester, '0000');
    }
    expect(find.byKey(const ValueKey('lock-lockout')), findsOneWidget);
    expect(find.textContaining('Try again in 0:30'), findsOneWidget);
    // The keypad is disabled, so even the right PIN cannot be entered.
    await tester.tap(
      find.byKey(const ValueKey('pin-key-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(lockScreen, findsOneWidget);
    await shutDown(tester, shopDb);
  });

  testWidgets('the keypad shows Bangla digits in Bangla', (tester) async {
    await openLocked(tester, locale: 'bn');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pin-key-5')),
        matching: find.text('৫'),
      ),
      findsOneWidget,
    );
    expect(find.text('টেইলর খাতা তালাবদ্ধ'), findsOneWidget);
    await typePin(tester, '1234');
    expect(lockScreen, findsNothing);
    await shutDown(tester, shopDb);
  });

  testWidgets('fingerprint opens it without the PIN', (tester) async {
    await openLocked(tester, biometric: true);
    // The prompt appears by itself on the lock screen, and passes.
    await tester.pumpAndSettle();
    expect(auth.prompts, isNotEmpty);
    expect(lockScreen, findsNothing);
    await shutDown(tester, shopDb);
  });

  testWidgets('a cancelled fingerprint prompt falls back to the PIN', (
    tester,
  ) async {
    await openLocked(tester, biometric: true);
    await tester.pumpAndSettle();
    expect(lockScreen, findsNothing);
    // Lock again, now with the scanner failing.
    auth.succeeds = false;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(lockControllerProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(lockScreen, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pin-key-biometric')));
    await tester.pumpAndSettle();
    expect(lockScreen, findsOneWidget);
    await typePin(tester, '1234');
    expect(lockScreen, findsNothing);
    await shutDown(tester, shopDb);
  });

  testWidgets('forgot PIN: the phone screen lock removes it, data stays', (
    tester,
  ) async {
    await openLocked(tester);
    await tester.tap(find.byKey(const ValueKey('lock-forgot')));
    await tester.pumpAndSettle();
    expect(find.text('Reset the PIN?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lock-reset-continue')));
    await tester.pumpAndSettle();
    expect(auth.prompts, hasLength(1));
    expect(lockScreen, findsNothing);
    expect(store.config, isNull);
    // The shop's customers are untouched.
    final customers = await tester.runAsync(
      () => shopDb.select(shopDb.customer).get(),
    );
    expect(customers, hasLength(2));
    await shutDown(tester, shopDb);
  });

  testWidgets('forgot PIN: a failed check leaves the lock in place', (
    tester,
  ) async {
    await openLocked(tester);
    auth.succeeds = false;
    await tester.tap(find.byKey(const ValueKey('lock-forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lock-reset-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-reset-error')), findsOneWidget);
    expect(store.config, isNotNull);
    expect(lockScreen, findsOneWidget);
    await shutDown(tester, shopDb);
  });

  testWidgets('forgot PIN: no screen lock on the phone says so', (
    tester,
  ) async {
    await openLocked(tester);
    auth.deviceCredential = false;
    await tester.tap(find.byKey(const ValueKey('lock-forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lock-reset-continue')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no screen lock'), findsOneWidget);
    expect(lockScreen, findsOneWidget);
    await shutDown(tester, shopDb);
  });

  group('locks again after the app was in the background', () {
    testWidgets('after the timeout', (tester) async {
      await openLocked(tester);
      await typePin(tester, '1234');
      expect(lockScreen, findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      env.clock.advance(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lockScreen, findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('not for a quick look at another app', (tester) async {
      await openLocked(tester);
      await typePin(tester, '1234');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      env.clock.advance(const Duration(seconds: 20));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lockScreen, findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('at once when the timeout is zero', (tester) async {
      await openLocked(tester, timeoutSeconds: 0);
      await typePin(tester, '1234');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // No frames are drawn while the app is in the background; the lock
      // screen is what appears the moment it comes back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lockScreen, findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('the screen you were on is still there after unlocking', (
      tester,
    ) async {
      await openLocked(tester, route: '/customer/c1');
      await typePin(tester, '1234');
      expect(find.text('Rahim Uddin'), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      env.clock.advance(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lockScreen, findsOneWidget);
      await typePin(tester, '1234');
      expect(find.text('Rahim Uddin'), findsWidgets);
      await shutDown(tester, shopDb);
    });
  });

  group('settings (S6-07)', () {
    Future<void> openSecurity(
      WidgetTester tester, {
      bool withPin = false,
    }) async {
      await openLocked(tester, route: AppRoutes.security, withPin: withPin);
      if (withPin) await typePin(tester, '1234');
    }

    Future<void> enterPin(WidgetTester tester, String key, String pin) async {
      await tester.enterText(find.byKey(ValueKey(key)), pin);
      await tester.pump();
    }

    testWidgets('turning the lock on asks for a PIN twice', (tester) async {
      await openSecurity(tester);
      expect(find.byKey(const ValueKey('security-change')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('security-enable')));
      await tester.pumpAndSettle();

      await enterPin(tester, 'pin-field', '12');
      await tester.tap(find.byKey(const ValueKey('pin-save')));
      await tester.pump();
      expect(find.text('Use 4 to 8 digits'), findsOneWidget);

      await enterPin(tester, 'pin-field', '4321');
      await enterPin(tester, 'pin-confirm', '4322');
      await tester.tap(find.byKey(const ValueKey('pin-save')));
      await tester.pump();
      expect(find.text('The two PINs do not match'), findsOneWidget);

      await enterPin(tester, 'pin-confirm', '4321');
      await tester.tap(find.byKey(const ValueKey('pin-save')));
      await tester.pumpAndSettle();
      expect(store.config, isNotNull);
      expect(find.byKey(const ValueKey('security-change')), findsOneWidget);
      // The app stays open for the person who just set it.
      expect(lockScreen, findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla digits typed on a Bangla keyboard count', (
      tester,
    ) async {
      await openSecurity(tester);
      await tester.tap(find.byKey(const ValueKey('security-enable')));
      await tester.pumpAndSettle();
      await enterPin(tester, 'pin-field', '১২৩৪');
      await enterPin(tester, 'pin-confirm', '১২৩৪');
      await tester.tap(find.byKey(const ValueKey('pin-save')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final lock = container.read(lockControllerProvider.notifier);
      expect(await tester.runAsync(() => lock.verifyPin('1234')), PinCheck.ok);
      await shutDown(tester, shopDb);
    });

    testWidgets('changing the PIN needs the current one', (tester) async {
      await openSecurity(tester, withPin: true);
      await tester.tap(find.byKey(const ValueKey('security-change')));
      await tester.pumpAndSettle();

      await enterPin(tester, 'pin-current', '9999');
      await tester.tap(find.byKey(const ValueKey('pin-current-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('security-change')));
      await tester.pumpAndSettle();
      await enterPin(tester, 'pin-current', '1234');
      await tester.tap(find.byKey(const ValueKey('pin-current-ok')));
      await tester.pumpAndSettle();
      await enterPin(tester, 'pin-field', '8765');
      await enterPin(tester, 'pin-confirm', '8765');
      await tester.tap(find.byKey(const ValueKey('pin-save')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final lock = container.read(lockControllerProvider.notifier);
      expect(
        await tester.runAsync(() => lock.verifyPin('1234')),
        PinCheck.wrong,
      );
      expect(await tester.runAsync(() => lock.verifyPin('8765')), PinCheck.ok);
      await shutDown(tester, shopDb);
    });

    testWidgets('turning it off needs a confirmation and the PIN', (
      tester,
    ) async {
      await openSecurity(tester, withPin: true);
      await tester.tap(find.byKey(const ValueKey('security-enable')));
      await tester.pumpAndSettle();
      expect(find.text('Turn off app lock?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('security-disable-confirm')));
      await tester.pumpAndSettle();

      await enterPin(tester, 'pin-current', '1234');
      await tester.tap(find.byKey(const ValueKey('pin-current-ok')));
      await tester.pumpAndSettle();
      expect(store.config, isNull);
      expect(find.byKey(const ValueKey('security-change')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('timeout can be changed and "lock now" locks', (tester) async {
      await openSecurity(tester, withPin: true);
      await tester.tap(find.byKey(const ValueKey('security-timeout')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('After 5 minutes').last);
      await tester.pumpAndSettle();
      expect(store.config!.timeoutSeconds, 300);

      await tester.tap(find.byKey(const ValueKey('security-lock-now')));
      await tester.pumpAndSettle();
      expect(lockScreen, findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('fingerprint is offered only when the phone has one', (
      tester,
    ) async {
      await openSecurity(tester, withPin: true);
      auth.biometrics = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('security-biometric')));
      await tester.pumpAndSettle();
      expect(store.config!.biometric, isTrue);
      expect(auth.prompts.last.biometricOnly, isTrue);
      await shutDown(tester, shopDb);
    });

    testWidgets(
      'no fingerprint on the phone: the switch is off and explained',
      (tester) async {
        await openLocked(tester, route: AppRoutes.security);
        // Rebuild with a phone without biometrics.
        await shutDown(tester, shopDb);
        auth = FakeDeviceAuth(biometrics: false);
        store = InMemoryLockStore();
        final hash = await tester.runAsync(
          () => const PinHasher.fast().hash('1234'),
        );
        store.config = LockConfig(pin: hash!);
        await openShop(
          tester,
          AppRoutes.security,
          overrides: [
            lockStoreProvider.overrideWithValue(store),
            initialLockConfigProvider.overrideWithValue(store.config),
            pinHasherProvider.overrideWithValue(const PinHasher.fast()),
            deviceAuthProvider.overrideWithValue(auth),
          ],
        );
        await typePin(tester, '1234');
        expect(find.text('Not set up on this phone'), findsOneWidget);
        await shutDown(tester, shopDb);
      },
    );
  });
}
