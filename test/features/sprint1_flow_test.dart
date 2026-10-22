import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/router.dart';
import 'package:tailor_khata/core/db/app_database.dart';

import '../support/flow_helpers.dart';
import '../support/test_app.dart' show shutDown;

class Ctx {
  Ctx(this.db);
  AppDatabase db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tk_flow');
    file = File('${dir.path}/app.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs [body] on a phone-sized screen with a file-backed database, and
  /// always shuts the app down cleanly before the test ends.
  void appTest(
    String name,
    Future<void> Function(WidgetTester tester, Ctx ctx) body,
  ) {
    testWidgets(name, (tester) async {
      phoneScreen(tester);
      final ctx = Ctx(AppDatabase(NativeDatabase(file)));
      try {
        await body(tester, ctx);
      } finally {
        await shutDown(tester, ctx.db);
      }
    });
  }

  appTest(
    'demo: add Rahim Uddin, take Panjabi measurements, reopen, numbers intact',
    (tester, ctx) async {
      var db = ctx.db;
      await tester.pumpWidget(appOn(db));
      await tester.pumpAndSettle();

      // Customers tab → empty state → add.
      await tester.tap(find.text('Customers').last);
      await tester.pumpAndSettle();
      expect(find.text('No customers yet'), findsOneWidget);
      await tester.tap(find.text('Add customer').first);
      await tester.pumpAndSettle();

      // Create "Rahim Uddin".
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Rahim Uddin');
      await tester.enterText(fields.at(1), '01712-345678');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Lands on the profile.
      expect(find.text('Rahim Uddin'), findsWidgets);
      expect(find.text('01712345678'), findsOneWidget);

      // Measurements tab → take measurements → Panjabi.
      await tester.tap(find.text('Measurements'));
      await tester.pumpAndSettle();
      expect(find.text('No measurements yet'), findsOneWidget);
      await tester.tap(find.text('Take measurements'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garment-panjabi')));
      await tester.pumpAndSettle();
      expect(find.text('Panjabi / Kurta measurements'), findsOneWidget);

      // Length 42½ (auto-advances), Chest 38½, Waist 3 4, skip hip, Shoulder 1 7 ¼.
      await typeKeys(tester, '42½');
      await typeKeys(tester, '38½');
      await typeKeys(tester, '34');
      await tapKey(tester, 'key-next'); // commit waist → hip
      await tapKey(tester, 'key-next'); // skip hip → shoulder
      await typeKeys(tester, '17¼');
      expect(find.text('42½'), findsOneWidget);
      expect(find.text('38½'), findsOneWidget);

      await tester.tap(find.text('Save').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Back on the profile with a card.
      expect(find.text('Measurements saved'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Length 42½'), findsOneWidget);
      expect(find.text('Chest 38½'), findsOneWidget);
      expect(find.text('Waist 34'), findsOneWidget);
      expect(find.text('Shoulder 17¼'), findsOneWidget);
      expect(find.textContaining('Hip'), findsNothing);

      // "Kill the app": dispose everything and reopen the same file.
      final customerId = (await tester.runAsync(
        () async => (await db.select(db.customer).getSingle()).id,
      ))!;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(db.close);

      db = ctx.db = AppDatabase(NativeDatabase(file));
      await tester.pumpWidget(appOn(db, start: AppRoutes.customer(customerId)));
      await tester.pumpAndSettle();
      expect(find.text('Rahim Uddin'), findsWidgets);
      await tester.tap(find.text('Measurements'));
      await tester.pumpAndSettle();
      expect(find.text('Length 42½'), findsOneWidget);
      expect(find.text('Chest 38½'), findsOneWidget);

      // The stored value is exact: 38½ in = 9779 units.
      final stored = (await tester.runAsync(
        () => db.select(db.measurementValue).get(),
      ))!;
      expect(stored.firstWhere((v) => v.fieldKey == 'chest').mm10, 9779);
    },
  );

  appTest('second measurement starts from the first and adds version 2', (
    tester,
    ctx,
  ) async {
    final db = ctx.db;
    await tester.pumpWidget(appOn(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add customer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Karim');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measurements'));
    await tester.pumpAndSettle();

    Future<void> openShirt() async {
      await tester.tap(find.text('Take measurements'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garment-shirt')));
      await tester.pumpAndSettle();
    }

    await openShirt();
    await typeKeys(tester, '30');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Version 1'), findsOneWidget);

    await openShirt();
    expect(
      find.textContaining('Started from the measurements'),
      findsOneWidget,
    );
    expect(find.text('30'), findsWidgets); // prefilled
    await typeKeys(tester, '31'); // replaces length
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Length 31'), findsOneWidget);

    final sets = (await tester.runAsync(
      () => db.select(db.measurementSet).get(),
    ))!;
    expect(sets.map((s) => s.version).toList()..sort(), [1, 2]);
    expect(sets.firstWhere((s) => s.version == 2).supersedesId, isNotNull);
  });

  appTest('saving with no values warns and stays; leaving asks to discard', (
    tester,
    ctx,
  ) async {
    final db = ctx.db;
    await tester.pumpWidget(appOn(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add customer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Salma');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measurements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take measurements'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('garment-blouse')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter at least one measurement'), findsOneWidget);

    // An out-of-range value only warns.
    await typeKeys(tester, '5');
    await tester.pump();
    expect(find.text('Looks small, please check'), findsOneWidget);

    // Back → discard dialog.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard measurements?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Blouse measurements'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Blouse measurements'), findsNothing);
    final sets = (await tester.runAsync(
      () => db.select(db.measurementSet).get(),
    ))!;
    expect(sets, isEmpty);
  });

  appTest('entry screen works in Bangla with Bangla digits', (
    tester,
    ctx,
  ) async {
    final db = ctx.db;
    await tester.runAsync(() async {
      await db.customStatement(
        'INSERT INTO customer (id, name, name_norm, created_at, updated_at) '
        "VALUES ('c1', 'রহিম উদ্দিন', 'রহিম উদ্দিন', 1, 1)",
      );
    });
    await tester.pumpWidget(
      appOn(db, locale: 'bn', start: AppRoutes.measure('c1', 'panjabi')),
    );
    await tester.pumpAndSettle();

    expect(find.text('পাঞ্জাবি-এর মাপ'), findsOneWidget);
    expect(find.text('লম্বা'), findsWidgets);
    expect(find.text('বুক'), findsOneWidget);
    expect(find.text('রহিম উদ্দিন'), findsOneWidget);
    await typeKeys(tester, '42½');
    expect(find.text('৪২½'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  appTest('customer list: search, swipe to delete with undo', (
    tester,
    ctx,
  ) async {
    final db = ctx.db;
    await tester.pumpWidget(appOn(db));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final (i, name) in [
        'Rahim Uddin',
        'Karim Hossain',
        'রহিম',
      ].indexed) {
        await db.customStatement(
          'INSERT INTO customer (id, name, name_norm, created_at, updated_at) '
          "VALUES ('c$i', '$name', '${name.toLowerCase()}', 1, 1)",
        );
      }
    });
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.text('Rahim Uddin'), findsOneWidget);
    expect(find.text('Karim Hossain'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kar');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Karim Hossain'), findsOneWidget);
    expect(find.text('Rahim Uddin'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('No customers match'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Swipe left on Karim → removed with an undo action.
    await tester.drag(find.text('Karim Hossain'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Karim Hossain'), findsNothing);
    expect(find.text('Karim Hossain removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Karim Hossain'), findsOneWidget);
  });

  appTest('duplicate phone asks before saving', (tester, ctx) async {
    final db = ctx.db;
    await tester.runAsync(() async {
      await db.customStatement(
        'INSERT INTO customer (id, name, name_norm, phone, phone_digits, '
        "created_at, updated_at) VALUES ('c1','Rahim','rahim','+8801712345678',"
        "'01712345678',1,1)",
      );
    });
    await tester.pumpWidget(appOn(db, start: AppRoutes.customerNew));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Rahim Junior');
    await tester.enterText(find.byType(TextFormField).at(1), '+8801712345678');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Number already saved'), findsOneWidget);
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();
    final all = (await tester.runAsync(() => db.select(db.customer).get()))!;
    expect(all, hasLength(2));
  });

  appTest('invalid phone shows an inline error and saves nothing', (
    tester,
    ctx,
  ) async {
    final db = ctx.db;
    await tester.pumpWidget(appOn(db, start: AppRoutes.customerNew));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Rahim');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('valid mobile number'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.select(db.customer).get()))!,
      isEmpty,
    );

    await tester.tap(find.byType(TextFormField).at(0));
    await tester.enterText(find.byType(TextFormField).at(0), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a name'), findsOneWidget);
  });
}
