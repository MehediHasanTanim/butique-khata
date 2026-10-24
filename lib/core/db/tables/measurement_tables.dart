import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/tables/customer_tables.dart';

@DataClassName('GarmentTypeRow')
class GarmentType extends Table {
  TextColumn get id => text()();

  /// Stable key: `panjabi`, `shirt`, ... or a generated key for custom ones.
  TextColumn get key => text().unique()();
  TextColumn get labelEn => text()();
  TextColumn get labelBn => text()();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// How much of the shop's capacity one garment uses, ×100 (Panjabi = 100,
  /// blouse 60, blazer 250). Used by the Eid-rush planning.
  IntColumn get workUnits => integer().withDefault(const Constant(100))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Editable template field of a garment type.
@DataClassName('MeasurementFieldRow')
class MeasurementField extends Table {
  TextColumn get id => text()();
  TextColumn get garmentTypeId => text().references(GarmentType, #id)();

  /// Stable per garment; copied into values so history survives renames.
  TextColumn get key => text()();
  TextColumn get labelEn => text()();
  TextColumn get labelBn => text()();

  /// `length` | `text` | `choice`.
  TextColumn get kind => text().withDefault(const Constant('length'))();

  /// Soft range in 0.1 mm units; out-of-range only warns.
  IntColumn get minMm10 => integer().nullable()();
  IntColumn get maxMm10 => integer().nullable()();
  IntColumn get sortOrder => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {garmentTypeId, key},
  ];
}

/// One dated measurement version. Append-only (see schema_extras triggers).
@DataClassName('MeasurementSetRow')
@TableIndex(
  name: 'idx_mset_lookup',
  columns: {#customerId, #garmentTypeId, #takenOn, #version},
)
class MeasurementSet extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customer, #id)();
  TextColumn get garmentTypeId => text().references(GarmentType, #id)();
  IntColumn get version => integer()();

  /// Calendar date `YYYY-MM-DD`; may be in the past (paper-book import).
  TextColumn get takenOn => text()();
  TextColumn get takenBy => text().nullable()();
  TextColumn get note => text().nullable()();

  /// `in` | `cm`: unit used at entry time.
  TextColumn get displayUnit => text()();

  /// `NULL` | `confirmed` | `altered`.
  TextColumn get fitOutcome => text().nullable()();

  /// `active` | `error`.
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get supersedesId => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {customerId, garmentTypeId, version},
  ];
}

@DataClassName('MeasurementValueRow')
class MeasurementValue extends Table {
  TextColumn get setId => text().references(MeasurementSet, #id)();

  /// Copied field key, deliberately not a foreign key.
  TextColumn get fieldKey => text()();
  IntColumn get mm10 => integer().nullable()();
  TextColumn get textValue => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {setId, fieldKey};
}
