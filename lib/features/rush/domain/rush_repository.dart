import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

/// A garment line that still needs work, for planning.
class RushItem {
  const RushItem({
    required this.itemId,
    required this.orderId,
    required this.orderNumber,
    required this.garmentTypeId,
    required this.qty,
    required this.units,
    required this.status,
    required this.deliveryDate,
  });

  final String itemId;
  final String orderId;
  final int orderNumber;
  final String garmentTypeId;

  /// Number of garments on the line.
  final int qty;

  /// Work units ×100 for the whole line.
  final int units;
  final OrderStatus status;
  final String deliveryDate;

  /// Work still to do for this line, from its stage.
  WorkLoad get remainingWork => WorkLoad(
    deliveryDate,
    StageProgress.remainingUnits(units, status.dbValue),
  );
}

/// How many garments of one type are at one stage (E-8).
class StageCount {
  const StageCount({
    required this.garmentTypeId,
    required this.status,
    required this.garments,
    required this.lines,
  });

  final String garmentTypeId;
  final OrderStatus status;

  /// Garments (quantities added up).
  final int garments;

  /// Order lines.
  final int lines;
}

abstract class RushRepository {
  /// All seasons that are switched on, soonest target first.
  Stream<List<Season>> watchSeasons();

  /// The season to plan against on [today]: the soonest active one that has
  /// not passed yet.
  Stream<Season?> watchActiveSeason(String today);

  Future<Season?> activeSeason(String today);

  /// One season by id (active or not), or null.
  Future<Season?> seasonById(String id);

  /// Inserts or updates [season].
  Future<void> save(Season season);

  /// Switches a season off; orders keep their link to it.
  Future<void> deactivate(String id);

  /// Unfinished garment lines on open orders.
  Stream<List<RushItem>> watchOpenItems();

  /// Garments per type and stage on open orders due on or before [toDate]
  /// (all open orders when null).
  Stream<List<StageCount>> watchStageCounts({String? toDate});

  /// Lines at [status] for [garmentTypeId], optionally due by [toDate].
  Future<List<String>> itemIds(
    String garmentTypeId,
    OrderStatus status, {
    String? toDate,
  });

  /// Sets how much capacity one garment of the type uses (×100).
  Future<void> setGarmentWeight(String garmentTypeId, int units);
}
