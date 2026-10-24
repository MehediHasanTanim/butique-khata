import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/schema_extras.dart';
import 'package:tailor_khata/core/db/tables/attachment_tables.dart';
import 'package:tailor_khata/core/db/tables/customer_tables.dart';
import 'package:tailor_khata/core/db/tables/measurement_tables.dart';
import 'package:tailor_khata/core/db/tables/order_tables.dart';
import 'package:tailor_khata/core/db/tables/season_tables.dart';
import 'package:tailor_khata/core/db/template_seeder.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';

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
    Worker,
    CustomerOrder,
    OrderItem,
    Payment,
    Attachment,
    Season,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump together with a new `fromXToY` step in [migration] (TD §9).
  static const int currentSchemaVersion = 5;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _applyV2Extras();
      await _applyV3Extras();
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
      if (from < 3) {
        await m.createTable(worker);
        await m.createTable(customerOrder);
        await m.createTable(orderItem);
        await m.createTable(payment);
        await m.createIndex(idxOrderDelivery);
        await m.createIndex(idxOrderCustomer);
        await m.createIndex(idxItemOrder);
        await m.createIndex(idxItemStatus);
        await m.createIndex(idxPaymentOrder);
        await _applyV3Extras();
      }
      if (from < 4) {
        await m.createTable(attachment);
        await m.createIndex(idxAttachmentOwner);
      }
      if (from < 5) {
        await m.createTable(season);
        // Tables created earlier in this same upgrade (from < 2 or < 3) were
        // built from today's definition and already have the new columns.
        if (from >= 2) await m.addColumn(garmentType, garmentType.workUnits);
        if (from >= 3) {
          await m.addColumn(customerOrder, customerOrder.seasonId);
          await m.addColumn(customerOrder, customerOrder.overbooked);
        }
        // Built-in garments get their standard capacity weights.
        for (final template in BuiltInTemplates.all) {
          await customStatement(
            'UPDATE garment_type SET work_units = ? WHERE id = ?',
            [template.workUnits, template.id],
          );
        }
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

  Future<void> _applyV3Extras() async {
    for (final statement in SchemaExtras.v3) {
      await customStatement(statement);
    }
  }
}
