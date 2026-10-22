import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/create_order.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

import '../../support/db_fixtures.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftOrderRepository repo;
  late CreateOrder create;
  late FixedClock clock;
  late String panjabi;
  late String shirt;

  setUp(() async {
    db = memoryDb();
    clock = FixedClock(DateTime(2026, 3, 1, 10));
    repo = DriftOrderRepository(db, clock, SequentialIdGenerator('o'));
    create = CreateOrder(repo);
    final customers = DriftCustomerRepository(db);
    final now = clock.now();
    for (final (id, name) in [('c1', 'Rahim Uddin'), ('c2', 'Karim Hossain')]) {
      await customers.insert(
        Customer(id: id, name: name, createdAt: now, updatedAt: now),
      );
    }
    panjabi = BuiltInTemplates.byKey('panjabi').id;
    shirt = BuiltInTemplates.byKey('shirt').id;
  });
  tearDown(() => db.close());

  NewOrder newOrder({
    String customer = 'c1',
    List<(String, int)>? items,
    int? advance,
    String delivery = '2026-04-01',
    int discount = 0,
  }) => NewOrder(
    customerId: customer,
    deliveryDate: delivery,
    discount: Money.taka(discount),
    items: [
      for (final (garment, price) in items ?? [(panjabi, 1200)])
        NewOrderItem(garmentTypeId: garment, price: Money.taka(price)),
    ],
    advance: advance == null
        ? null
        : NewPayment(
            orderId: '',
            amount: Money.taka(advance),
            method: PayMethod.bkash,
            paidOn: '2026-03-01',
            kind: PaymentKind.advance,
          ),
  );

  Future<OrderDetail> make([NewOrder? input]) async =>
      (await create(input ?? newOrder())).valueOrNull!;

  group('create (S3-03)', () {
    test(
      'stores order, items and advance in one go with money right',
      () async {
        final detail = await make(
          newOrder(
            items: [(panjabi, 1200), (shirt, 800)],
            advance: 500,
            discount: 100,
          ),
        );
        expect(detail.order.number, 1);
        expect(detail.order.status, OrderStatus.received);
        expect(detail.customerName, 'Rahim Uddin');
        expect(detail.items, hasLength(2));
        expect(
          detail.items.every((i) => i.status == OrderStatus.received),
          isTrue,
        );
        expect(detail.payments.single.kind, PaymentKind.advance);
        expect(detail.payments.single.method, PayMethod.bkash);
        expect(detail.money.total, const Money.taka(1900));
        expect(detail.money.paid, const Money.taka(500));
        expect(detail.money.due, const Money.taka(1400));
      },
    );

    test('invalid orders are rejected and nothing is stored', () async {
      final result = await create(newOrder(advance: 5000));
      expect(result.failureOrNull?.code, 'order.advance_exceeds_total');
      expect(await db.select(db.customerOrder).get(), isEmpty);
      expect(await db.select(db.orderItem).get(), isEmpty);
    });

    test('a zero advance means no payment row', () async {
      final detail = await make(newOrder(advance: 0));
      expect(detail.payments, isEmpty);
      expect(detail.money.due, const Money.taka(1200));
    });

    test('slip numbers are sequential and never shared', () async {
      final numbers = <int>[];
      for (var i = 0; i < 5; i++) {
        numbers.add((await make()).order.number);
      }
      expect(numbers, [1, 2, 3, 4, 5]);
    });

    test('concurrent creates get distinct numbers', () async {
      final all = await Future.wait([for (var i = 0; i < 8; i++) make()]);
      expect(all.map((d) => d.order.number).toSet(), hasLength(8));
    });

    test('quantity scales work units; style and fabric round-trip', () async {
      final detail = await make(
        NewOrder(
          customerId: 'c1',
          deliveryDate: '2026-04-01',
          items: [
            NewOrderItem(
              garmentTypeId: panjabi,
              price: const Money.taka(3000),
              qty: 3,
              fabricSource: FabricSource.customer,
              colour: 'Maroon',
              style: const {'collar': 'band', 'pocket': 'side'},
              note: 'extra loose',
            ),
          ],
        ),
      );
      final item = detail.items.single;
      expect(item.qty, 3);
      expect(item.workUnits, 300);
      expect(item.fabricSource, FabricSource.customer);
      expect(item.style, {'collar': 'band', 'pocket': 'side'});
      expect(item.colour, 'Maroon');
    });

    test('unknown customer is rejected by the foreign key', () async {
      await expectLater(
        create(newOrder(customer: 'nobody')),
        throwsA(anything),
      );
    });
  });

  group('payments (S3-09)', () {
    test('later payments reduce the due; refunds add it back', () async {
      final d = await make(newOrder(advance: 200));
      await repo.addPayment(
        NewPayment(
          orderId: d.order.id,
          amount: const Money.taka(400),
          method: PayMethod.cash,
          paidOn: '2026-03-05',
        ),
      );
      var now = (await repo.detail(d.order.id))!;
      expect(now.money.due, const Money.taka(600));
      await repo.addPayment(
        NewPayment(
          orderId: d.order.id,
          amount: const Money.taka(-100),
          method: PayMethod.cash,
          paidOn: '2026-03-06',
          kind: PaymentKind.refund,
        ),
      );
      now = (await repo.detail(d.order.id))!;
      expect(now.money.due, const Money.taka(700));
      expect(now.payments.map((p) => p.kind), [
        PaymentKind.advance,
        PaymentKind.payment,
        PaymentKind.refund,
      ]);
    });

    test('overpaying shows credit; zero payments are rejected', () async {
      final d = await make();
      await repo.addPayment(
        NewPayment(
          orderId: d.order.id,
          amount: const Money.taka(1500),
          method: PayMethod.nagad,
          paidOn: '2026-03-05',
        ),
      );
      final now = (await repo.detail(d.order.id))!;
      expect(now.money.credit, const Money.taka(300));
      await expectLater(
        repo.addPayment(
          NewPayment(
            orderId: d.order.id,
            amount: Money.zero,
            method: PayMethod.cash,
            paidOn: '2026-03-05',
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'payments cannot be edited or deleted (corrections are new rows)',
      () async {
        final d = await make(newOrder(advance: 200));
        await expectLater(
          db.customStatement('UPDATE payment SET amount = 1'),
          throwsA(predicate((e) => e.toString().contains('immutable'))),
        );
        await expectLater(
          db.customStatement('DELETE FROM payment'),
          throwsA(predicate((e) => e.toString().contains('immutable'))),
        );
        expect(
          (await repo.detail(d.order.id))!.money.paid,
          const Money.taka(200),
        );
      },
    );
  });

  group('status pipeline (S3-08)', () {
    test('moving the slowest item moves the order; roll-up follows', () async {
      final d = await make(newOrder(items: [(panjabi, 1000), (shirt, 500)]));
      final [a, b] = d.items;
      await repo.setItemStatus(a.id, OrderStatus.ready);
      expect(
        (await repo.detail(d.order.id))!.order.status,
        OrderStatus.received,
      );
      await repo.setItemStatus(b.id, OrderStatus.cut);
      expect((await repo.detail(d.order.id))!.order.status, OrderStatus.cut);
      await repo.setItemStatus(b.id, OrderStatus.delivered, dueConfirmed: true);
      expect((await repo.detail(d.order.id))!.order.status, OrderStatus.ready);
      await repo.setItemStatus(a.id, OrderStatus.delivered, dueConfirmed: true);
      expect(
        (await repo.detail(d.order.id))!.order.status,
        OrderStatus.delivered,
      );
    });

    test('one step back works; bigger steps back are refused', () async {
      final d = await make();
      final item = d.items.single;
      await repo.setItemStatus(item.id, OrderStatus.stitching);
      await repo.setItemStatus(item.id, OrderStatus.cut);
      expect((await repo.detail(d.order.id))!.order.status, OrderStatus.cut);
      await repo.setItemStatus(item.id, OrderStatus.received); // one step back
      expect(
        (await repo.detail(d.order.id))!.order.status,
        OrderStatus.received,
      );

      await repo.setItemStatus(item.id, OrderStatus.stitching);
      await expectLater(
        repo.setItemStatus(item.id, OrderStatus.received), // two steps back
        throwsStateError,
      );
      await expectLater(
        repo.setItemStatus(item.id, OrderStatus.stitching), // no move
        throwsStateError,
      );
    });

    test('bulk update moves every item that can move', () async {
      final d = await make(
        newOrder(items: [(panjabi, 1), (shirt, 1), (panjabi, 1)]),
      );
      await repo.setItemStatus(d.items[0].id, OrderStatus.finishing);
      await repo.setAllItemsStatus(d.order.id, OrderStatus.ready);
      final after = (await repo.detail(d.order.id))!;
      expect(after.items.map((i) => i.status), everyElement(OrderStatus.ready));
      expect(after.order.status, OrderStatus.ready);
      // Moving everything back one step only affects items exactly one ahead.
      await repo.setAllItemsStatus(d.order.id, OrderStatus.finishing);
      expect(
        (await repo.detail(d.order.id))!.items.map((i) => i.status),
        everyElement(OrderStatus.finishing),
      );
    });

    test('status changes are timestamped and logged', () async {
      final d = await make();
      clock.advance(const Duration(hours: 2));
      await repo.setItemStatus(d.items.single.id, OrderStatus.cut);
      final item = (await repo.detail(d.order.id))!.items.single;
      expect(item.statusChangedAt, DateTime(2026, 3, 1, 12));
      final log = await repo.watchChangeLog(d.order.id).first;
      expect(log.map((e) => e.action), ['item_status', 'created']);
      expect(log.first.detail, 'received → cut');
    });
  });

  group('cancel (S3-11)', () {
    test(
      'refund option records a negative payment and removes the due',
      () async {
        final d = await make(newOrder(advance: 400));
        await repo.cancel(
          d.order.id,
          reason: 'Changed mind',
          advance: CancelAdvance.refund,
          today: '2026-03-03',
        );
        final after = (await repo.detail(d.order.id))!;
        expect(after.order.isCancelled, isTrue);
        expect(after.order.cancelReason, 'Changed mind');
        expect(after.money.paid, Money.zero);
        expect(after.payments.last.kind, PaymentKind.refund);
        expect(after.payments.last.amount, const Money.taka(-400));
        expect(await repo.watchDues().first, isEmpty);
      },
    );

    test('keep option leaves payments alone', () async {
      final d = await make(newOrder(advance: 400));
      await repo.cancel(
        d.order.id,
        reason: 'No show',
        advance: CancelAdvance.keep,
        today: '2026-03-03',
      );
      final after = (await repo.detail(d.order.id))!;
      expect(after.payments, hasLength(1));
      expect(after.money.paid, const Money.taka(400));
      expect(await repo.watchDues().first, isEmpty);
    });

    test(
      'a cancelled order cannot change status or be cancelled twice',
      () async {
        final d = await make();
        await repo.cancel(
          d.order.id,
          reason: 'x',
          advance: CancelAdvance.keep,
          today: '2026-03-03',
        );
        await expectLater(
          repo.setItemStatus(d.items.single.id, OrderStatus.cut),
          throwsStateError,
        );
        await expectLater(
          repo.cancel(
            d.order.id,
            reason: 'y',
            advance: CancelAdvance.keep,
            today: '2026-03-03',
          ),
          throwsStateError,
        );
      },
    );
  });

  group('edit details with change log (O-11)', () {
    test('changes are applied and each is logged', () async {
      final d = await make();
      await repo.updateDetails(
        d.order.id,
        deliveryDate: '2026-04-10',
        urgent: true,
        note: 'Eid rush',
      );
      final after = (await repo.detail(d.order.id))!;
      expect(after.order.deliveryDate, '2026-04-10');
      expect(after.order.urgent, isTrue);
      expect(after.order.note, 'Eid rush');
      final log = await repo.watchChangeLog(d.order.id).first;
      expect(log.first.action, 'details_changed');
      expect(log.first.detail, contains('2026-04-01 → 2026-04-10'));
    });

    test('no change writes no log entry; trial date can be cleared', () async {
      final d = await make();
      await repo.updateDetails(d.order.id, deliveryDate: '2026-04-01');
      expect((await repo.watchChangeLog(d.order.id).first).length, 1);
      await repo.updateDetails(d.order.id, trialDate: '2026-03-20');
      expect((await repo.detail(d.order.id))!.order.trialDate, '2026-03-20');
      await repo.updateDetails(d.order.id, clearTrialDate: true);
      expect((await repo.detail(d.order.id))!.order.trialDate, isNull);
    });
  });

  group('lists and dues (S3-10)', () {
    test('summaries are sorted by delivery date and carry money', () async {
      await make(newOrder(delivery: '2026-05-01', advance: 100));
      await make(newOrder(delivery: '2026-04-01', customer: 'c2'));
      final list = await repo.watchSummaries().first;
      expect(list.map((s) => s.order.deliveryDate), [
        '2026-04-01',
        '2026-05-01',
      ]);
      expect(list.first.customerName, 'Karim Hossain');
      expect(list.last.money.due, const Money.taka(1100));
      expect(list.last.itemCount, 1);
    });

    test('filters by customer and open-only', () async {
      final a = await make();
      await make(newOrder(customer: 'c2'));
      final c1 = await repo.watchSummaries(customerId: 'c1').first;
      expect(c1.single.order.id, a.order.id);

      await repo.setAllItemsStatus(
        a.order.id,
        OrderStatus.delivered,
        dueConfirmed: true,
      );
      expect(await repo.watchSummaries(openOnly: true).first, hasLength(1));
      expect(await repo.watchSummaries().first, hasLength(2));
    });

    test(
      'dues list sums per customer, biggest first, ignores settled',
      () async {
        final a = await make(newOrder(delivery: '2026-04-01')); // c1: 1200
        await make(
          newOrder(delivery: '2026-03-20', items: [(shirt, 800)]),
        ); // c1: 800
        final settled = await make(newOrder(customer: 'c2', advance: 1200));
        await make(newOrder(customer: 'c2', items: [(panjabi, 300)]));
        expect(settled.money.due, Money.zero);

        final dues = await repo.watchDues().first;
        expect(dues.map((d) => d.customerName), [
          'Rahim Uddin',
          'Karim Hossain',
        ]);
        expect(dues.first.due, const Money.taka(2000));
        expect(dues.first.orderCount, 2);
        expect(dues.first.oldestDeliveryDate, '2026-03-20');
        expect(dues.last.due, const Money.taka(300));

        await repo.addPayment(
          NewPayment(
            orderId: a.order.id,
            amount: const Money.taka(1200),
            method: PayMethod.cash,
            paidOn: '2026-03-02',
          ),
        );
        expect((await repo.watchDues().first).first.due, const Money.taka(800));
      },
    );

    test('customer due ignores credit on another order', () async {
      final a = await make(newOrder(items: [(panjabi, 500)]));
      await repo.addPayment(
        NewPayment(
          orderId: a.order.id,
          amount: const Money.taka(900),
          method: PayMethod.cash,
          paidOn: '2026-03-02',
        ),
      );
      await make(newOrder(items: [(panjabi, 300)]));
      expect(await repo.watchCustomerDue('c1').first, const Money.taka(300));
      expect(await repo.watchCustomerDue('c2').first, Money.zero);
    });

    test('streams update live when a payment arrives', () async {
      final d = await make();
      final seen = <int>[];
      final sub = repo.watchDues().listen((l) => seen.add(l.length));
      await pumpEventQueue();
      await repo.addPayment(
        NewPayment(
          orderId: d.order.id,
          amount: const Money.taka(1200),
          method: PayMethod.cash,
          paidOn: '2026-03-02',
        ),
      );
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [1, 0]);
    });
  });

  test('migration v2 → v3 keeps data and adds the order tables', () async {
    final dir = Directory.systemTemp.createTempSync('tk_mig3');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v1.db');
    DbFixtures.writeV1File(file);
    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);

    expect(
      (await upgraded.select(upgraded.appSetting).get()).single.value,
      'bn',
    );
    final names =
        (await upgraded
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type IN ('table','view','trigger')",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      names,
      containsAll([
        'customer_order',
        'order_item',
        'payment',
        'worker',
        'v_order_money',
        'trg_payment_no_update',
        'trg_payment_no_delete',
      ]),
    );
    final v = await upgraded.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  });
}
