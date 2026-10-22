import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('shows five tabs and navigates between them', (tester) async {
    final db = memoryDb();
    await tester.pumpWidget(buildTestApp(db));
    await tester.pumpAndSettle();

    for (final label in ['Home', 'Customers', 'Orders', 'Rush', 'More']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.text('No customers yet'), findsOneWidget);

    await tester.tap(find.text('Orders').last);
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);

    await tester.tap(find.text('Rush').last);
    await tester.pumpAndSettle();
    expect(find.text('Rush mode is off'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('switches to Bangla at runtime and persists the choice', (
    tester,
  ) async {
    final db = memoryDb();
    await tester.pumpWidget(buildTestApp(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    expect(find.text('গ্রাহক'), findsWidgets);
    expect(find.text('ভাষা'), findsOneWidget);
    expect(await SettingsRepository(db).read(SettingKeys.locale), 'bn');

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(await SettingsRepository(db).read(SettingKeys.locale), 'en');
    await shutDown(tester, db);
  });

  testWidgets('starts in the persisted language', (tester) async {
    final db = memoryDb();
    await tester.pumpWidget(buildTestApp(db, locale: 'bn'));
    await tester.pumpAndSettle();
    expect(find.text('হোম'), findsWidgets);
    expect(find.text('আজকের কাজ'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('bottom navigation targets are at least 48dp tall', (
    tester,
  ) async {
    final db = memoryDb();
    await tester.pumpWidget(buildTestApp(db));
    await tester.pumpAndSettle();
    final bar = tester.getSize(find.byType(NavigationBar));
    expect(bar.height, greaterThanOrEqualTo(48));
    await shutDown(tester, db);
  });

  testWidgets('useBanglaDigitsProvider follows the locale', (tester) async {
    final db = memoryDb();
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          initialLocaleCodeProvider.overrideWithValue('bn'),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(captured.read(useBanglaDigitsProvider), isTrue);
    await shutDown(tester, db);
  });
}
