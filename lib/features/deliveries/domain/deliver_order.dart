import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';

/// How to hand over an order that still has a balance (P-4).
enum DeliverChoice {
  /// Take the balance now, then hand over.
  collectAndDeliver,

  /// Hand over and leave the balance owing.
  deliverWithDue,
}

/// Delivery was not done because money is owed and nobody chose how to
/// proceed. The UI answers with a [DeliverChoice].
class DueOutstandingFailure extends Failure {
  const DueOutstandingFailure(this.due)
    : super('deliver.due_outstanding', 'Balance not settled');

  final Money due;
}

/// Hands an order over to the customer. This is the guarded path for marking
/// things Delivered: with a balance it demands an explicit choice, so a
/// garment never leaves unpaid by accident.
class DeliverOrder {
  DeliverOrder(this._repo);

  final OrderRepository _repo;

  /// Failure codes: `deliver.not_found`, `deliver.cancelled`,
  /// `deliver.due_outstanding` ([DueOutstandingFailure]).
  Future<Result<void>> call(
    String orderId, {
    DeliverChoice? choice,
    PayMethod method = PayMethod.cash,
    required String today,
  }) async {
    final detail = await _repo.detail(orderId);
    if (detail == null) return const Result.err(Failure('deliver.not_found'));
    if (detail.order.isCancelled) {
      return const Result.err(Failure('deliver.cancelled'));
    }
    final due = detail.money.due;
    if (!due.isPositive) {
      await _repo.deliverAll(orderId);
      return const Result.ok(null);
    }
    switch (choice) {
      case null:
        return Result.err(DueOutstandingFailure(due));
      case DeliverChoice.collectAndDeliver:
        await _repo.deliverAll(
          orderId,
          collect: due,
          method: method,
          paidOn: today,
        );
      case DeliverChoice.deliverWithDue:
        await _repo.deliverAll(orderId, dueConfirmed: true);
    }
    return const Result.ok(null);
  }
}
