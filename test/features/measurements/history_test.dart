import 'package:flutter_test/flutter_test.dart';
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
import 'package:tailor_khata/features/measurements/domain/measurement_diff.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/domain/save_measurement.dart';

import '../../support/test_app.dart';

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

void main() {
  group('diffMeasurements (S2-03)', () {
    test('chest 38 → 40 is a +2 change', () {
      final deltas = diffMeasurements(
        {'chest': inches('38'), 'waist': inches('34')},
        {'chest': inches('40'), 'waist': inches('34')},
        order: ['chest', 'waist'],
      );
      expect(deltas.map((d) => d.key), ['chest', 'waist']);
      expect(deltas[0].kind, DeltaKind.changed);
      expect(formatDelta(deltas[0].delta!, MeasureUnit.inch), '+2');
      expect(deltas[1].kind, DeltaKind.same);
      expect(deltas[1].isChange, isFalse);
    });

    test('fields in only one version are added / removed', () {
      final deltas = diffMeasurements(
        {'length': inches('42'), 'hip': inches('40')},
        {'length': inches('42'), 'neck': inches('15')},
      );
      final byKey = {for (final d in deltas) d.key: d};
      expect(byKey['hip']!.kind, DeltaKind.removed);
      expect(byKey['hip']!.delta, isNull);
      expect(byKey['neck']!.kind, DeltaKind.added);
      expect(byKey['length']!.kind, DeltaKind.same);
    });

    test('order follows the template, unknown keys sort last', () {
      final deltas = diffMeasurements(
        {'z': inches('1'), 'b': inches('1'), 'chest': inches('1')},
        {'z': inches('1'), 'b': inches('1'), 'chest': inches('1')},
        order: ['chest', 'waist'],
      );
      expect(deltas.map((d) => d.key), ['chest', 'b', 'z']);
    });

    test('works across garments on shared keys only', () {
      final panjabi = {'chest': inches('38'), 'sleeve': inches('25')};
      final pant = {'waist': inches('32'), 'chest': inches('39')};
      final changed = diffMeasurements(
        panjabi,
        pant,
      ).where((d) => d.kind == DeltaKind.changed).map((d) => d.key);
      expect(changed, ['chest']);
    });

    test('negative and fractional deltas format with a sign', () {
      expect(formatDelta(inches('38') - inches('38½'), MeasureUnit.inch), '-½');
      expect(
        formatDelta(inches('40½') - inches('38'), MeasureUnit.inch),
        '+2½',
      );
      expect(formatDelta(Length.zero, MeasureUnit.inch), '0');
      expect(formatDelta(const Length.fromMm10(100), MeasureUnit.cm), '+1.0');
      expect(formatDelta(inches('2'), MeasureUnit.inch, bangla: true), '+২');
    });

    test('sameValues is exact', () {
      expect(sameValues({'a': inches('1')}, {'a': inches('1')}), isTrue);
      expect(sameValues({'a': inches('1')}, {'a': inches('1½')}), isFalse);
      expect(sameValues({'a': inches('1')}, {'b': inches('1')}), isFalse);
      expect(
        sameValues({'a': inches('1')}, {'a': inches('1'), 'b': inches('1')}),
        isFalse,
      );
    });
  });

  group('largeChanges (S2-06)', () {
    test('flags moves above 1.5 inch only', () {
      final big = largeChanges(
        {'chest': inches('38'), 'waist': inches('34'), 'hip': inches('40')},
        {'chest': inches('44'), 'waist': inches('35½'), 'hip': inches('41')},
      );
      expect(big.map((d) => d.key), ['chest']);
    });

    test('exactly 1.5 inch is not flagged; decreases are', () {
      expect(largeChanges({'a': inches('30')}, {'a': inches('31½')}), isEmpty);
      expect(
        largeChanges({'a': inches('30')}, {'a': inches('27')}),
        hasLength(1),
      );
    });

    test('added or removed fields are not large changes', () {
      expect(largeChanges({'a': inches('30')}, {'b': inches('50')}), isEmpty);
    });

    test('threshold is configurable', () {
      expect(
        largeChanges(
          {'a': inches('30')},
          {'a': inches('31')},
          thresholdMm10: 100,
        ),
        hasLength(1),
      );
    });
  });

  group('history with a database', () {
    late AppDatabase db;
    late DriftMeasurementRepository repo;
    late SaveMeasurement save;
    late String panjabiId;
    late DateTime now;

    setUp(() async {
      db = memoryDb();
      now = DateTime(2026, 3, 5);
      repo = DriftMeasurementRepository(
        db,
        FixedClock(now),
        SequentialIdGenerator('m'),
      );
      save = SaveMeasurement(repo);
      await DriftCustomerRepository(db).insert(
        Customer(id: 'c1', name: 'Rahim', createdAt: now, updatedAt: now),
      );
      panjabiId = BuiltInTemplates.byKey('panjabi').id;
    });
    tearDown(() => db.close());

    NewMeasurement input(
      Map<String, Length> values, {
      String takenOn = '2026-03-05',
    }) => NewMeasurement(
      customerId: 'c1',
      garmentTypeId: panjabiId,
      takenOn: takenOn,
      unit: MeasureUnit.inch,
      values: values,
    );

    test('unchanged values create no new row (S2-01)', () async {
      final first = await save(
        input({'chest': inches('38'), 'length': inches('42')}),
      );
      expect(first, isA<MeasurementSaved>());
      final again = await save(
        input({
          'length': inches('42'),
          'chest': inches('38'),
        }, takenOn: '2026-09-01'),
      );
      expect(again, isA<MeasurementUnchanged>());
      expect((again as MeasurementUnchanged).latest.version, 1);
      expect(await db.select(db.measurementSet).get(), hasLength(1));
    });

    test('one changed field makes v2 linked to v1, v1 untouched', () async {
      final v1 = (await save(
        input({'chest': inches('38'), 'length': inches('42')}),
      )) as MeasurementSaved;
      final v2 = (await save(
        input({'chest': inches('40'), 'length': inches('42')}),
      )) as MeasurementSaved;
      expect(v2.measurement.version, 2);
      expect(v2.measurement.supersedesId, v1.measurement.id);
      final reloaded = (await repo.byId(v1.measurement.id))!;
      expect(reloaded.values['chest'], inches('38'));
      expect(reloaded.version, 1);
    });

    test('adding a field counts as a change', () async {
      await save(input({'chest': inches('38')}));
      final out = await save(
        input({'chest': inches('38'), 'waist': inches('34')}),
      );
      expect(out, isA<MeasurementSaved>());
    });

    test(
      'an entered-in-error latest is ignored for change detection',
      () async {
        final v1 =
            (await save(input({'chest': inches('38')}))) as MeasurementSaved;
        final v2 =
            (await save(input({'chest': inches('44')}))) as MeasurementSaved;
        await repo.markError(v2.measurement.id);
        // Same as v1 (the real latest now) → unchanged, supersedes not needed.
        expect(
          await save(input({'chest': inches('38')})),
          isA<MeasurementUnchanged>(),
        );
        expect((await repo.latest('c1', panjabiId))!.id, v1.measurement.id);
      },
    );

    test(
      'backdated save links to current latest and keeps it latest (S2-02)',
      () async {
        await save(input({'chest': inches('40')}, takenOn: '2026-06-01'));
        final old = (await save(
          input({'chest': inches('36')}, takenOn: '2021-02-01'),
        )) as MeasurementSaved;
        expect(old.measurement.version, 2);
        expect((await repo.latest('c1', panjabiId))!.takenOn, '2026-06-01');
        final all = await repo.versions('c1', panjabiId);
        expect(all.map((m) => m.takenOn), ['2026-06-01', '2021-02-01']);
      },
    );

    test('mark error is reversible and audit-logged (S2-07)', () async {
      final v1 =
          (await save(input({'chest': inches('38')}))) as MeasurementSaved;
      final id = v1.measurement.id;
      await repo.markError(id);
      expect(await repo.latest('c1', panjabiId), isNull);
      expect(await repo.versions('c1', panjabiId), isEmpty);
      expect(
        await repo.versions('c1', panjabiId, includeErrors: true),
        hasLength(1),
      );
      await repo.restore(id);
      expect((await repo.latest('c1', panjabiId))!.id, id);
      final log = await db.select(db.auditLog).get();
      expect(log.map((r) => r.action), ['mark_error', 'unmark_error']);
      expect(log.every((r) => r.entityId == id), isTrue);
    });

    test('fit outcome can be set, changed and cleared (S2-09)', () async {
      final id = ((await save(
        input({'chest': inches('38')}),
      )) as MeasurementSaved).measurement.id;
      expect((await repo.byId(id))!.fitOutcome, isNull);
      await repo.setFitOutcome(id, FitOutcome.confirmed);
      expect((await repo.byId(id))!.fitOutcome, FitOutcome.confirmed);
      await repo.setFitOutcome(id, FitOutcome.altered);
      expect((await repo.byId(id))!.fitOutcome, FitOutcome.altered);
      await repo.setFitOutcome(id, null);
      expect((await repo.byId(id))!.fitOutcome, isNull);
      expect(await db.select(db.auditLog).get(), hasLength(3));
    });

    test('watchVersions re-emits on save and on error flag', () async {
      final seen = <int>[];
      final sub = repo
          .watchVersions('c1', panjabiId)
          .listen((l) => seen.add(l.length));
      await pumpEventQueue();
      final v1 =
          (await save(input({'chest': inches('38')}))) as MeasurementSaved;
      await pumpEventQueue();
      await repo.markError(v1.measurement.id);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [0, 1, 0]);
    });

    test('history of 50 versions loads in under 100 ms (S2-11)', () async {
      for (var i = 0; i < 50; i++) {
        await repo.create(
          input({
            'length': inches('42'),
            'chest': Length.fromMm10(9779 + i),
            'waist': inches('34'),
            'hip': inches('40'),
            'shoulder': inches('18'),
            'sleeve': inches('25'),
            'cuff': inches('9'),
            'collar': inches('15'),
            'neck': inches('15'),
            'bottom': inches('20'),
          }, takenOn: '2026-01-${(i % 28 + 1).toString().padLeft(2, '0')}'),
        );
      }
      final samples = <int>[];
      late List<Measurement> versions;
      for (var run = 0; run < 5; run++) {
        final watch = Stopwatch()..start();
        versions = await repo.versions('c1', panjabiId);
        watch.stop();
        samples.add(watch.elapsedMilliseconds);
      }
      // ignore: avoid_print
      print('versions() ms: $samples');
      expect(versions, hasLength(50));
      expect(versions.first.values, hasLength(10));
      expect(samples.reduce((a, b) => a < b ? a : b), lessThan(100));
    });
  });
}
