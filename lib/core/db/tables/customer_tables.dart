import 'package:drift/drift.dart';

/// A person (or walk-in) the shop makes garments for. Soft-deleted only.
@DataClassName('CustomerRow')
@TableIndex(name: 'idx_customer_phone', columns: {#phoneDigits})
@TableIndex(name: 'idx_customer_name', columns: {#nameNorm})
class Customer extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Search key from `NameNormalizer.normalize`.
  TextColumn get nameNorm => text()();

  /// Canonical E.164 number, e.g. `+8801712345678`.
  TextColumn get phone => text().nullable()();

  /// National digits for substring search, e.g. `01712345678`.
  TextColumn get phoneDigits => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  /// Groups related customers (family profiles, v1.1).
  TextColumn get familyId => text().nullable()();

  /// Slip number for walk-ins who gave no phone.
  TextColumn get slipToken => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
