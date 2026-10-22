import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/orders/domain/create_order.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

NewOrder order({
  List<int> prices = const [1000],
  int discount = 0,
  int? advance,
  String delivery = '2026-04-01',
  String? trial,
}) => NewOrder(
  customerId: 'c1',
  deliveryDate: delivery,
  trialDate: trial,
  discount: Money.taka(discount),
  items: [
    for (final p in prices)
      NewOrderItem(garmentTypeId: 'g', price: Money.taka(p)),
  ],
  advance: advance == null
      ? null
      : NewPayment(
          orderId: '',
          amount: Money.taka(advance),
          method: PayMethod.cash,
          paidOn: '2026-03-01',
          kind: PaymentKind.advance,
        ),
);

void main() {
  group('Money.tryParse', () {
    final cases = <String, int?>{
      '1250': 125000,
      '1,250.50': 125050,
      '৳ 1250': 125000,
      '১২৫০': 125000,
      '0.5': 50,
      '.5': 50,
      '12.345': null,
      '': null,
      '.': null,
      '-5': null,
      'abc': null,
      '12a': null,
    };
    cases.forEach((input, poisha) {
      test('"$input" → $poisha', () {
        expect(Money.tryParse(input)?.poisha, poisha);
      });
    });
  });

  group('Money.toInputString', () {
    test('plain text that tryParse reads back', () {
      for (final poisha in [0, 5, 100, 135000, 125050, 99999999]) {
        final text = Money(poisha).toInputString();
        expect(text.contains(','), isFalse);
        expect(Money.tryParse(text), Money(poisha), reason: text);
      }
      expect(const Money(135000).toInputString(), '1350');
      expect(const Money(125050).toInputString(), '1250.50');
    });
  });

  group('OrderMoney (S3-02)', () {
    test('due = total - paid, credit when overpaid', () {
      final m = OrderMoney.compute(
        itemPrices: const [Money.taka(1200), Money.taka(800)],
        discount: const Money.taka(100),
        payments: const [Money.taka(500)],
      );
      expect(m.total, const Money.taka(1900));
      expect(m.due, const Money.taka(1400));
      expect(m.hasDue, isTrue);
      expect(m.credit, Money.zero);

      final over = OrderMoney.compute(
        itemPrices: const [Money.taka(100)],
        discount: Money.zero,
        payments: const [Money.taka(150)],
      );
      expect(over.due, const Money.taka(-50));
      expect(over.credit, const Money.taka(50));
      expect(over.hasDue, isFalse);
      expect(over.isSettled, isFalse);
    });

    test('refunds (negative payments) raise the due again', () {
      final m = OrderMoney.compute(
        itemPrices: const [Money.taka(1000)],
        discount: Money.zero,
        payments: const [Money.taka(1000), Money.taka(-300)],
      );
      expect(m.paid, const Money.taka(700));
      expect(m.due, const Money.taka(300));
    });

    test('random sequences: due is always total minus the sum of payments', () {
      final random = Random(11);
      for (var round = 0; round < 500; round++) {
        final prices = List.generate(
          random.nextInt(5) + 1,
          (_) => random.nextInt(500000),
        );
        final discount = random.nextInt(prices.reduce((a, b) => a + b) + 1);
        final payments = List.generate(
          random.nextInt(8),
          (_) => random.nextInt(300000) - 50000,
        );
        final m = OrderMoney.compute(
          itemPrices: prices.map(Money.new),
          discount: Money(discount),
          payments: payments.map(Money.new),
        );
        final expectedTotal = prices.fold(0, (a, b) => a + b) - discount;
        final expectedPaid = payments.fold(0, (a, b) => a + b);
        expect(m.total.poisha, expectedTotal);
        expect(m.paid.poisha, expectedPaid);
        expect(m.due.poisha, expectedTotal - expectedPaid);
        // Settling the exact due always clears it.
        final settled = OrderMoney(total: m.total, paid: m.paid + m.due);
        expect(settled.isSettled, isTrue);
      }
    });
  });

  group('OrderStatus', () {
    test('forward any distance and one step back are allowed', () {
      expect(OrderStatus.received.canMoveTo(OrderStatus.ready), isTrue);
      expect(OrderStatus.cut.canMoveTo(OrderStatus.stitching), isTrue);
      expect(OrderStatus.stitching.canMoveTo(OrderStatus.cut), isTrue);
      expect(OrderStatus.stitching.canMoveTo(OrderStatus.received), isFalse);
      expect(OrderStatus.cut.canMoveTo(OrderStatus.cut), isFalse);
      expect(OrderStatus.received.canMoveTo(OrderStatus.received), isFalse);
    });

    test('next walks the pipeline and ends at delivered', () {
      var s = OrderStatus.received;
      final walked = <OrderStatus>[s];
      while (s.next != null) {
        s = s.next!;
        walked.add(s);
      }
      expect(walked, OrderStatus.values);
    });

    test('roll-up is the slowest item; delivered only when all are', () {
      expect(OrderStatus.rollUp(const []), OrderStatus.received);
      expect(
        OrderStatus.rollUp([OrderStatus.ready, OrderStatus.cut]),
        OrderStatus.cut,
      );
      expect(
        OrderStatus.rollUp([OrderStatus.delivered, OrderStatus.ready]),
        OrderStatus.ready,
      );
      expect(
        OrderStatus.rollUp([OrderStatus.delivered, OrderStatus.delivered]),
        OrderStatus.delivered,
      );
    });
  });

  group('CreateOrder.validate', () {
    test('a good order passes', () {
      expect(CreateOrder.validate(order(advance: 300)), isNull);
    });

    test('rejects empty orders and bad dates', () {
      expect(CreateOrder.validate(order(prices: [])), isA<Object>());
      expect(CreateOrder.validate(order(prices: []))?.code, 'order.no_items');
      expect(
        CreateOrder.validate(order(delivery: '1/4/2026'))?.code,
        'order.delivery_invalid',
      );
      expect(
        CreateOrder.validate(order(trial: 'soon'))?.code,
        'order.delivery_invalid',
      );
    });

    test('rejects a discount above the subtotal', () {
      expect(CreateOrder.validate(order(discount: 1000)), isNull);
      expect(
        CreateOrder.validate(order(discount: 1001))?.code,
        'order.discount_too_big',
      );
    });

    test('advance may equal but not exceed the payable total', () {
      expect(CreateOrder.validate(order(advance: 1000)), isNull);
      expect(
        CreateOrder.validate(order(advance: 1001))?.code,
        'order.advance_exceeds_total',
      );
      expect(
        CreateOrder.validate(order(discount: 200, advance: 801))?.code,
        'order.advance_exceeds_total',
      );
    });
  });
}
