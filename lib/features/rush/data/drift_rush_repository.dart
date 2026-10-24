import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/domain/rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

class DriftRushRepository implements RushRepository {
  DriftRushRepository(this._db);

  final AppDatabase _db;

  static Season _season(SeasonRow r) => Season(
    id: r.id,
    name: r.name,
    kind: SeasonKind.fromDb(r.kind),
    targetDate: r.targetDate,
    dailyCapacity: r.dailyCapacity,
    workingDaysMask: r.workingDaysMask,
    closedDates: r.closedDatesJson == null
        ? const {}
        : (jsonDecode(r.closedDatesJson!) as List<dynamic>)
              .cast<String>()
              .toSet(),
    active: r.active,
  );

  @override
  Stream<List<Season>> watchSeasons() =>
      (_db.select(_db.season)
            ..where((t) => t.active.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.targetDate)]))
          .watch()
          .map((rows) => rows.map(_season).toList());

  SimpleSelectStatement<$SeasonTable, SeasonRow> _activeFrom(String today) =>
      _db.select(_db.season)
        ..where(
          (t) =>
              t.active.equals(true) & t.targetDate.isBiggerOrEqualValue(today),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.targetDate)])
        ..limit(1);

  @override
  Stream<Season?> watchActiveSeason(String today) =>
      _activeFrom(today)
          .watch()
          .map((rows) => rows.isEmpty ? null : _season(rows.first));

  @override
  Future<Season?> activeSeason(String today) async {
    final rows = await _activeFrom(today).get();
    return rows.isEmpty ? null : _season(rows.first);
  }

  @override
  Future<Season?> seasonById(String id) async {
    final row = await (_db.select(
      _db.season,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _season(row);
  }

  @override
  Future<void> save(Season season) => _db
      .into(_db.season)
      .insertOnConflictUpdate(
        SeasonCompanion.insert(
          id: season.id,
          name: season.name,
          kind: season.kind.dbValue,
          targetDate: season.targetDate,
          dailyCapacity: season.dailyCapacity,
          workingDaysMask: Value(season.workingDaysMask),
          closedDatesJson: Value(
            season.closedDates.isEmpty
                ? null
                : jsonEncode(season.closedDates.toList()..sort()),
          ),
          active: Value(season.active),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> deactivate(String id) =>
      (_db.update(_db.season)..where((t) => t.id.equals(id))).write(
        const SeasonCompanion(active: Value(false)),
      );

  // An IN list (not `!= 'delivered'`) lets SQLite use the status index and
  // skip the years of delivered history.
  static const String _open =
      'o.deleted_at IS NULL AND o.cancelled_at IS NULL AND '
      "i.status IN ('received', 'cut', 'stitching', 'finishing', 'ready')";

  @override
  Stream<List<RushItem>> watchOpenItems() => _db
      .customSelect(
        'SELECT i.id AS item_id, i.order_id, o.number, i.garment_type_id, '
        'i.qty, i.work_units, i.status, o.delivery_date '
        'FROM order_item i JOIN customer_order o ON o.id = i.order_id '
        'WHERE $_open',
        readsFrom: {_db.orderItem, _db.customerOrder},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            RushItem(
              itemId: r.read<String>('item_id'),
              orderId: r.read<String>('order_id'),
              orderNumber: r.read<int>('number'),
              garmentTypeId: r.read<String>('garment_type_id'),
              qty: r.read<int>('qty'),
              units: r.read<int>('work_units'),
              status: OrderStatus.fromDb(r.read<String>('status')),
              deliveryDate: r.read<String>('delivery_date'),
            ),
        ],
      );

  @override
  Stream<List<StageCount>> watchStageCounts({String? toDate}) => _db
      .customSelect(
        'SELECT i.garment_type_id, i.status, SUM(i.qty) AS garments, '
        'COUNT(*) AS lines '
        'FROM order_item i JOIN customer_order o ON o.id = i.order_id '
        'WHERE $_open ${toDate == null ? '' : 'AND o.delivery_date <= ?'} '
        'GROUP BY i.garment_type_id, i.status',
        variables: [if (toDate != null) Variable<String>(toDate)],
        readsFrom: {_db.orderItem, _db.customerOrder},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            StageCount(
              garmentTypeId: r.read<String>('garment_type_id'),
              status: OrderStatus.fromDb(r.read<String>('status')),
              garments: r.read<int>('garments'),
              lines: r.read<int>('lines'),
            ),
        ],
      );

  @override
  Future<List<String>> itemIds(
    String garmentTypeId,
    OrderStatus status, {
    String? toDate,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT i.id AS id FROM order_item i '
          'JOIN customer_order o ON o.id = i.order_id '
          'WHERE $_open AND i.garment_type_id = ? AND i.status = ? '
          '${toDate == null ? '' : 'AND o.delivery_date <= ?'} '
          'ORDER BY o.delivery_date, o.number',
          variables: [
            Variable<String>(garmentTypeId),
            Variable<String>(status.dbValue),
            if (toDate != null) Variable<String>(toDate),
          ],
          readsFrom: {_db.orderItem, _db.customerOrder},
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  @override
  Future<void> setGarmentWeight(String garmentTypeId, int units) {
    if (units <= 0) throw ArgumentError.value(units, 'units', 'must be > 0');
    return (_db.update(_db.garmentType)
          ..where((t) => t.id.equals(garmentTypeId)))
        .write(GarmentTypeCompanion(workUnits: Value(units)));
  }
}
