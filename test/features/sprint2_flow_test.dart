import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_trend_screen.dart';

import '../support/flow_helpers.dart';
import '../support/test_app.dart';

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

late String panjabiId;

/// Customer "Rahim Uddin" with four Panjabi versions.
Future<void> seed(AppDatabase db) async {
  final now = DateTime(2026, 3, 5);
  await DriftCustomerRepository(db).insert(
    Customer(id: 'c1', name: 'Rahim Uddin', createdAt: now, updatedAt: now),
  );
  panjabiId = BuiltInTemplates.byKey('panjabi').id;
  final repo = DriftMeasurementRepository(
    db,
    FixedClock(now),
    SequentialIdGenerator('m'),
  );
  Future<void> add(String date, Map<String, String> values) => repo.create(
    NewMeasurement(
      customerId: 'c1',
      garmentTypeId: panjabiId,
      takenOn: date,
      unit: MeasureUnit.inch,
      values: {for (final e in values.entries) e.key: inches(e.value)},
    ),
  );
  await add('2022-02-10', {'length': '42', 'chest': '36'});
  await add('2023-03-01', {'length': '42', 'chest': '38'});
  await add('2024-05-05', {'length': '42', 'chest': '38', 'waist': '34'});
  await add('2026-01-02', {'length': '42', 'chest': '40', 'waist': '34'});
}

void main() {
  late AppDatabase db;

  Future<void> open(
    WidgetTester tester,
    String route, {
    String locale = 'en',
  }) async {
    phoneScreen(tester);
    db = memoryDb();
    await tester.runAsync(() => seed(db));
    await tester.pumpWidget(appOn(db, start: route, locale: locale));
    await tester.pumpAndSettle();
  }

  Future<void> choose(
    WidgetTester tester,
    String versionId,
    String item,
  ) async {
    await tester.tap(find.byKey(ValueKey('menu-$versionId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Future<String> idOfVersion(WidgetTester tester, int version) async {
    final rows = (await tester.runAsync(
      () => db.select(db.measurementSet).get(),
    ))!;
    return rows.firstWhere((r) => r.version == version).id;
  }

  group('trendPoints', () {
    Measurement m(
      int v,
      String date,
      Map<String, String> values, {
      MeasurementStatus status = MeasurementStatus.active,
    }) => Measurement(
      id: 'id$v',
      customerId: 'c',
      garmentTypeId: 'g',
      version: v,
      takenOn: date,
      unit: MeasureUnit.inch,
      status: status,
      createdAt: DateTime(2026),
      values: {for (final e in values.entries) e.key: inches(e.value)},
    );

    test('oldest first, skips errors and versions without the field', () {
      final points = trendPoints(
        [
          m(3, '2026-01-01', {'chest': '40'}),
          m(2, '2024-01-01', {'chest': '38', 'waist': '34'}),
          m(1, '2022-01-01', {'chest': '36'}),
          m(4, '2026-06-01', {'chest': '50'}, status: MeasurementStatus.error),
        ],
        'chest',
        MeasureUnit.inch,
      );
      expect(points.map((p) => p.date), [
        '2022-01-01',
        '2024-01-01',
        '2026-01-01',
      ]);
      expect(points.map((p) => p.value), [36, 38, 40]);
      expect(
        trendPoints(
          [
            m(1, '2022-01-01', {'chest': '36'}),
          ],
          'waist',
          MeasureUnit.inch,
        ),
        isEmpty,
      );
    });

    test('centimetres', () {
      final points = trendPoints(
        [
          m(1, '2022-01-01', {'chest': '10'}),
        ],
        'chest',
        MeasureUnit.cm,
      );
      expect(points.single.value, closeTo(25.4, 0.001));
    });
  });

  testWidgets('timeline lists versions newest first with change summaries', (
    tester,
  ) async {
    await open(tester, AppRoutes.history('c1', 'panjabi'));

    expect(find.text('Panjabi / Kurta history'), findsOneWidget);
    expect(find.textContaining('v4 · '), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Chest 40'), findsOneWidget);
    expect(find.text('Chest +2'), findsWidgets);

    // Scroll to the oldest entries (the list builds lazily).
    await tester.dragUntilVisible(
      find.textContaining('v1 · '),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('First entry'), findsOneWidget);
    expect(find.text('Chest 36'), findsOneWidget);
    expect(find.textContaining('v2 · '), findsOneWidget);
    expect(find.text('Chest +2'), findsWidgets); // v2 shown now
    await shutDown(tester, db);
  });

  testWidgets(
    'mark as error hides a version; toggle shows it; restore brings it back',
    (tester) async {
      await open(tester, AppRoutes.history('c1', 'panjabi'));
      final v4 = await idOfVersion(tester, 4);

      await choose(tester, v4, 'Mark as entered in error');
      expect(find.text('Mark as entered in error?'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('v4 · '), findsNothing);
      expect(find.text('Latest'), findsOneWidget); // now v3
      expect(find.text('Chest 40'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('v4 · '), findsOneWidget);
      expect(find.text('Entered in error'), findsOneWidget);

      await choose(tester, v4, 'Restore this entry');
      expect(find.text('Entered in error'), findsNothing);
      expect(find.text('Latest'), findsOneWidget);

      // Nothing was ever deleted.
      final rows = (await tester.runAsync(
        () => db.select(db.measurementSet).get(),
      ))!;
      expect(rows, hasLength(4));
      final audit = (await tester.runAsync(
        () => db.select(db.auditLog).get(),
      ))!;
      expect(audit.map((a) => a.action), ['mark_error', 'unmark_error']);
      await shutDown(tester, db);
    },
  );

  testWidgets('fit result can be recorded and cleared', (tester) async {
    await open(tester, AppRoutes.history('c1', 'panjabi'));
    final v2 = await idOfVersion(tester, 2);

    await choose(tester, v2, 'Fit confirmed');
    expect(find.text('Fit confirmed'), findsOneWidget);

    await choose(tester, v2, 'Needed alteration');
    expect(find.text('Needed alteration'), findsOneWidget);
    expect(find.text('Fit confirmed'), findsNothing);

    await choose(tester, v2, 'Clear fit result');
    expect(find.text('Needed alteration'), findsNothing);
    await shutDown(tester, db);
  });

  testWidgets('compare with previous highlights deltas; changed-only filters', (
    tester,
  ) async {
    await open(tester, AppRoutes.history('c1', 'panjabi'));
    final v2 = await idOfVersion(tester, 2);

    await choose(tester, v2, 'Compare with previous');
    expect(find.text('Compare'), findsOneWidget);
    // v1 → v2: chest 36 → 38 (+2); length unchanged.
    expect(find.byKey(const ValueKey('delta-chest')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('delta-chest'))).data,
      '+2',
    );
    expect(find.byKey(const ValueKey('delta-length')), findsNothing);
    expect(find.byKey(const ValueKey('cmp-length')), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cmp-length')), findsNothing);
    expect(find.byKey(const ValueKey('cmp-chest')), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('compare any two versions, including added fields', (
    tester,
  ) async {
    await open(tester, AppRoutes.compare('c1', 'panjabi'));
    // Defaults: latest (v4) vs previous (v3): chest 38 → 40.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('delta-chest'))).data,
      '+2',
    );

    // Pick v1 as the earlier version: waist was added, chest +4.
    await tester.tap(find.byKey(const ValueKey('pick-earlier')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('v1 · ').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('delta-chest'))).data,
      '+4',
    );
    expect(find.text('added'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('compare needs two versions', (tester) async {
    phoneScreen(tester);
    db = memoryDb();
    await tester.runAsync(() async {
      await seed(db);
      await db.customStatement(
        "UPDATE measurement_set SET status = 'error' WHERE version > 1",
      );
    });
    await tester.pumpWidget(
      appOn(db, start: AppRoutes.compare('c1', 'panjabi')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Save at least two measurements to compare.'),
      findsOneWidget,
    );
    await shutDown(tester, db);
  });

  testWidgets('trend chart offers fields measured at least twice', (
    tester,
  ) async {
    await open(tester, AppRoutes.trend('c1', 'panjabi'));
    expect(find.byKey(const ValueKey('trend-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend-chest')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend-length')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend-waist')), findsOneWidget); // v3, v4
    expect(find.byKey(const ValueKey('trend-hip')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('trend-length')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await shutDown(tester, db);
  });

  testWidgets('trend with one version shows guidance', (tester) async {
    phoneScreen(tester);
    db = memoryDb();
    await tester.runAsync(() async {
      await seed(db);
      await db.customStatement(
        "UPDATE measurement_set SET status = 'error' WHERE version > 1",
      );
    });
    await tester.pumpWidget(appOn(db, start: AppRoutes.trend('c1', 'panjabi')));
    await tester.pumpAndSettle();
    expect(
      find.text('Save at least two measurements to see a trend.'),
      findsOneWidget,
    );
    await shutDown(tester, db);
  });

  testWidgets('a big change asks for confirmation before saving v5', (
    tester,
  ) async {
    await open(tester, AppRoutes.measure('c1', 'panjabi'));
    expect(
      find.textContaining('Started from the measurements'),
      findsOneWidget,
    );

    // Focus Chest (second field) and type 46 instead of 40: +6.
    await tester.tap(find.text('Chest').first);
    await tester.pump();
    await typeKeys(tester, '46');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Check these changes'), findsOneWidget);
    expect(find.text('Chest: 40 → 46 (+6)'), findsOneWidget);

    // Go back keeps editing and saves nothing.
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(() => db.select(db.measurementSet).get()))!,
      hasLength(4),
    );

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, save'));
    await tester.pumpAndSettle();
    final rows = (await tester.runAsync(
      () => db.select(db.measurementSet).get(),
    ))!;
    expect(rows, hasLength(5));
    expect(rows.firstWhere((r) => r.version == 5).supersedesId, isNotNull);
    await shutDown(tester, db);
  });

  testWidgets('a small change saves without a prompt', (tester) async {
    await open(tester, AppRoutes.measure('c1', 'panjabi'));
    await tester.tap(find.text('Chest').first);
    await tester.pump();
    await typeKeys(tester, '41');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Check these changes'), findsNothing);
    expect(
      (await tester.runAsync(() => db.select(db.measurementSet).get()))!,
      hasLength(5),
    );
    await shutDown(tester, db);
  });

  testWidgets('saving unchanged values creates no new version', (tester) async {
    await open(tester, AppRoutes.measure('c1', 'panjabi'));
    // Prefilled with the latest values; nothing edited. Typing is needed to
    // enable the discard guard, so just save directly.
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('No changes: these are already your latest measurements'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(() => db.select(db.measurementSet).get()))!,
      hasLength(4),
    );
    await shutDown(tester, db);
  });

  testWidgets('history works in Bangla with Bangla digits', (tester) async {
    await open(tester, AppRoutes.history('c1', 'panjabi'), locale: 'bn');
    expect(find.text('পাঞ্জাবি-এর ইতিহাস'), findsOneWidget);
    expect(find.text('প্রথম এন্ট্রি'), findsOneWidget);
    expect(find.text('সর্বশেষ'), findsOneWidget);
    expect(find.textContaining('সং ৪'), findsOneWidget);
    expect(find.text('বুক ৪০'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutDown(tester, db);
  });
}
