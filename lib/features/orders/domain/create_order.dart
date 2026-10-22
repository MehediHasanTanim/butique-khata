import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';

/// Validates a [NewOrder] and stores it (O-1, O-4, O-5, P-1).
///
/// Failure codes: `order.no_items`, `order.delivery_invalid`,
/// `order.price_negative`, `order.discount_too_big`, `order.advance_invalid`,
/// `order.advance_exceeds_total`.
class CreateOrder {
  CreateOrder(this._repo);

  final OrderRepository _repo;

  Future<Result<OrderDetail>> call(NewOrder input) async {
    final failure = validate(input);
    if (failure != null) return Result.err(failure);
    // A zero advance means "no advance".
    final advance = input.advance;
    final cleaned = (advance != null && advance.amount.isZero)
        ? NewOrder(
            customerId: input.customerId,
            deliveryDate: input.deliveryDate,
            trialDate: input.trialDate,
            items: input.items,
            discount: input.discount,
            urgent: input.urgent,
            note: input.note,
            parentOrderId: input.parentOrderId,
          )
        : input;
    return Result.ok(await _repo.create(cleaned));
  }

  /// Pure validation, also used by the wizard to enable its Save button.
  static Failure? validate(NewOrder input) {
    if (input.items.isEmpty) return const Failure('order.no_items');
    try {
      Clock.parseDate(input.deliveryDate);
      final trial = input.trialDate;
      if (trial != null) Clock.parseDate(trial);
    } on FormatException {
      return const Failure('order.delivery_invalid');
    }
    for (final item in input.items) {
      if (item.price.isNegative || item.qty < 1) {
        return const Failure('order.price_negative');
      }
    }
    final subtotal = Money.sum(input.items.map((i) => i.price));
    if (input.discount.isNegative || input.discount > subtotal) {
      return const Failure('order.discount_too_big');
    }
    final advance = input.advance;
    if (advance != null) {
      if (advance.amount.isNegative) {
        return const Failure('order.advance_invalid');
      }
      if (advance.amount > subtotal - input.discount) {
        return const Failure('order.advance_exceeds_total');
      }
    }
    return null;
  }
}
