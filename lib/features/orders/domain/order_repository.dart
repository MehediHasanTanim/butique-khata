import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

abstract class OrderRepository {
  /// Creates the order, its items and the advance payment in one transaction
  /// and assigns the next slip number.
  Future<OrderDetail> create(NewOrder input);

  Future<OrderDetail?> detail(String id);
  Stream<OrderDetail?> watchDetail(String id);

  /// Orders not deleted, soonest delivery first. With [customerId] only that
  /// customer's. With [openOnly] cancelled and fully delivered ones are left
  /// out.
  Stream<List<OrderSummary>> watchSummaries({
    String? customerId,
    bool openOnly = false,
    OrderFilter? filter,
  });

  /// One page of open orders with a delivery date in `[from, to]`, soonest
  /// first, starting after [after] (keyset paging, so it stays fast with
  /// thousands of orders).
  Future<List<OrderSummary>> deliveriesPage({
    String? from,
    String? to,
    DeliveryCursor? after,
    int limit = 30,
  });

  /// Open orders that have been ready since [olderThanMillis] or earlier
  /// without being collected.
  Future<List<OrderSummary>> uncollected({required int olderThanMillis});

  Stream<DeliveryCounts> watchDeliveryCounts({
    required DeliveryBuckets buckets,
    required int uncollectedBeforeMillis,
  });

  /// Open orders grouped by delivery date from [fromDate] on, for reminders.
  Stream<List<DeliveryDay>> watchOpenDeliveryDays();

  Stream<DashboardStats> watchDashboard({
    required String today,
    required int startOfTodayMillis,
  });

  /// Customers who owe money on non-cancelled orders.
  Stream<List<CustomerDue>> watchDues();

  /// What one customer owes in total.
  Stream<Money> watchCustomerDue(String customerId);

  Future<Payment> addPayment(NewPayment payment);

  /// Moves one item and rolls the order status up in the same transaction.
  /// Throws [StateError] for a disallowed move.
  ///
  /// Delivering while the order has a balance throws [DueOutstandingError]
  /// unless [dueConfirmed] (P-4); prefer [deliverAll].
  Future<void> setItemStatus(
    String itemId,
    OrderStatus to, {
    bool dueConfirmed = false,
  });

  /// Moves every item that is allowed to move to [to] (bulk update, O-8).
  Future<void> setAllItemsStatus(
    String orderId,
    OrderStatus to, {
    bool dueConfirmed = false,
  });

  /// Moves every listed garment line to [to] in one transaction (batch
  /// update, E-8). Lines of cancelled orders, and lines that cannot make that
  /// move, are skipped. Returns how many moved. Delivering is not allowed
  /// here: use [deliverAll] so a balance is never skipped.
  Future<int> moveItems(Iterable<String> itemIds, OrderStatus to);

  /// Moves the lagging garments of an order up to the next stage (the swipe
  /// on the rush list, E-11). Returns the order's new stage, or null when it
  /// is already ready or cancelled (hand-over has its own guarded path).
  Future<OrderStatus?> advanceOrder(String orderId);

  /// Hands the whole order over. With [collect] the money is recorded in the
  /// same transaction, so a failure leaves neither half done.
  Future<void> deliverAll(
    String orderId, {
    Money? collect,
    PayMethod method = PayMethod.cash,
    String? paidOn,
    bool dueConfirmed = false,
  });

  /// Edits delivery details with a change-log entry (O-11).
  Future<void> updateDetails(
    String orderId, {
    String? deliveryDate,
    String? trialDate,
    bool clearTrialDate = false,
    bool? urgent,
    String? note,
    String? reason,
  });

  Future<void> cancel(
    String orderId, {
    required String reason,
    required CancelAdvance advance,
    required String today,
  });

  Stream<List<AuditEntry>> watchChangeLog(String orderId);
}
