import 'package:drift/drift.dart';

/// A busy period with a deadline (Eid, Puja, wedding season...) and the
/// shop's capacity for it (E-1, E-4).
@DataClassName('SeasonRow')
class Season extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `eid_fitr` | `eid_adha` | `puja` | `pohela_boishakh` | `wedding` |
  /// `custom`.
  TextColumn get kind => text()();

  /// The day everything must be ready by, `YYYY-MM-DD`.
  TextColumn get targetDate => text()();

  /// Work the shop gets through per working day, in work units ×100 (a
  /// standard garment is 100).
  IntColumn get dailyCapacity => integer()();

  /// Bit n is set when weekday n+1 (Monday = 1 … Sunday = 7) is a working
  /// day. 127 = every day.
  IntColumn get workingDaysMask => integer().withDefault(const Constant(127))();

  /// JSON list of `YYYY-MM-DD` dates the shop is closed.
  TextColumn get closedDatesJson => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
