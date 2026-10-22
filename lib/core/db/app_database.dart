import 'package:drift/drift.dart';

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

@DriftDatabase(tables: [AppSetting, AuditLog])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump together with a new `fromXToY` step in [migration] (TD §9).
  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Migrations are additive and run step by step; none exist yet.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
