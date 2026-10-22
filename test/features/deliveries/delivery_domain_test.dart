import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/deliveries/domain/deliver_order.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

import '../../support/test_app.dart';

({String title, String body}) words(ReminderKind kind, int count) =>
    (title: '${kind.name}:$count', body: 'body');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('MessageTemplates (S4-04)', () {
    test('render fills placeholders and leaves unknown ones', () {
      expect(
        MessageTemplates.render('Hi {name}, {x} #{order}', {
          'name': 'Rahim',
          'order': '12',
        }),
        'Hi Rahim, {x} #12',
      );
    });

    test('an empty {due} leaves no stray double spaces', () {
      final text = MessageTemplates.render(
        MessageTemplates.defaultFor(MessageKind.ready, 'en'),
        {
          'name': 'Rahim',
          'garment': 'Panjabi',
          'order': '7',
          'due': MessageTemplates.dueSentence('', 'en'),
          'shop': 'Noor Tailors',
        },
      );
      expect(
        text,
        contains('Your Panjabi (order #7) is ready for pickup. Thank you'),
      );
      expect(text.contains('  '), isFalse);
    });

    test('balance sentence in both languages', () {
      expect(MessageTemplates.dueSentence('৳700', 'en'), ' Balance due: ৳700.');
      expect(MessageTemplates.dueSentence('৳৭০০', 'bn'), contains('৳৭০০'));
    });

    test(
      'every kind has English and Bangla wording with the key placeholders',
      () {
        for (final kind in MessageKind.values) {
          for (final lang in ['en', 'bn']) {
            final t = MessageTemplates.defaultFor(kind, lang);
            expect(t, contains('{name}'));
            expect(t, contains('{order}'));
            expect(t, contains('{shop}'));
          }
          expect(kind.settingKey, 'tpl.${kind.name}');
        }
      },
    );
  });

  group('MessageLinks', () {
    test('sms and WhatsApp links for any phone format', () {
      final sms = MessageLinks.sms('01712-345678', 'Hello world & more')!;
      expect(sms.scheme, 'sms');
      expect(sms.path, '+8801712345678');
      expect(sms.queryParameters['body'], 'Hello world & more');

      final wa = MessageLinks.whatsApp('+8801712345678', 'Hi there')!;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/8801712345678');
      expect(wa.queryParameters['text'], 'Hi there');
    });

    test('no usable phone gives no link', () {
      expect(MessageLinks.sms(null, 'x'), isNull);
      expect(MessageLinks.sms('', 'x'), isNull);
      expect(MessageLinks.sms('123', 'x'), isNull);
      expect(MessageLinks.whatsApp('abc', 'x'), isNull);
    });

    test('Bangla text survives encoding', () {
      const text = 'আপনার পোশাক তৈরি';
      final uri = MessageLinks.sms('01712345678', text)!;
      expect(uri.queryParameters['body'], text);
    });
  });

  group('planReminders (S4-05)', () {
    final now = DateTime(2026, 3, 10, 10);
    const settings = ReminderSettings();

    List<PlannedNotification> plan(
      List<DeliveryDay> days, {
      ReminderSettings s = settings,
      DateTime? at,
    }) => planReminders(days: days, now: at ?? now, settings: s, text: words);

    DeliveryDay day(String date, int count, [String id = 'o1']) =>
        DeliveryDay(date: date, count: count, firstOrderId: id);

    test('nothing to do when disabled or no deliveries', () {
      expect(plan(const []), isEmpty);
      expect(
        plan([day('2026-03-12', 2)], s: const ReminderSettings(enabled: false)),
        isEmpty,
      );
    });

    test('groups a busy day into one morning and one evening notification', () {
      final result = plan([day('2026-03-12', 5)]);
      expect(result, hasLength(2));
      expect(result[0].at, DateTime(2026, 3, 11, 19)); // evening before
      expect(result[0].title, 'eveningBefore:5');
      expect(result[0].payload, '/deliveries?tab=tomorrow');
      expect(result[1].at, DateTime(2026, 3, 12, 8));
      expect(result[1].title, 'morningOf:5');
      expect(result[1].payload, '/deliveries?tab=today');
    });

    test('a single delivery deep-links to the order', () {
      final result = plan([day('2026-03-12', 1, 'abc')]);
      expect(result.map((n) => n.payload), everyElement('/order/abc'));
    });

    test('past times are skipped', () {
      // Today's morning slot (08:00) has passed at 10:00; the evening before
      // was yesterday.
      expect(plan([day('2026-03-10', 2)]), isEmpty);
      // Tomorrow: evening-before is today 19:00, still ahead.
      final tomorrow = plan([day('2026-03-11', 2)]);
      expect(tomorrow.map((n) => n.at), [
        DateTime(2026, 3, 10, 19),
        DateTime(2026, 3, 11, 8),
      ]);
    });

    test('custom times are honoured', () {
      final result = plan(
        [day('2026-03-12', 2)],
        s: const ReminderSettings(
          eveningMinutes: 20 * 60 + 30,
          morningMinutes: 7 * 60 + 15,
        ),
      );
      expect(result.map((n) => n.at), [
        DateTime(2026, 3, 11, 20, 30),
        DateTime(2026, 3, 12, 7, 15),
      ]);
    });

    test('overdue deliveries get a daily digest at the digest time', () {
      final result = plan([day('2026-03-05', 2), day('2026-03-08', 1)]);
      // Seven days from today, minus today's 09:00 which has already passed.
      expect(result, hasLength(6));
      expect(result.first.at, DateTime(2026, 3, 11, 9)); // today 09:00 passed
      expect(result.every((n) => n.title == 'overdueDigest:3'), isTrue);
      expect(
        result.every((n) => n.payload == '/deliveries?tab=overdue'),
        isTrue,
      );
    });

    test('ids are stable and unique; output is sorted by time', () {
      final days = [
        day('2026-03-12', 2),
        day('2026-03-14', 3),
        day('2026-03-05', 1),
      ];
      final a = plan(days);
      final b = plan(days);
      expect(a, b);
      expect(a.map((n) => n.id).toSet(), hasLength(a.length));
      for (var i = 1; i < a.length; i++) {
        expect(a[i].at.isBefore(a[i - 1].at), isFalse);
      }
    });

    test('editing a delivery date replaces its notifications', () {
      final before = plan([day('2026-03-12', 1)]);
      final after = plan([day('2026-03-15', 1)]);
      expect(
        before
            .map((n) => n.id)
            .toSet()
            .intersection(after.map((n) => n.id).toSet()),
        isEmpty,
      );
    });

    test('the plan is capped', () {
      final days = [
        for (var i = 0; i < 100; i++)
          day(
            Clock.toDateString(
              DateTime(2026, 4, 1 + i % 28, 0).add(Duration(days: i ~/ 28)),
            ),
            1,
          ),
      ];
      expect(
        planReminders(
          days: days,
          now: now,
          settings: settings,
          text: words,
          maxCount: 20,
        ),
        hasLength(20),
      );
    });

    test('crosses month and year ends', () {
      final result = plan([day('2027-01-01', 2)], at: DateTime(2026, 12, 30));
      expect(result.map((n) => n.at), [
        DateTime(2026, 12, 31, 19),
        DateTime(2027, 1, 1, 8),
      ]);
    });
  });

  group('DeliverOrder (S4-03)', () {
    late AppDatabase db;
    late DriftOrderRepository repo;
    late DeliverOrder deliver;
    late String panjabi;

    setUp(() async {
      db = memoryDb();
      final clock = FixedClock(DateTime(2026, 3, 10));
      repo = DriftOrderRepository(db, clock, SequentialIdGenerator('o'));
      deliver = DeliverOrder(repo);
      await DriftCustomerRepository(db).insert(
        Customer(
          id: 'c1',
          name: 'Rahim',
          createdAt: clock.now(),
          updatedAt: clock.now(),
        ),
      );
      panjabi = BuiltInTemplates.byKey('panjabi').id;
    });
    tearDown(() => db.close());

    Future<OrderDetail> make(int advance) => repo.create(
      NewOrder(
        customerId: 'c1',
        deliveryDate: '2026-03-10',
        items: [
          NewOrderItem(garmentTypeId: panjabi, price: const Money.taka(1000)),
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

    test('with a balance it asks first and changes nothing', () async {
      final d = await make(300);
      final result = await deliver(d.order.id, today: '2026-03-10');
      final failure = result.failureOrNull;
      expect(failure, isA<DueOutstandingFailure>());
      expect((failure! as DueOutstandingFailure).due, const Money.taka(700));
      expect(
        (await repo.detail(d.order.id))!.order.status,
        OrderStatus.received,
      );
    });

    test('collect and deliver settles the balance', () async {
      final d = await make(300);
      final result = await deliver(
        d.order.id,
        choice: DeliverChoice.collectAndDeliver,
        method: PayMethod.nagad,
        today: '2026-03-10',
      );
      expect(result.isOk, isTrue);
      final after = (await repo.detail(d.order.id))!;
      expect(after.order.status, OrderStatus.delivered);
      expect(after.money.isSettled, isTrue);
      expect(after.payments.last.method, PayMethod.nagad);
    });

    test('deliver with due keeps the balance owing', () async {
      final d = await make(300);
      await deliver(
        d.order.id,
        choice: DeliverChoice.deliverWithDue,
        today: '2026-03-10',
      );
      final after = (await repo.detail(d.order.id))!;
      expect(after.order.status, OrderStatus.delivered);
      expect(after.money.due, const Money.taka(700));
    });

    test(
      'a settled order delivers straight away; a choice is ignored',
      () async {
        final d = await make(1000);
        final result = await deliver(
          d.order.id,
          choice: DeliverChoice.collectAndDeliver,
          today: '2026-03-10',
        );
        expect(result.isOk, isTrue);
        expect((await repo.detail(d.order.id))!.payments, hasLength(1));
      },
    );

    test('cancelled and missing orders are refused', () async {
      final d = await make(0);
      await repo.cancel(
        d.order.id,
        reason: 'x',
        advance: CancelAdvance.keep,
        today: '2026-03-10',
      );
      expect(
        (await deliver(d.order.id, today: '2026-03-10')).failureOrNull?.code,
        'deliver.cancelled',
      );
      expect(
        (await deliver('nope', today: '2026-03-10')).failureOrNull?.code,
        'deliver.not_found',
      );
    });

    test('no other path marks a garment delivered with a balance', () async {
      final d = await make(300);
      // Every status-changing entry point refuses without confirmation.
      final attempts = <Future<void>>[
        repo.setItemStatus(d.items.single.id, OrderStatus.delivered),
        repo.setAllItemsStatus(d.order.id, OrderStatus.delivered),
        repo.deliverAll(d.order.id),
      ];
      for (final attempt in attempts) {
        await expectLater(attempt, throwsA(isA<DueOutstandingError>()));
      }
    });
  });
}
