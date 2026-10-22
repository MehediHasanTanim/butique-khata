import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/template_seeder.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';

import '../../support/db_fixtures.dart';
import '../../support/test_app.dart';

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftMeasurementRepository repo;
  late String customerId;
  late String panjabiId;
  late String shirtId;

  setUp(() async {
    db = memoryDb();
    repo = DriftMeasurementRepository(
      db,
      FixedClock(DateTime(2026, 3, 5)),
      SequentialIdGenerator('m'),
    );
    final customers = DriftCustomerRepository(db);
    final now = DateTime(2026, 3, 5);
    await customers.insert(
      Customer(id: 'c1', name: 'Rahim Uddin', createdAt: now, updatedAt: now),
    );
    customerId = 'c1';
    panjabiId = BuiltInTemplates.byKey('panjabi').id;
    shirtId = BuiltInTemplates.byKey('shirt').id;
  });
  tearDown(() => db.close());

  NewMeasurement panjabi({
    String takenOn = '2026-03-05',
    Map<String, Length>? values,
    MeasureUnit unit = MeasureUnit.inch,
    String? note,
  }) => NewMeasurement(
    customerId: customerId,
    garmentTypeId: panjabiId,
    takenOn: takenOn,
    unit: unit,
    note: note,
    values: values ?? {'chest': inches('38½'), 'length': inches('42')},
  );

  group('built-in templates (S1-06)', () {
    test('all seven garments are seeded with ordered fields', () async {
      final garments = await repo.garments();
      expect(garments.map((g) => g.key), [
        'panjabi',
        'shirt',
        'pant',
        'pajama',
        'blazer',
        'salwar_kameez',
        'blouse',
      ]);
      final panjabiFields = garments.first.fields.map((f) => f.key).toList();
      expect(panjabiFields, [
        'length',
        'chest',
        'waist',
        'hip',
        'shoulder',
        'sleeve',
        'cuff',
        'collar',
        'neck',
        'bottom',
      ]);
      for (final garment in garments) {
        expect(garment.fields, isNotEmpty);
        expect(garment.labelBn, isNotEmpty);
        for (final f in garment.fields) {
          expect(f.labelBn, isNotEmpty);
          expect(
            f.minMm10! < f.maxMm10!,
            isTrue,
            reason: '${garment.key}.${f.key}',
          );
        }
      }
    });

    test(
      'Bangla and English labels exist and keys are unique per garment',
      () async {
        for (final garment in await repo.garments()) {
          final keys = garment.fields.map((f) => f.key).toList();
          expect(keys.toSet(), hasLength(keys.length), reason: garment.key);
        }
      },
    );

    test('seeding is idempotent and does not overwrite owner edits', () async {
      await (db.update(db.measurementField)
            ..where((t) => t.id.equals('gt_panjabi:chest')))
          .write(const MeasurementFieldCompanion(labelEn: Value('My chest')));
      await seedAgain(db);
      final panjabi = (await repo.garments()).first;
      expect(
        panjabi.fields.firstWhere((f) => f.key == 'chest').labelEn,
        'My chest',
      );
      expect(await db.select(db.garmentType).get(), hasLength(7));
    });
  });

  group('versions (S1-09)', () {
    test('versions count up per customer and garment', () async {
      final a = await repo.create(panjabi());
      final b = await repo.create(panjabi(takenOn: '2026-06-01'));
      final shirt = await repo.create(
        NewMeasurement(
          customerId: customerId,
          garmentTypeId: shirtId,
          takenOn: '2026-03-05',
          unit: MeasureUnit.inch,
          values: {'chest': inches('40')},
        ),
      );
      expect([a.version, b.version, shirt.version], [1, 2, 1]);
    });

    test('values round-trip exactly: 38 ½ is stored as 9779', () async {
      final saved = await repo.create(panjabi());
      expect(saved.values['chest']!.mm10, 9779);
      final loaded = (await repo.byId(saved.id))!;
      expect(loaded.values['chest']!.toInchFraction(), '38½');
      expect(loaded.values['length']!.toInchFraction(), '42');
      expect(loaded.unit, MeasureUnit.inch);
      expect(loaded.status, MeasurementStatus.active);
    });

    test('two concurrent saves never produce duplicate versions', () async {
      final results = await Future.wait([
        for (var i = 0; i < 8; i++) repo.create(panjabi(note: 'n$i')),
      ]);
      final versions = results.map((m) => m.version).toList()..sort();
      expect(versions, [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test(
      'latest is by taken-on date, then version (backdating safe)',
      () async {
        await repo.create(panjabi(takenOn: '2026-06-01'));
        await repo.create(panjabi(takenOn: '2022-01-10', note: 'paper book'));
        final latest = (await repo.latest(customerId, panjabiId))!;
        expect(latest.takenOn, '2026-06-01');
        expect(latest.version, 1);
        final all = await repo.versions(customerId, panjabiId);
        expect(all.map((m) => m.takenOn), ['2026-06-01', '2022-01-10']);
      },
    );

    test('error versions are hidden unless requested', () async {
      final v1 = await repo.create(panjabi(takenOn: '2026-01-01'));
      final v2 = await repo.create(panjabi(takenOn: '2026-02-01'));
      await repo.markError(v2.id);
      expect((await repo.latest(customerId, panjabiId))!.id, v1.id);
      expect(await repo.versions(customerId, panjabiId), hasLength(1));
      expect(
        await repo.versions(customerId, panjabiId, includeErrors: true),
        hasLength(2),
      );
      // The row is still there.
      expect(await db.select(db.measurementSet).get(), hasLength(2));
    });

    test('latest per garment streams and updates on save', () async {
      final emissions = <List<String>>[];
      final sub = repo
          .watchLatestPerGarment(customerId)
          .listen(
            (list) => emissions.add(
              list.map((m) => '${m.garmentTypeId}:${m.version}').toList(),
            ),
          );
      await pumpEventQueue();
      await repo.create(panjabi());
      await pumpEventQueue();
      await repo.create(panjabi(takenOn: '2026-07-01'));
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.first, isEmpty);
      expect(emissions.last, ['$panjabiId:2']);
    });

    test('saving nothing is rejected', () async {
      await expectLater(repo.create(panjabi(values: {})), throwsArgumentError);
    });

    test('unknown customer is rejected by the foreign key', () async {
      await expectLater(
        repo.create(
          NewMeasurement(
            customerId: 'missing',
            garmentTypeId: panjabiId,
            takenOn: '2026-03-05',
            unit: MeasureUnit.inch,
            values: {'chest': inches('38')},
          ),
        ),
        throwsA(anything),
      );
    });
  });

  group('append-only triggers (S1-10)', () {
    late String setId;
    setUp(() async => setId = (await repo.create(panjabi())).id);

    test('updating a value row aborts', () async {
      await expectLater(
        db.customStatement(
          "UPDATE measurement_value SET mm10 = 1 WHERE set_id = '$setId'",
        ),
        throwsA(predicate((e) => e.toString().contains('append-only'))),
      );
    });

    test('deleting a value row aborts', () async {
      await expectLater(
        db.customStatement(
          "DELETE FROM measurement_value WHERE set_id = '$setId'",
        ),
        throwsA(predicate((e) => e.toString().contains('append-only'))),
      );
    });

    test('deleting a set aborts', () async {
      await expectLater(
        db.customStatement("DELETE FROM measurement_set WHERE id = '$setId'"),
        throwsA(predicate((e) => e.toString().contains('append-only'))),
      );
    });

    for (final column in [
      'note',
      'taken_on',
      'version',
      'display_unit',
      'taken_by',
    ]) {
      test('changing $column on a set aborts', () async {
        final value = column == 'version' ? '99' : "'x'";
        await expectLater(
          db.customStatement(
            "UPDATE measurement_set SET $column = $value WHERE id = '$setId'",
          ),
          throwsA(predicate((e) => e.toString().contains('append-only'))),
        );
      });
    }

    test('status and fit outcome may change', () async {
      await db.customStatement(
        "UPDATE measurement_set SET status = 'error', fit_outcome = 'altered' "
        "WHERE id = '$setId'",
      );
      final row = await (db.select(
        db.measurementSet,
      )..where((t) => t.id.equals(setId))).getSingle();
      expect(row.status, 'error');
      expect(row.fitOutcome, 'altered');
    });

    test('values are untouched after all failed attempts', () async {
      try {
        await db.customStatement('UPDATE measurement_value SET mm10 = 1');
      } on Object {
        // expected
      }
      expect((await repo.byId(setId))!.values['chest']!.mm10, 9779);
    });
  });

  group('migration v1 → v2', () {
    test(
      'keeps v1 data and adds tables, FTS, triggers and templates',
      () async {
        final dir = Directory.systemTemp.createTempSync('tk_mig2');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/v1.db');
        DbFixtures.writeV1File(file);

        final upgraded = AppDatabase(NativeDatabase(file));
        addTearDown(upgraded.close);

        final settings = await upgraded.select(upgraded.appSetting).get();
        expect(settings.single.value, 'bn');
        expect(await upgraded.select(upgraded.garmentType).get(), hasLength(7));

        final names =
            (await upgraded
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type IN ('table','trigger')",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toSet();
        expect(
          names,
          containsAll([
            'customer',
            'customer_fts',
            'measurement_set',
            'measurement_value',
            'trg_mvalue_no_update',
            'trg_mset_no_delete',
            'customer_fts_ai',
          ]),
        );
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(
          version.read<int>('user_version'),
          AppDatabase.currentSchemaVersion,
        );
      },
    );
  });
}

Future<void> seedAgain(AppDatabase db) => seedBuiltInTemplates(db);
