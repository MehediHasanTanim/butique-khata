import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/tables/customer_tables.dart';
import 'package:tailor_khata/core/db/tables/measurement_tables.dart';

/// A karigor / worker. Table only in Sprint 3; assignment UI comes later.
@DataClassName('WorkerRow')
class Worker extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get specialty => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One visit / transaction: one or more garments, a delivery date, money.
/// (Not named `order` because that is an SQL keyword.)
@DataClassName('OrderRow')
@TableIndex(name: 'idx_order_delivery', columns: {#deliveryDate})
@TableIndex(name: 'idx_order_customer', columns: {#customerId})
class CustomerOrder extends Table {
  TextColumn get id => text()();

  /// Human slip number, sequential per shop.
  IntColumn get number => integer().unique()();
  TextColumn get customerId => text().references(Customer, #id)();

  /// `YYYY-MM-DD`.
  TextColumn get deliveryDate => text()();
  TextColumn get trialDate => text().nullable()();

  /// Poisha taken off the sum of item prices.
  IntColumn get discount => integer().withDefault(const Constant(0))();
  BoolColumn get urgent => boolean().withDefault(const Constant(false))();

  /// Roll-up of the item statuses, kept for indexed filtering.
  TextColumn get status => text()();
  TextColumn get note => text().nullable()();

  /// Season this order was planned for, if any.
  TextColumn get seasonId => text().nullable()();

  /// Taken on a date the plan said was already full (E-5).
  BoolColumn get overbooked => boolean().withDefault(const Constant(false))();

  /// Set for alteration / remake orders (later).
  TextColumn get parentOrderId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One garment in an order.
@DataClassName('OrderItemRow')
@TableIndex(name: 'idx_item_order', columns: {#orderId})
@TableIndex(name: 'idx_item_status', columns: {#status})
class OrderItem extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(CustomerOrder, #id)();
  TextColumn get garmentTypeId => text().references(GarmentType, #id)();
  IntColumn get qty => integer().withDefault(const Constant(1))();

  /// Line total in poisha (for [qty] garments).
  IntColumn get price => integer()();

  /// The exact immutable measurement version cut from (the snapshot, H-8).
  TextColumn get measurementSetId =>
      text().nullable().references(MeasurementSet, #id)();

  /// `shop` | `customer`.
  TextColumn get fabricSource => text().nullable()();
  TextColumn get colour => text().nullable()();

  /// JSON object: style group → chosen option key.
  TextColumn get styleJson => text().nullable()();
  TextColumn get note => text().nullable()();

  /// `received` | `cut` | `stitching` | `finishing` | `ready` | `delivered`.
  TextColumn get status => text()();
  IntColumn get statusChangedAt => integer()();
  TextColumn get workerId => text().nullable().references(Worker, #id)();

  /// Capacity weight ×100 (a standard garment is 100) for the Eid-rush view.
  IntColumn get workUnits => integer().withDefault(const Constant(100))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Money received (or returned) against an order. Rows are never edited:
/// a correction is a new row (negative for refunds).
@DataClassName('PaymentRow')
@TableIndex(name: 'idx_payment_order', columns: {#orderId})
class Payment extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(CustomerOrder, #id)();

  /// Poisha; negative for refunds.
  IntColumn get amount => integer()();

  /// `advance` | `payment` | `refund` | `adjustment`.
  TextColumn get kind => text()();

  /// `cash` | `bkash` | `nagad` | `bank` | `other`.
  TextColumn get method => text()();

  /// `YYYY-MM-DD`.
  TextColumn get paidOn => text()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
