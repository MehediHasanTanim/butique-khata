import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/schema_extras.dart';
import 'package:tailor_khata/core/db/tables/customer_tables.dart';
import 'package:tailor_khata/core/db/tables/measurement_tables.dart';
import 'package:tailor_khata/core/db/template_seeder.dart';

part 'app_database.g.dart';

/// Key/value application settings (locale, units, ...).
@DataClassName('AppSettingRow')
class AppSetting extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Who changed what and when. Written from v1, surfaced in the UI later.
@DataClassName('AuditLogRow')
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get at => integer()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get diffJson => text().nullable()();
}

@DriftDatabase(
  tables: [
    AppSetting,
    AuditLog,
    Customer,
    GarmentType,
    MeasurementField,
    MeasurementSet,
    MeasurementValue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump together with a new `fromXToY` step in [migration] (TD §9).
  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _applyV2Extras();
      await seedBuiltInTemplates(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(customer);
        await m.createTable(garmentType);
        await m.createTable(measurementField);
        await m.createTable(measurementSet);
        await m.createTable(measurementValue);
        await m.createIndex(idxCustomerPhone);
        await m.createIndex(idxCustomerName);
        await m.createIndex(idxMsetLookup);
        await _applyV2Extras();
        await seedBuiltInTemplates(this);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _applyV2Extras() async {
    for (final statement in SchemaExtras.v2) {
      await customStatement(statement);
    }
  }
}
