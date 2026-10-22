import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_repository.dart';

class DriftMeasurementRepository implements MeasurementRepository {
  DriftMeasurementRepository(this._db, this._clock, this._ids);

  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  static const int _maxAttempts = 5;

  // ---- templates ----------------------------------------------------------

  @override
  Future<List<GarmentInfo>> garments() async {
    final types =
        await (_db.select(_db.garmentType)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    final fields =
        await (_db.select(_db.measurementField)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    return types
        .map(
          (type) => GarmentInfo(
            id: type.id,
            key: type.key,
            labelEn: type.labelEn,
            labelBn: type.labelBn,
            fields: [
              for (final f in fields.where((f) => f.garmentTypeId == type.id))
                FieldTemplate(
                  key: f.key,
                  labelEn: f.labelEn,
                  labelBn: f.labelBn,
                  sortOrder: f.sortOrder,
                  minMm10: f.minMm10,
                  maxMm10: f.maxMm10,
                ),
            ],
          ),
        )
        .toList();
  }

  @override
  Stream<List<GarmentInfo>> watchGarments() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {_db.garmentType, _db.measurementField},
      )
      .watch()
      .asyncMap((_) => garments());

  // ---- writes -------------------------------------------------------------

  @override
  Future<Measurement> create(NewMeasurement input) async {
    if (input.values.isEmpty) {
      throw ArgumentError('A measurement needs at least one value');
    }
    for (var attempt = 1; ; attempt++) {
      try {
        return await _db.transaction(() => _insert(input));
      } on sqlite.SqliteException catch (error) {
        // 19 = constraint violation: another save took this version number.
        if (error.extendedResultCode != 2067 &&
            error.extendedResultCode != 1555 &&
            error.resultCode != 19) {
          rethrow;
        }
        if (attempt >= _maxAttempts) rethrow;
      }
    }
  }

  Future<Measurement> _insert(NewMeasurement input) async {
    final maxExpr = _db.measurementSet.version.max();
    final maxQuery = _db.selectOnly(_db.measurementSet)
      ..addColumns([maxExpr])
      ..where(
        _db.measurementSet.customerId.equals(input.customerId) &
            _db.measurementSet.garmentTypeId.equals(input.garmentTypeId),
      );
    final currentMax = (await maxQuery.getSingle()).read(maxExpr) ?? 0;

    final id = _ids.newId();
    final now = _clock.now();
    await _db
        .into(_db.measurementSet)
        .insert(
          MeasurementSetCompanion.insert(
            id: id,
            customerId: input.customerId,
            garmentTypeId: input.garmentTypeId,
            version: currentMax + 1,
            takenOn: input.takenOn,
            takenBy: Value(input.takenBy),
            note: Value(input.note),
            displayUnit: input.unit.dbValue,
            supersedesId: Value(input.supersedesId),
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
    await _db.batch((batch) {
      batch.insertAll(_db.measurementValue, [
        for (final entry in input.values.entries)
          MeasurementValueCompanion.insert(
            setId: id,
            fieldKey: entry.key,
            mm10: Value(entry.value.mm10),
          ),
      ]);
    });
    return (await byId(id))!;
  }

  @override
  Future<void> markError(String id) => _setStatus(id, 'error', 'mark_error');

  @override
  Future<void> restore(String id) => _setStatus(id, 'active', 'unmark_error');

  @override
  Future<void> setFitOutcome(String id, FitOutcome? outcome) => _db.transaction(
    () async {
      await (_db.update(_db.measurementSet)..where((t) => t.id.equals(id)))
          .write(MeasurementSetCompanion(fitOutcome: Value(outcome?.dbValue)));
      await _audit(id, 'fit_outcome', outcome?.dbValue);
    },
  );

  Future<void> _setStatus(String id, String status, String action) =>
      _db.transaction(() async {
        await (_db.update(_db.measurementSet)..where((t) => t.id.equals(id)))
            .write(MeasurementSetCompanion(status: Value(status)));
        await _audit(id, action, status);
      });

  Future<void> _audit(String id, String action, String? value) => _db
      .into(_db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          at: _clock.now().millisecondsSinceEpoch,
          entity: 'measurement_set',
          entityId: id,
          action: action,
          diffJson: Value(value == null ? null : '{"to":"$value"}'),
        ),
      );

  // ---- reads --------------------------------------------------------------

  @override
  Future<Measurement?> byId(String id) async {
    final row = await (_db.select(
      _db.measurementSet,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return (await _hydrate([row])).single;
  }

  SimpleSelectStatement<$MeasurementSetTable, MeasurementSetRow> _ordered(
    String customerId, {
    String? garmentTypeId,
    bool includeErrors = false,
  }) {
    return _db.select(_db.measurementSet)
      ..where((t) {
        var predicate = t.customerId.equals(customerId);
        if (garmentTypeId != null) {
          predicate = predicate & t.garmentTypeId.equals(garmentTypeId);
        }
        if (!includeErrors) predicate = predicate & t.status.equals('active');
        return predicate;
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.takenOn),
        (t) => OrderingTerm.desc(t.version),
      ]);
  }

  @override
  Future<Measurement?> latest(String customerId, String garmentTypeId) async {
    final rows = await (_ordered(
      customerId,
      garmentTypeId: garmentTypeId,
    )..limit(1)).get();
    if (rows.isEmpty) return null;
    return (await _hydrate(rows)).single;
  }

  @override
  Stream<List<Measurement>> watchVersions(
    String customerId,
    String garmentTypeId, {
    bool includeErrors = false,
  }) => _ordered(
    customerId,
    garmentTypeId: garmentTypeId,
    includeErrors: includeErrors,
  ).watch().asyncMap(_hydrate);

  @override
  Stream<List<Measurement>> watchLatestPerGarment(String customerId) =>
      _ordered(customerId).watch().asyncMap((rows) async {
        final seen = <String>{};
        final newest = [
          for (final row in rows)
            if (seen.add(row.garmentTypeId)) row,
        ];
        return _hydrate(newest);
      });

  @override
  Future<List<Measurement>> versions(
    String customerId,
    String garmentTypeId, {
    bool includeErrors = false,
  }) async {
    final rows = await _ordered(
      customerId,
      garmentTypeId: garmentTypeId,
      includeErrors: includeErrors,
    ).get();
    return _hydrate(rows);
  }

  Future<List<Measurement>> _hydrate(List<MeasurementSetRow> rows) async {
    if (rows.isEmpty) return const [];
    final values = await (_db.select(
      _db.measurementValue,
    )..where((t) => t.setId.isIn(rows.map((r) => r.id)))).get();
    final bySet = <String, Map<String, Length>>{};
    for (final v in values) {
      if (v.mm10 == null) continue;
      (bySet[v.setId] ??= {})[v.fieldKey] = Length.fromMm10(v.mm10!);
    }
    return [
      for (final row in rows)
        Measurement(
          id: row.id,
          customerId: row.customerId,
          garmentTypeId: row.garmentTypeId,
          version: row.version,
          takenOn: row.takenOn,
          takenBy: row.takenBy,
          note: row.note,
          unit: MeasureUnit.fromDb(row.displayUnit),
          status: MeasurementStatus.fromDb(row.status),
          supersedesId: row.supersedesId,
          fitOutcome: FitOutcome.fromDb(row.fitOutcome),
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
          values: bySet[row.id] ?? const {},
        ),
    ];
  }
}
