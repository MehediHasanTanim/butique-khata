import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftOrderRepository repo;
  late FixedClock clock;
  late String panjabi;
  late String shirt;

  setUp(() async {
    db = memoryDb();
    clock = FixedClock(DateTime(2026, 3, 10, 9));
    repo = DriftOrderRepository(db, clock, SequentialIdGenerator('o'));
    final customers = DriftCustomerRepository(db);
    final now = clock.now();
    for (final (id, name, phone) in [
      ('c1', 'Rahim Uddin', '+8801712345678'),
      ('c2', 'Karim Hossain', '+8801898765432'),
    ]) {
      await customers.insert(
        Customer(
          id: id,
          name: name,
          phone: phone,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    panjabi = BuiltInTemplates.byKey('panjabi').id;
    shirt = BuiltInTemplates.byKey('shirt').id;
  });
  tearDown(() => db.close());

  Future<OrderDetail> make({
    String customer = 'c1',
    String delivery = '2026-03-10',
    int price = 1000,
    int advance = 0,
    String garment = 'panjabi',
    List<StoredImage> photos = const [],
  }) => repo.create(
    NewOrder(
      customerId: customer,
      deliveryDate: delivery,
      items: [
        NewOrderItem(
          garmentTypeId: garment == 'panjabi' ? panjabi : shirt,
          price: Money.taka(price),
          photos: photos,
        ),
      ],
      advance: advance == 0
          ? null
          : NewPayment(
              orderId: '',
              amount: Money.taka(advance),
              method: PayMethod.cash,
              paidOn: '2026-03-01',
              kind: PaymentKind.advance,
            ),
    ),
  );

  group('deliver guard (S4-03 / P-4)', () {
    test('delivering with a balance is refused unless confirmed', () async {
      final d = await make(advance: 400);
      await expectLater(
        repo.setItemStatus(d.items.single.id, OrderStatus.delivered),
        throwsA(
          isA<DueOutstandingError>().having(
            (e) => e.due,
            'due',
            const Money.taka(600),
          ),
        ),
      );
      await expectLater(
        repo.setAllItemsStatus(d.order.id, OrderStatus.delivered),
        throwsA(isA<DueOutstandingError>()),
      );
      await expectLater(
        repo.deliverAll(d.order.id),
        throwsA(isA<DueOutstandingError>()),
      );
      final after = (await repo.detail(d.order.id))!;
      expect(after.order.status, OrderStatus.received);
      expect(after.items.single.status, OrderStatus.received);
    });

    test('a paid order delivers without a prompt', () async {
      final d = await make(advance: 1000);
      await repo.deliverAll(d.order.id);
      expect(
        (await repo.detail(d.order.id))!.order.status,
        OrderStatus.delivered,
      );
    });

    test('deliver with the due confirmed leaves the balance', () async {
      final d = await make(advance: 400);
      await repo.deliverAll(d.order.id, dueConfirmed: true);
      final after = (await repo.detail(d.order.id))!;
      expect(after.order.status, OrderStatus.delivered);
      expect(after.money.due, const Money.taka(600));
    });

    test(
      'collect and deliver records the money and delivers atomically',
      () async {
        final d = await make(advance: 400);
        await repo.deliverAll(
          d.order.id,
          collect: const Money.taka(600),
          method: PayMethod.bkash,
          paidOn: '2026-03-10',
        );
        final after = (await repo.detail(d.order.id))!;
        expect(after.order.status, OrderStatus.delivered);
        expect(after.money.isSettled, isTrue);
        expect(after.payments.last.method, PayMethod.bkash);
        expect(after.payments.last.amount, const Money.taka(600));
      },
    );

    test('collecting too little still fails and records nothing', () async {
      final d = await make(advance: 400);
      await expectLater(
        repo.deliverAll(d.order.id, collect: const Money.taka(100)),
        throwsA(isA<DueOutstandingError>()),
      );
      final after = (await repo.detail(d.order.id))!;
      expect(after.payments, hasLength(1), reason: 'rolled back');
      expect(after.order.status, OrderStatus.received);
    });

    test('it applies per item too, and not to other moves', () async {
      final d = await make();
      await repo.setItemStatus(d.items.single.id, OrderStatus.ready);
      await expectLater(
        repo.setItemStatus(d.items.single.id, OrderStatus.delivered),
        throwsA(isA<DueOutstandingError>()),
      );
      await repo.setItemStatus(
        d.items.single.id,
        OrderStatus.delivered,
        dueConfirmed: true,
      );
    });
  });

  group('delivery buckets', () {
    test('boundaries are computed from today', () {
      final b = DeliveryBuckets.of('2026-03-30');
      expect(b.tomorrow, '2026-03-31');
      expect(b.weekStart, '2026-04-01');
      expect(b.weekEnd, '2026-04-06');
    });
  });

  group('deliveries (S4-02)', () {
    final buckets = DeliveryBuckets.of('2026-03-10');

    test('counts per bucket ignore delivered and cancelled orders', () async {
      await make(delivery: '2026-03-05'); // overdue
      await make(delivery: '2026-03-09'); // overdue
      await make(delivery: '2026-03-10'); // today
      await make(delivery: '2026-03-10', customer: 'c2'); // today
      await make(delivery: '2026-03-11'); // tomorrow
      await make(delivery: '2026-03-12'); // week
      await make(delivery: '2026-03-17'); // week (day 7)
      await make(delivery: '2026-03-18'); // later: no bucket
      final cancelled = await make(delivery: '2026-03-10');
      await repo.cancel(
        cancelled.order.id,
        reason: 'x',
        advance: CancelAdvance.keep,
        today: '2026-03-10',
      );
      final done = await make(delivery: '2026-03-10', advance: 1000);
      await repo.deliverAll(done.order.id);

      final counts = await repo
          .watchDeliveryCounts(buckets: buckets, uncollectedBeforeMillis: 0)
          .first;
      expect(counts.overdue, 2);
      expect(counts.today, 2);
      expect(counts.tomorrow, 1);
      expect(counts.week, 2);
      expect(counts.uncollected, 0);
    });

    test('keyset paging walks every order once, in order', () async {
      for (var i = 0; i < 12; i++) {
        await make(
          delivery: '2026-03-${(10 + i % 4).toString().padLeft(2, '0')}',
        );
      }
      final seen = <int>[];
      DeliveryCursor? cursor;
      var pages = 0;
      while (true) {
        final page = await repo.deliveriesPage(after: cursor, limit: 5);
        if (page.isEmpty) break;
        pages++;
        seen.addAll(page.map((s) => s.order.number));
        final last = page.last.order;
        cursor = DeliveryCursor(last.deliveryDate, last.number);
        if (pages > 10) fail('paging does not terminate');
      }
      expect(pages, 3);
      expect(seen.toSet(), hasLength(12));
      // Sorted by delivery date then number.
      final all = await repo.deliveriesPage(limit: 100);
      expect(
        all.map((s) => (s.order.deliveryDate, s.order.number)).toList(),
        [for (final s in all) (s.order.deliveryDate, s.order.number)]
          ..sort((a, b) {
            final byDate = a.$1.compareTo(b.$1);
            return byDate != 0 ? byDate : a.$2.compareTo(b.$2);
          }),
      );
      expect(seen, all.map((s) => s.order.number).toList());
    });

    test('range limits what a page returns', () async {
      await make(delivery: '2026-03-09');
      await make(delivery: '2026-03-10');
      await make(delivery: '2026-03-11');
      final today = await repo.deliveriesPage(
        from: '2026-03-10',
        to: '2026-03-10',
      );
      expect(today.single.order.deliveryDate, '2026-03-10');
      final overdue = await repo.deliveriesPage(to: '2026-03-09');
      expect(overdue.single.order.deliveryDate, '2026-03-09');
      expect(today.single.customerName, 'Rahim Uddin');
    });

    test('paging 5,000 orders stays fast', () async {
      await db.transaction(() async {
        for (var i = 0; i < 5000; i++) {
          await db.customStatement(
            'INSERT INTO customer_order (id, number, customer_id, delivery_date, '
            "discount, urgent, status, created_at, updated_at) VALUES ('b$i', ${i + 1000}, 'c1', "
            "'2026-04-${(i % 28 + 1).toString().padLeft(2, '0')}', 0, 0, 'received', 1, 1)",
          );
        }
      });
      final watch = Stopwatch()..start();
      const cursor = DeliveryCursor('2026-04-14', 3000);
      final page = await repo.deliveriesPage(after: cursor, limit: 30);
      watch.stop();
      expect(page, hasLength(30));
      expect(
        page.first.order.deliveryDate.compareTo('2026-04-14') >= 0,
        isTrue,
      );
      expect(watch.elapsedMilliseconds, lessThan(150));
    });

    test('uncollected: ready for N days and still here', () async {
      final a = await make(advance: 1000);
      final b = await make(advance: 1000, customer: 'c2');
      await repo.setAllItemsStatus(a.order.id, OrderStatus.ready);
      clock.advance(const Duration(days: 5));
      await repo.setAllItemsStatus(b.order.id, OrderStatus.ready);

      final threshold = clock.now().subtract(const Duration(days: 3));
      final list = await repo.uncollected(
        olderThanMillis: threshold.millisecondsSinceEpoch,
      );
      expect(list.map((s) => s.order.id), [a.order.id]);

      final counts = await repo
          .watchDeliveryCounts(
            buckets: buckets,
            uncollectedBeforeMillis: threshold.millisecondsSinceEpoch,
          )
          .first;
      expect(counts.uncollected, 1);

      // Handing it over removes it.
      await repo.deliverAll(a.order.id);
      expect(
        await repo.uncollected(
          olderThanMillis: threshold.millisecondsSinceEpoch,
        ),
        isEmpty,
      );
    });

    test('open delivery days feed reminders', () async {
      final first = await make(delivery: '2026-03-12');
      await make(delivery: '2026-03-12', customer: 'c2');
      await make(delivery: '2026-03-15');
      final delivered = await make(delivery: '2026-03-13', advance: 1000);
      await repo.deliverAll(delivered.order.id);

      final days = await repo.watchOpenDeliveryDays().first;
      expect(days.map((d) => (d.date, d.count)), [
        ('2026-03-12', 2),
        ('2026-03-15', 1),
      ]);
      expect(
        days.first.firstOrderId,
        first.order.id.compareTo('') == 0 ? '' : isNotEmpty,
      );
    });
  });

  group('dashboard (S4-07)', () {
    test('counts what matters today', () async {
      await make(delivery: '2026-03-08', price: 500); // overdue, due 500
      await make(
        delivery: '2026-03-10',
        price: 1000,
        advance: 400,
      ); // today, due 600
      await make(
        delivery: '2026-03-20',
        price: 300,
        advance: 300,
      ); // later, settled
      final startOfToday = DateTime(2026, 3, 10).millisecondsSinceEpoch;
      final stats = await repo
          .watchDashboard(today: '2026-03-10', startOfTodayMillis: startOfToday)
          .first;
      expect(stats.dueToday, 1);
      expect(stats.overdue, 1);
      expect(stats.totalDue, const Money.taka(1100));
      expect(stats.receivedToday, 3);
    });

    test('empty shop gives zeros', () async {
      final stats = await repo
          .watchDashboard(today: '2026-03-10', startOfTodayMillis: 0)
          .first;
      expect(stats, const DashboardStats());
    });

    test('updates live when an order arrives', () async {
      final seen = <int>[];
      final sub = repo
          .watchDashboard(today: '2026-03-10', startOfTodayMillis: 0)
          .listen((s) => seen.add(s.dueToday));
      await pumpEventQueue();
      await make(delivery: '2026-03-10');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [0, 1]);
    });
  });

  group('filters (S4-09)', () {
    Future<List<int>> numbers(OrderFilter f) async =>
        (await repo.watchSummaries(filter: f).first)
            .map((s) => s.order.number)
            .toList();

    setUp(() async {
      await make(
        delivery: '2026-03-05',
        price: 1000,
        advance: 1000,
      ); // #1 Rahim paid
      await make(
        delivery: '2026-03-10',
        customer: 'c2',
        garment: 'shirt',
      ); // #2 Karim due
      await make(delivery: '2026-03-20', price: 500); // #3 Rahim due
    });

    test('by order number, customer name or phone digits', () async {
      expect(await numbers(const OrderFilter(query: '2')), contains(2));
      expect(await numbers(const OrderFilter(query: '#2')), [2]);
      expect(await numbers(const OrderFilter(query: 'karim')), [2]);
      expect(await numbers(const OrderFilter(query: 'rahim')), [1, 3]);
      expect(await numbers(const OrderFilter(query: '1712345')), [1, 3]);
      expect(await numbers(const OrderFilter(query: '01898')), [2]);
      expect(await numbers(const OrderFilter(query: 'nobody')), isEmpty);
    });

    test('by status, due only, garment and delivery range', () async {
      final a = (await repo.watchSummaries().first).first;
      await repo.setItemStatus(
        (await repo.detail(a.order.id))!.items.single.id,
        OrderStatus.cut,
      );
      expect(await numbers(const OrderFilter(statuses: {OrderStatus.cut})), [
        1,
      ]);
      expect(
        await numbers(
          const OrderFilter(statuses: {OrderStatus.cut, OrderStatus.received}),
        ),
        [1, 2, 3],
      );
      expect(await numbers(const OrderFilter(dueOnly: true)), [2, 3]);
      expect(await numbers(OrderFilter(garmentTypeId: shirt)), [2]);
      expect(
        await numbers(const OrderFilter(from: '2026-03-06', to: '2026-03-15')),
        [2],
      );
      expect(await numbers(const OrderFilter(from: '2026-03-10')), [2, 3]);
    });

    test('filters combine', () async {
      expect(await numbers(const OrderFilter(query: 'rahim', dueOnly: true)), [
        3,
      ]);
      expect(
        await numbers(
          const OrderFilter(query: 'rahim', dueOnly: true, to: '2026-03-10'),
        ),
        isEmpty,
      );
    });

    test('an empty filter changes nothing; equality and counts work', () async {
      expect(await numbers(const OrderFilter()), [1, 2, 3]);
      expect(const OrderFilter().isEmpty, isTrue);
      expect(
        const OrderFilter(statuses: {OrderStatus.cut}),
        const OrderFilter(statuses: {OrderStatus.cut}),
      );
      expect(const OrderFilter(dueOnly: true, from: 'a').activeCount, 2);
    });

    test('quotes and wildcards in the query are harmless', () async {
      expect(await numbers(const OrderFilter(query: "o'brien")), isEmpty);
      expect(await numbers(const OrderFilter(query: '%')), isA<List<int>>());
    });
  });

  group('reschedule reason (S4-08)', () {
    test('the reason is stored in the change log', () async {
      final d = await make();
      await repo.updateDetails(
        d.order.id,
        deliveryDate: '2026-03-14',
        reason: 'Fabric arrived late',
      );
      final log = await repo.watchChangeLog(d.order.id).first;
      expect(log.first.detail, contains('2026-03-10 → 2026-03-14'));
      expect(log.first.detail, contains('Fabric arrived late'));
    });
  });

  group('photos on create (S3-06)', () {
    test(
      'attachments are stored for each item in the same transaction',
      () async {
        final d = await make(
          photos: const [
            StoredImage(path: 'a.jpg', thumbPath: 'a.thumb.jpg'),
            StoredImage(path: 'b.jpg', thumbPath: 'b.thumb.jpg'),
          ],
        );
        final rows = await db.select(db.attachment).get();
        expect(rows.map((r) => r.path), ['a.jpg', 'b.jpg']);
        expect(rows.every((r) => r.ownerType == 'order_item'), isTrue);
        expect(rows.every((r) => r.ownerId == d.items.single.id), isTrue);
      },
    );

    test('a failed order stores no attachments', () async {
      await expectLater(
        make(
          customer: 'nobody',
          photos: const [StoredImage(path: 'a.jpg', thumbPath: 'a.thumb.jpg')],
        ),
        throwsA(anything),
      );
      expect(await db.select(db.attachment).get(), isEmpty);
    });
  });
}
