import 'package:tailor_khata/core/money/money.dart';
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
  });

  /// Customers who owe money on non-cancelled orders.
  Stream<List<CustomerDue>> watchDues();

  /// What one customer owes in total.
  Stream<Money> watchCustomerDue(String customerId);

  Future<Payment> addPayment(NewPayment payment);

  /// Moves one item and rolls the order status up in the same transaction.
  /// Throws [StateError] for a disallowed move.
  Future<void> setItemStatus(String itemId, OrderStatus to);

  /// Moves every item that is allowed to move to [to] (bulk update, O-8).
  Future<void> setAllItemsStatus(String orderId, OrderStatus to);

  /// Edits delivery details with a change-log entry (O-11).
  Future<void> updateDetails(
    String orderId, {
    String? deliveryDate,
    String? trialDate,
    bool clearTrialDate = false,
    bool? urgent,
    String? note,
  });

  Future<void> cancel(
    String orderId, {
    required String reason,
    required CancelAdvance advance,
    required String today,
  });

  Stream<List<AuditEntry>> watchChangeLog(String orderId);
}
