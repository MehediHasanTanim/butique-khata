import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/deliveries/domain/message_composer.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

OrderDetail detail({int paid = 500, int price = 1200}) {
  final now = DateTime(2026, 3, 5);
  return OrderDetail(
    order: Order(
      id: 'o1',
      number: 12,
      customerId: 'c1',
      deliveryDate: '2026-03-20',
      discount: Money.zero,
      urgent: false,
      status: OrderStatus.ready,
      createdAt: now,
      updatedAt: now,
    ),
    customerName: 'Rahim Uddin',
    items: [
      OrderItem(
        id: 'i1',
        orderId: 'o1',
        garmentTypeId: 'g',
        qty: 1,
        price: Money.taka(price),
        status: OrderStatus.ready,
        statusChangedAt: now,
      ),
    ],
    payments: [
      if (paid > 0)
        Payment(
          id: 'p1',
          orderId: 'o1',
          amount: Money.taka(paid),
          kind: PaymentKind.advance,
          method: PayMethod.cash,
          paidOn: '2026-03-05',
          createdAt: now,
        ),
    ],
  );
}

void main() {
  setUpAll(() => initializeDateFormatting());
  String compose(
    MessageKind kind,
    OrderDetail d, {
    String lang = 'en',
    String? newDate,
  }) => composeMessage(
    template: MessageTemplates.defaultFor(kind, lang),
    detail: d,
    garments: const ['Panjabi', 'Shirt'],
    shop: 'Noor Tailors',
    languageCode: lang,
    newDate: newDate,
  );

  test('ready message mentions the balance when there is one', () {
    final text = compose(MessageKind.ready, detail());
    expect(text, contains('Rahim Uddin'));
    expect(text, contains('Panjabi, Shirt'));
    expect(text, contains('order #12'));
    expect(text, contains('Balance due: ৳700.'));
    expect(text, endsWith('Noor Tailors'));
    expect(text.contains('{'), isFalse);
  });

  test('a settled order has no balance sentence', () {
    final text = compose(MessageKind.ready, detail(paid: 1200));
    expect(text, isNot(contains('Balance')));
    expect(text.contains('  '), isFalse);
  });

  test('moved message uses the new date', () {
    final text = compose(MessageKind.moved, detail(), newDate: '2026-04-02');
    expect(text, contains('2 Apr 2026'));
    expect(text, isNot(contains('20 Mar')));
  });

  test('Bangla messages use Bangla digits', () {
    final text = compose(MessageKind.ready, detail(), lang: 'bn');
    expect(text, contains('অর্ডার #১২'));
    expect(text, contains('৳৭০০'));
    expect(text, contains('Rahim Uddin'));
  });

  test('an edited template is honoured', () {
    final text = composeMessage(
      template: 'Hi {name}: #{order} owes {due} ({shop})',
      detail: detail(),
      garments: const ['Panjabi'],
      shop: 'S',
      languageCode: 'en',
    );
    expect(text, 'Hi Rahim Uddin: #12 owes Balance due: ৳700. (S)');
  });
}
