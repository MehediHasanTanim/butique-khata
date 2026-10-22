import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

import '../support/flow_helpers.dart';
import '../support/test_app.dart';

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

late String panjabiId;
late String shirtId;
late DriftOrderRepository orders;

/// Rahim (with Panjabi v1 measurements) and Karim (no measurements).
Future<void> seed(AppDatabase db) async {
  final now = DateTime(2026, 3, 5);
  final customers = DriftCustomerRepository(db);
  await customers.insert(
    Customer(id: 'c1', name: 'Rahim Uddin', createdAt: now, updatedAt: now),
  );
  await customers.insert(
    Customer(id: 'c2', name: 'Karim Hossain', createdAt: now, updatedAt: now),
  );
  panjabiId = BuiltInTemplates.byKey('panjabi').id;
  shirtId = BuiltInTemplates.byKey('shirt').id;
  await DriftMeasurementRepository(
    db,
    FixedClock(now),
    SequentialIdGenerator('m'),
  ).create(
    NewMeasurement(
      customerId: 'c1',
      garmentTypeId: panjabiId,
      takenOn: '2026-03-01',
      unit: MeasureUnit.inch,
      values: {'length': inches('42'), 'chest': inches('38½')},
    ),
  );
  orders = DriftOrderRepository(
    db,
    FixedClock(now),
    SequentialIdGenerator('o'),
  );
}

Future<OrderDetail> seedOrder(
  AppDatabase db, {
  String customer = 'c1',
  int price = 1200,
  int advance = 0,
  String delivery = '2026-03-20',
  String garment = 'panjabi',
}) {
  return orders.create(
    NewOrder(
      customerId: customer,
      deliveryDate: delivery,
      items: [
        NewOrderItem(
          garmentTypeId: garment == 'panjabi' ? panjabiId : shirtId,
          price: Money.taka(price),
          style: const {'collar': 'band'},
        ),
      ],
      advance: advance == 0
          ? null
          : NewPayment(
              orderId: '',
              amount: Money.taka(advance),
              method: PayMethod.cash,
              paidOn: '2026-03-05',
              kind: PaymentKind.advance,
            ),
    ),
  );
}

void main() {
  late AppDatabase db;

  Future<void> open(
    WidgetTester tester,
    String route, {
    String locale = 'en',
    Future<void> Function()? extra,
  }) async {
    phoneScreen(tester);
    db = memoryDb();
    await tester.runAsync(() async {
      await seed(db);
      await extra?.call();
    });
    await tester.pumpWidget(appOn(db, start: route, locale: locale));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    if (find.text(text).evaluate().isEmpty) {
      // Lazily built list: scroll until it exists.
      await tester.scrollUntilVisible(
        find.text(text),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKeyed(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<T>> query<T>(
    WidgetTester tester,
    Future<List<T>> Function() q,
  ) async => (await tester.runAsync(q))!;

  /// The single order the UI created (ids from the UI are random UUIDs).
  Future<OrderDetail> theOrder(WidgetTester tester) async {
    final rows = await query(tester, () => db.select(db.customerOrder).get());
    return (await tester.runAsync(() => orders.detail(rows.single.id)))!;
  }

  testWidgets('Flow A: returning customer → order with advance in few taps', (
    tester,
  ) async {
    await open(tester, AppRoutes.orders);
    var actions = 0;
    Future<void> act(Future<void> Function() step) async {
      actions++;
      await step();
    }

    // Orders tab → New order → choose Rahim.
    await act(() => tapText(tester, 'New order'));
    await act(() => tapKeyed(tester, 'pick-c1'));
    expect(find.byKey(const ValueKey('step-title')), findsOneWidget);

    // Step 1: add a Panjabi.
    await act(() => tapKeyed(tester, 'add-panjabi'));
    await act(() => tapKeyed(tester, 'wizard-next'));

    // Step 2: the last measurements are pre-selected ("No change").
    expect(find.textContaining('Using version 1'), findsOneWidget);
    expect(find.text('Chest 38½'), findsOneWidget);
    await act(() => tapKeyed(tester, 'wizard-next'));

    // Step 3: style and price.
    await act(() => tapKeyed(tester, 'style-panjabi-collar-band'));
    actions++;
    await tester.enterText(find.byKey(const ValueKey('price-panjabi')), '1200');
    await tester.pump();
    await act(() => tapKeyed(tester, 'wizard-next'));

    // Step 4: advance and save (delivery date defaults to a week out).
    actions++;
    await tester.enterText(find.byKey(const ValueKey('advance')), '500');
    await tester.pump();
    final due = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('summary-due')),
        matching: find.byType(Text),
      ),
    );
    expect(due.data, '৳700');
    await act(() => tapKeyed(tester, 'wizard-next'));

    // Landed on the order.
    expect(find.text('Order #1'), findsOneWidget);
    expect(find.text('Rahim Uddin'), findsOneWidget);
    expect(find.text('Received'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('due')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '৳700',
    );
    // Ten-ish interactions for a returning customer.
    expect(actions, lessThanOrEqualTo(12));

    // Stored exactly: linked to the existing v1, no extra version created.
    final order = await theOrder(tester);
    final sets = await query(tester, () => db.select(db.measurementSet).get());
    expect(sets, hasLength(1));
    expect(order.items.single.measurementSetId, sets.single.id);
    expect(order.items.single.style, {'collar': 'band'});
    expect(order.money.due, const Money.taka(700));
    expect(order.payments.single.kind, PaymentKind.advance);
    await shutDown(tester, db);
  });

  testWidgets(
    'wizard blocks empty orders, missing prices and too-large advance',
    (tester) async {
      await open(tester, AppRoutes.newOrder('c2'));
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Add at least one garment'), findsOneWidget);

      await tapKeyed(tester, 'add-shirt');
      await tapKeyed(tester, 'wizard-next');
      // No measurements for Karim yet: offered, but not required.
      expect(
        find.text('No measurements yet. You can add them later.'),
        findsOneWidget,
      );
      await tapKeyed(tester, 'wizard-next');

      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Enter a price for every garment'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('price-shirt')), '800');
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(find.byKey(const ValueKey('wizard-error')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('advance')), '900');
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Advance is more than the total'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('discount')), '9999');
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Discount is more than the price'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('discount')), 'abc');
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Enter a valid amount'), findsOneWidget);

      expect(
        await query(tester, () => db.select(db.customerOrder).get()),
        isEmpty,
      );

      // Fix the amounts and save: no measurement is linked.
      await tester.enterText(find.byKey(const ValueKey('discount')), '100');
      await tester.enterText(find.byKey(const ValueKey('advance')), '200');
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('summary-total')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '৳700',
      );
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Order #1'), findsOneWidget);
      final order = await theOrder(tester);
      expect(order.items.single.measurementSetId, isNull);
      expect(order.money.due, const Money.taka(500));
      await shutDown(tester, db);
    },
  );

  testWidgets('editing measurements in the wizard links the new version', (
    tester,
  ) async {
    await open(tester, AppRoutes.newOrder('c1'));
    await tapKeyed(tester, 'add-panjabi');
    await tapKeyed(tester, 'wizard-next');
    await tapKeyed(tester, 'edit-panjabi');

    // Entry screen is prefilled; change the first field (Length) to 43.
    expect(find.text('Panjabi / Kurta measurements'), findsOneWidget);
    await typeKeys(tester, '43');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // Back in the wizard using version 2.
    expect(find.textContaining('Using version 2'), findsOneWidget);
    expect(find.text('Length 43'), findsOneWidget);

    // Switching back to "no change" re-selects version 1.
    await tapKeyed(tester, 'keep-panjabi');
    await tapKeyed(tester, 'wizard-next');
    await tester.enterText(find.byKey(const ValueKey('price-panjabi')), '1000');
    await tester.pump();
    await tapKeyed(tester, 'wizard-next');
    await tapKeyed(tester, 'wizard-next');

    final sets = await query(tester, () => db.select(db.measurementSet).get());
    expect(sets, hasLength(2));
    await shutDown(tester, db);
  });

  testWidgets('taking measurements in the wizard for a new customer', (
    tester,
  ) async {
    await open(tester, AppRoutes.newOrder('c2'));
    await tapKeyed(tester, 'add-shirt');
    await tapKeyed(tester, 'wizard-next');
    await tapKeyed(tester, 'take-shirt');
    await typeKeys(tester, '30');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Using version 1'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('order detail: progress an item, collect the due, settle up', (
    tester,
  ) async {
    late OrderDetail created;
    await open(
      tester,
      '/order/o-1',
      extra: () async => created = await seedOrder(db, advance: 500),
    );
    expect(find.text('Order #1'), findsOneWidget);
    expect(find.text('Received'), findsWidgets);

    // Move the item along the pipeline.
    await tapKeyed(tester, 'advance-${created.items.single.id}');
    expect(find.text('Cut'), findsWidgets);
    await tapKeyed(tester, 'advance-${created.items.single.id}');
    expect(find.text('Stitching'), findsWidgets);

    // Jump straight to Ready via the status picker; step back once.
    await tapKeyed(tester, 'status-${created.items.single.id}');
    expect(
      find.byKey(const ValueKey('pick-status-received')),
      findsNothing,
    ); // 2 back
    expect(
      find.byKey(const ValueKey('pick-status-cut')),
      findsOneWidget,
    ); // 1 back
    await tapKeyed(tester, 'pick-status-ready');
    expect(find.text('Ready'), findsWidgets);
    expect(find.textContaining('Move to Delivered'), findsOneWidget);

    // Collect the due: dialog is prefilled with 700.
    await tapText(tester, 'Collect due');
    expect(find.widgetWithText(TextField, '700'), findsOneWidget);
    await tapKeyed(tester, 'payment-save');
    expect(find.text('Paid in full'), findsNothing); // detail shows Due row
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('due')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '৳0',
    );
    expect(find.text('Collect due'), findsNothing);
    expect(find.text('Add payment'), findsOneWidget);

    final order = (await tester.runAsync(() => orders.detail('o-1')))!;
    expect(order.money.isSettled, isTrue);
    expect(order.order.status.name, 'ready');
    expect(order.payments.map((p) => p.kind), [
      PaymentKind.advance,
      PaymentKind.payment,
    ]);
    await shutDown(tester, db);
  });

  testWidgets(
    'payment dialog validates; overpayment shows credit; refund restores due',
    (tester) async {
      await open(
        tester,
        '/order/o-1',
        extra: () async => seedOrder(db, price: 1000, advance: 400),
      );
      await tapText(tester, 'Collect due');
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        'abc',
      );
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await tester.pump();
      expect(find.text('Enter a valid amount'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '700',
      );
      await tapKeyed(tester, 'payment-save');
      expect(find.byKey(const ValueKey('credit')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('credit')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '৳100',
      );

      await tapText(tester, 'Record refund');
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '100',
      );
      await tapKeyed(tester, 'payment-save');
      expect(find.byKey(const ValueKey('credit')), findsNothing);
      final order = (await tester.runAsync(() => orders.detail('o-1')))!;
      expect(order.payments.last.amount, const Money.taka(-100));
      expect(order.money.due, Money.zero);
      await shutDown(tester, db);
    },
  );

  testWidgets('cancel with refund shows Cancelled and removes the due', (
    tester,
  ) async {
    await open(
      tester,
      '/order/o-1',
      extra: () async => seedOrder(db, advance: 400),
    );
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel order');
    await tester.enterText(
      find.byKey(const ValueKey('cancel-reason')),
      'Changed mind',
    );
    expect(find.textContaining('was already paid'), findsOneWidget);
    await tapKeyed(tester, 'cancel-refund');
    await tapKeyed(tester, 'cancel-confirm');

    expect(find.text('Cancelled'), findsWidgets);
    expect(find.text('Changed mind'), findsOneWidget);
    expect(find.text('Collect due'), findsNothing);
    final order = (await tester.runAsync(() => orders.detail('o-1')))!;
    expect(order.order.isCancelled, isTrue);
    expect(order.money.paid, Money.zero);
    await shutDown(tester, db);
  });

  testWidgets('change delivery date and see it in the change log', (
    tester,
  ) async {
    await open(tester, '/order/o-1', extra: () async => seedOrder(db));
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Change delivery');
    await tapKeyed(tester, 'edit-delivery-date');
    // Date picker opens on the current value; pick another day of the month.
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapKeyed(tester, 'edit-delivery-save');
    // The date moved, so the app offers to tell the customer; skip it here.
    expect(find.text('Tell the customer?'), findsNothing);
    expect(find.byKey(const ValueKey('message-text')), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('25'), findsWidgets);
    final order = (await tester.runAsync(() => orders.detail('o-1')))!;
    expect(order.order.deliveryDate, '2026-03-25');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('change-log')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('change-log')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Changed: delivery 2026-03-20 → 2026-03-25'),
      findsOneWidget,
    );
    expect(find.text('Order created'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('the measurements an item was cut from can be reviewed', (
    tester,
  ) async {
    late OrderDetail created;
    await open(
      tester,
      '/order/o-1',
      extra: () async {
        final m = await DriftMeasurementRepository(
          db,
          FixedClock(DateTime(2026, 3, 5)),
          SequentialIdGenerator('x'),
        ).latest('c1', panjabiId);
        created = await orders.create(
          NewOrder(
            customerId: 'c1',
            deliveryDate: '2026-03-20',
            items: [
              NewOrderItem(
                garmentTypeId: panjabiId,
                price: const Money.taka(900),
                measurementSetId: m!.id,
              ),
            ],
          ),
        );
      },
    );
    await tapKeyed(tester, 'snapshot-${created.items.single.id}');
    expect(find.text('Measurements used'), findsWidgets);
    expect(find.text('Version 1 · 1 Mar 2026'), findsOneWidget);
    expect(find.text('38½'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('duplicate order starts from the old one', (tester) async {
    await open(
      tester,
      '/order/o-1',
      extra: () async => seedOrder(db, price: 1350, advance: 100),
    );
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Duplicate order');

    // Garment, qty already there; measurements pre-selected; price copied.
    expect(find.byKey(const ValueKey('qty-panjabi')), findsOneWidget);
    await tapKeyed(tester, 'wizard-next');
    expect(find.textContaining('Using version 1'), findsOneWidget);
    await tapKeyed(tester, 'wizard-next');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('price-panjabi')))
          .initialValue,
      '1350',
    );
    final style = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('style-panjabi-collar-band')),
    );
    expect(style.selected, isTrue);
    await tapKeyed(tester, 'wizard-next');
    // The advance is NOT copied.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('advance')))
          .initialValue,
      '',
    );
    await tapKeyed(tester, 'wizard-next');
    expect(find.text('Order #2'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('orders list, open-only filter and tapping through', (
    tester,
  ) async {
    await open(
      tester,
      AppRoutes.orders,
      extra: () async {
        await seedOrder(db, delivery: '2026-03-25');
        final b = await seedOrder(
          db,
          customer: 'c2',
          delivery: '2026-03-10',
          price: 800,
          advance: 800,
          garment: 'shirt',
        );
        await orders.setAllItemsStatus(b.order.id, OrderStatus.delivered);
      },
    );
    // Delivered order is hidden while "Open only" is on.
    expect(find.text('Rahim Uddin'), findsOneWidget);
    expect(find.text('Karim Hossain'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-open')));
    await tester.pumpAndSettle();
    expect(find.text('Karim Hossain'), findsOneWidget);
    expect(find.text('Paid in full'), findsOneWidget);
    // Soonest delivery first.
    expect(
      tester.getTopLeft(find.text('Karim Hossain')).dy,
      lessThan(tester.getTopLeft(find.text('Rahim Uddin')).dy),
    );
    await tester.tap(find.text('Rahim Uddin'));
    await tester.pumpAndSettle();
    expect(find.text('Order #1'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('dues tab totals what customers owe and sorts by age', (
    tester,
  ) async {
    await open(
      tester,
      AppRoutes.orders,
      extra: () async {
        await seedOrder(db, price: 1200, delivery: '2026-03-25'); // Rahim 1200
        await seedOrder(
          db,
          customer: 'c2',
          price: 300,
          delivery: '2026-03-01',
          garment: 'shirt',
        ); // Karim 300
      },
    );
    await tapText(tester, 'Dues');
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('dues-total')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '৳1,500',
    );
    double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    // By amount (default): Rahim first.
    expect(y('due-c1'), lessThan(y('due-c2')));
    await tapText(tester, 'By age');
    expect(y('due-c2'), lessThan(y('due-c1')));
    await shutDown(tester, db);
  });

  testWidgets('customer profile shows orders, due and starts a new order', (
    tester,
  ) async {
    await open(
      tester,
      AppRoutes.customer('c1'),
      extra: () async {
        await seedOrder(db, price: 1000, advance: 250);
      },
    );
    await tapText(tester, 'Orders');
    expect(find.textContaining('Delivery'), findsOneWidget);
    await tapText(tester, 'Payments');
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('customer-due')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '৳750',
    );
    await tapText(tester, 'Orders');
    await tapKeyed(tester, 'profile-new-order');
    expect(find.byKey(const ValueKey('step-title')), findsOneWidget);
    expect(find.text('Rahim Uddin'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('order screens work in Bangla with Bangla digits', (
    tester,
  ) async {
    await open(
      tester,
      '/order/o-1',
      locale: 'bn',
      extra: () async => seedOrder(db, price: 1200, advance: 500),
    );
    expect(find.text('অর্ডার #১'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('due')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '৳৭০০',
    );
    expect(find.text('গ্রহণ'), findsWidgets);
    expect(tester.takeException(), isNull);
    await shutDown(tester, db);
  });
}
