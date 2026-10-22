import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

enum PaymentKind {
  advance,
  payment,
  refund,
  adjustment;

  String get dbValue => name;

  static PaymentKind fromDb(String v) =>
      PaymentKind.values.firstWhere((k) => k.name == v);
}

enum PayMethod {
  cash,
  bkash,
  nagad,
  bank,
  other;

  String get dbValue => name;

  static PayMethod fromDb(String v) =>
      PayMethod.values.firstWhere((m) => m.name == v, orElse: () => other);
}

enum FabricSource {
  shop,
  customer;

  String get dbValue => name;

  static FabricSource? fromDb(String? v) =>
      FabricSource.values.where((f) => f.name == v).firstOrNull;
}

/// What happens to money already paid when an order is cancelled (O-12).
enum CancelAdvance {
  /// Return it: a refund payment is recorded.
  refund,

  /// The shop keeps it; the order simply stops counting as owed.
  keep,
}

/// Total, paid and due of one order. Due is derived, never stored.
class OrderMoney {
  const OrderMoney({required this.total, required this.paid});

  /// Sum of item prices minus the discount.
  final Money total;

  /// Sum of all payments (refunds are negative).
  final Money paid;

  Money get due => total - paid;

  /// True when the customer owes something.
  bool get hasDue => due.isPositive;

  /// Paid more than the total (shown as credit).
  Money get credit => due.isNegative ? -due : Money.zero;

  bool get isSettled => due.isZero;

  /// Computes money from raw parts.
  factory OrderMoney.compute({
    required Iterable<Money> itemPrices,
    required Money discount,
    required Iterable<Money> payments,
  }) => OrderMoney(
    total: Money.sum(itemPrices) - discount,
    paid: Money.sum(payments),
  );
}

class Payment {
  const Payment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.kind,
    required this.method,
    required this.paidOn,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String orderId;
  final Money amount;
  final PaymentKind kind;
  final PayMethod method;
  final String paidOn;
  final String? note;
  final DateTime createdAt;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.garmentTypeId,
    required this.qty,
    required this.price,
    required this.status,
    required this.statusChangedAt,
    this.measurementSetId,
    this.fabricSource,
    this.colour,
    this.style = const {},
    this.note,
    this.workerId,
    this.workUnits = 100,
  });

  final String id;
  final String orderId;
  final String garmentTypeId;
  final int qty;
  final Money price;
  final OrderStatus status;
  final DateTime statusChangedAt;
  final String? measurementSetId;
  final FabricSource? fabricSource;
  final String? colour;
  final Map<String, String> style;
  final String? note;
  final String? workerId;
  final int workUnits;
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.customerId,
    required this.deliveryDate,
    required this.discount,
    required this.urgent,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.trialDate,
    this.note,
    this.parentOrderId,
    this.cancelledAt,
    this.cancelReason,
  });

  final String id;
  final int number;
  final String customerId;

  /// `YYYY-MM-DD`.
  final String deliveryDate;
  final String? trialDate;
  final Money discount;
  final bool urgent;
  final OrderStatus status;
  final String? note;
  final String? parentOrderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  bool get isCancelled => cancelledAt != null;

  /// Still to be made or handed over.
  bool get isOpen => !isCancelled && status != OrderStatus.delivered;
}

/// Everything about one order for the detail screen.
class OrderDetail {
  const OrderDetail({
    required this.order,
    required this.customerName,
    required this.items,
    required this.payments,
  });

  final Order order;
  final String customerName;
  final List<OrderItem> items;
  final List<Payment> payments;

  OrderMoney get money => OrderMoney.compute(
    itemPrices: items.map((i) => i.price),
    discount: order.discount,
    payments: payments.map((p) => p.amount),
  );
}

/// One row of an order list.
class OrderSummary {
  const OrderSummary({
    required this.order,
    required this.customerName,
    required this.itemCount,
    required this.money,
  });

  final Order order;
  final String customerName;
  final int itemCount;
  final OrderMoney money;
}

/// What one customer owes across all their open orders (P-5).
class CustomerDue {
  const CustomerDue({
    required this.customerId,
    required this.customerName,
    required this.due,
    required this.orderCount,
    required this.oldestDeliveryDate,
  });

  final String customerId;
  final String customerName;
  final Money due;
  final int orderCount;

  /// Earliest delivery date among the orders with a balance; the age of the
  /// debt.
  final String oldestDeliveryDate;
}

class AuditEntry {
  const AuditEntry({required this.at, required this.action, this.detail});

  final DateTime at;
  final String action;
  final String? detail;
}

// ---- inputs ----------------------------------------------------------------

class NewOrderItem {
  const NewOrderItem({
    required this.garmentTypeId,
    required this.price,
    this.qty = 1,
    this.measurementSetId,
    this.fabricSource,
    this.colour,
    this.style = const {},
    this.note,
    this.workUnits = 100,
    this.photos = const [],
  });

  /// Photos already saved in the media store (design pictures, swatches).
  final List<StoredImage> photos;

  final String garmentTypeId;
  final Money price;
  final int qty;
  final String? measurementSetId;
  final FabricSource? fabricSource;
  final String? colour;
  final Map<String, String> style;
  final String? note;
  final int workUnits;
}

class NewPayment {
  const NewPayment({
    required this.orderId,
    required this.amount,
    required this.method,
    required this.paidOn,
    this.kind = PaymentKind.payment,
    this.note,
  });

  final String orderId;
  final Money amount;
  final PayMethod method;
  final String paidOn;
  final PaymentKind kind;
  final String? note;
}

class NewOrder {
  const NewOrder({
    required this.customerId,
    required this.deliveryDate,
    required this.items,
    this.trialDate,
    this.discount = Money.zero,
    this.urgent = false,
    this.note,
    this.advance,
    this.parentOrderId,
  });

  final String customerId;
  final String deliveryDate;
  final String? trialDate;
  final List<NewOrderItem> items;
  final Money discount;
  final bool urgent;
  final String? note;

  /// Advance taken at order time (P-1).
  final NewPayment? advance;
  final String? parentOrderId;
}
