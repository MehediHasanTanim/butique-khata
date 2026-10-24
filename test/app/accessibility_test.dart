import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/features/security/data/lock_store.dart';
import 'package:tailor_khata/features/security/data/pin_hasher.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';

import '../support/fakes.dart';
import '../support/shop_fixture.dart';
import '../support/test_app.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name.arb').readAsStringSync())
        as Map<String, dynamic>;

/// `{name}` placeholders used by an ICU message, ignoring plural syntax.
Set<String> _placeholders(String message) {
  final names = <String>{};
  // plural/select headers: {count, plural, ...}
  for (final m in RegExp(r'\{(\w+),\s*(plural|select)').allMatches(message)) {
    names.add(m.group(1)!);
  }
  for (final m in RegExp(r'\{(\w+)\}').allMatches(message)) {
    names.add(m.group(1)!);
  }
  return names;
}

void main() {
  group('translations (S6-09)', () {
    final en = _arb('app_en');
    final bn = _arb('app_bn');
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final bnKeys = bn.keys.where((k) => !k.startsWith('@')).toSet();

    test('every English string has a Bangla one', () {
      expect(enKeys.difference(bnKeys), isEmpty);
    });

    test('Bangla has no leftover strings English no longer has', () {
      expect(bnKeys.difference(enKeys), isEmpty);
    });

    test('no string is empty', () {
      for (final arb in [en, bn]) {
        for (final key in arb.keys.where((k) => !k.startsWith('@'))) {
          expect((arb[key] as String).trim(), isNotEmpty, reason: key);
        }
      }
    });

    test('both languages use the same placeholders', () {
      final mismatched = <String>[];
      for (final key in enKeys.intersection(bnKeys)) {
        final a = _placeholders(en[key] as String);
        final b = _placeholders(bn[key] as String);
        if (a.difference(b).isNotEmpty || b.difference(a).isNotEmpty) {
          mismatched.add('$key: $a vs $b');
        }
      }
      expect(mismatched, isEmpty);
    });

    test('Bangla strings are really Bangla, not copied English', () {
      final bangla = RegExp('[ঀ-৿]');
      // Names and symbols that are the same in both languages.
      const same = {'appName', 'languageEnglish', 'languageBangla'};
      final untranslated = <String>[
        for (final key in bnKeys)
          if (!same.contains(key) &&
              !bangla.hasMatch(bn[key] as String) &&
              RegExp('[A-Za-z]{3}').hasMatch(
                (bn[key] as String).replaceAll(RegExp(r'\{[^}]*\}'), ''),
              ))
            key,
      ];
      expect(untranslated, isEmpty, reason: untranslated.join(', '));
    });

    test('Bangla messages use Bangla digits, not Latin ones', () {
      final latinDigit = RegExp('[0-9]');
      final offenders = <String>[
        for (final key in bnKeys)
          if (latinDigit.hasMatch(
            // Numbers inside placeholders and plural syntax are fine.
            (bn[key] as String).replaceAll(RegExp(r'\{[^}]*\}'), ''),
          ))
            key,
      ];
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });

  group('large text (1.3×) does not break screens', () {
    Future<void> check(
      WidgetTester tester,
      String route, {
      required String locale,
      Future<void> Function()? extra,
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openShop(tester, route, locale: locale, extra: extra);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    }

    for (final locale in ['en', 'bn']) {
      for (final route in [
        AppRoutes.home,
        AppRoutes.customers,
        AppRoutes.orders,
        AppRoutes.rush,
        AppRoutes.more,
        AppRoutes.security,
        AppRoutes.backup,
        AppRoutes.recentlyDeleted,
        AppRoutes.settingsReminders,
        AppRoutes.settingsMessages,
        '/customer/c1',
        AppRoutes.search,
      ]) {
        testWidgets('$route in $locale', (tester) async {
          await check(tester, route, locale: locale);
        });
      }
    }

    testWidgets('the lock screen, English and Bangla', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final locale in ['en', 'bn']) {
        final hash = await tester.runAsync(
          () => const PinHasher.fast().hash('1234'),
        );
        await openShop(
          tester,
          AppRoutes.home,
          locale: locale,
          overrides: [
            initialLockConfigProvider.overrideWithValue(LockConfig(pin: hash!)),
            lockStoreProvider.overrideWithValue(InMemoryLockStore()),
            deviceAuthProvider.overrideWithValue(FakeDeviceAuth()),
            pinHasherProvider.overrideWithValue(const PinHasher.fast()),
          ],
        );
        expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shutDown(tester, shopDb);
      }
    });
  });

  group('screen readers and touch targets', () {
    for (final route in [
      AppRoutes.home,
      AppRoutes.more,
      AppRoutes.security,
      AppRoutes.backup,
      AppRoutes.recentlyDeleted,
      AppRoutes.customers,
    ]) {
      testWidgets('$route: targets are at least 48 dp and labelled', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await openShop(tester, route);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
        await shutDown(tester, shopDb);
      });
    }

    testWidgets('the lock screen keys are big and named', (tester) async {
      final handle = tester.ensureSemantics();
      final hash = await tester.runAsync(
        () => const PinHasher.fast().hash('1234'),
      );
      await openShop(
        tester,
        AppRoutes.home,
        overrides: [
          initialLockConfigProvider.overrideWithValue(
            LockConfig(pin: hash!, biometric: true),
          ),
          lockStoreProvider.overrideWithValue(InMemoryLockStore()),
          deviceAuthProvider.overrideWithValue(FakeDeviceAuth(succeeds: false)),
          pinHasherProvider.overrideWithValue(const PinHasher.fast()),
        ],
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      // Digits are read out as digits; the other keys have spoken names.
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(find.bySemanticsLabel('OK'), findsOneWidget);
      handle.dispose();
      await shutDown(tester, shopDb);
    });
  });

  group('Bangla digits everywhere', () {
    /// Every piece of text on screen.
    List<String> shown(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
    ];

    final latin = RegExp('[0-9]');

    for (final route in [
      AppRoutes.home,
      AppRoutes.customers,
      AppRoutes.orders,
      AppRoutes.rush,
      AppRoutes.more,
      AppRoutes.security,
      AppRoutes.backup,
      AppRoutes.recentlyDeleted,
      '/customer/c1',
    ]) {
      testWidgets(route, (tester) async {
        await openShop(
          tester,
          route,
          locale: 'bn',
          extra: () async {
            await seedOrder(price: 1200, advance: 500);
          },
        );
        final offenders = shown(tester).where(latin.hasMatch).toList();
        expect(offenders, isEmpty, reason: offenders.join(' | '));
        await shutDown(tester, shopDb);
      });
    }
  });
}
