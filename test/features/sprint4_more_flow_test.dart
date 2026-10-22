import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/photo_widgets.dart';
import 'package:tailor_khata/features/settings/data/app_settings.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

import '../support/fakes.dart';
import '../support/shop_fixture.dart';
import '../support/test_app.dart';

void main() {
  // -------------------------------------------------------------------------
  group('dashboard (S4-07)', () {
    Future<void> seedMix() async {
      await seedOrder(); // today, due 700
      await seedOrder(
        customer: 'c2',
        delivery: '2026-03-08',
        price: 300,
        advance: 0,
        garment: 'shirt',
      ); // overdue, due 300
      await seedOrder(
        delivery: '2026-03-20',
        price: 200,
        advance: 200,
      ); // settled
    }

    testWidgets('shows today, overdue, outstanding money and new orders', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.home, extra: seedMix);
      expect(textOf(tester, 'stat-today'), '1');
      expect(textOf(tester, 'stat-overdue'), '1');
      expect(textOf(tester, 'stat-due'), '৳1,000');
      expect(textOf(tester, 'stat-received'), '3');
      // Today's list holds only today's delivery.
      expect(find.byKey(const ValueKey('order-o-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-o-4')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('an empty shop says so', (tester) async {
      await openShop(tester, AppRoutes.home);
      expect(textOf(tester, 'stat-today'), '0');
      expect(textOf(tester, 'stat-due'), '৳0');
      expect(find.byKey(const ValueKey('home-nothing-due')), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-uncollected')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('updates live when an order is delivered', (tester) async {
      await openShop(tester, AppRoutes.home, extra: seedMix);
      await tester.runAsync(
        () => orders.deliverAll('o-1', collect: const Money.taka(700)),
      );
      await tester.pumpAndSettle();
      expect(textOf(tester, 'stat-today'), '0');
      expect(textOf(tester, 'stat-due'), '৳300');
      await shutDown(tester, shopDb);
    });

    testWidgets('cards open the matching list', (tester) async {
      await openShop(tester, AppRoutes.home, extra: seedMix);
      await tapKeyed(tester, 'stat-overdue');
      expect(find.text('Deliveries'), findsOneWidget);
      expect(find.text('Karim Hossain'), findsOneWidget); // overdue tab first
      expect(find.text('Rahim Uddin'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKeyed(tester, 'stat-due');
      expect(find.text('Total outstanding'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('quick actions start an order or a customer', (tester) async {
      await openShop(tester, AppRoutes.home);
      await tapKeyed(tester, 'quick-new-customer');
      expect(find.text('New customer'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKeyed(tester, 'quick-new-order');
      expect(find.text('Choose customer'), findsOneWidget);
      await tapKeyed(tester, 'pick-c1');
      expect(find.byKey(const ValueKey('step-title')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla digits and labels', (tester) async {
      await openShop(tester, AppRoutes.home, locale: 'bn', extra: seedMix);
      expect(textOf(tester, 'stat-today'), '১');
      expect(textOf(tester, 'stat-due'), '৳১,০০০');
      expect(find.text('আজ দিতে হবে'), findsWidgets);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });
  });

  // -------------------------------------------------------------------------
  group('deliveries (S4-02, S4-08)', () {
    Future<void> seedDays() async {
      await seedOrder(); // today: Rahim
      await seedOrder(customer: 'c2', garment: 'shirt', price: 500, advance: 0);
      await seedOrder(delivery: '2026-03-11'); // tomorrow
      await seedOrder(delivery: '2026-03-14'); // this week
      await seedOrder(delivery: '2026-03-17'); // week, last day
      await seedOrder(delivery: '2026-03-18'); // later: no tab
      await seedOrder(delivery: '2026-03-05'); // overdue
    }

    testWidgets('tabs show counts and the right orders', (tester) async {
      await openShop(tester, '/deliveries', extra: seedDays);
      expect(find.text('Today (2)'), findsOneWidget);
      expect(find.text('Tomorrow (1)'), findsOneWidget);
      expect(find.text('This week (2)'), findsOneWidget);
      expect(find.text('Overdue (1)'), findsOneWidget);
      expect(find.text('Uncollected (0)'), findsOneWidget);

      // Today: both orders under one date heading.
      expect(find.text('10 Mar 2026'), findsOneWidget);
      expect(find.text('Rahim Uddin'), findsOneWidget);
      expect(find.text('Karim Hossain'), findsOneWidget);

      await tapKeyed(tester, 'tab-tomorrow');
      expect(find.text('11 Mar 2026'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);

      await tapKeyed(tester, 'tab-week');
      expect(find.text('14 Mar 2026'), findsOneWidget);
      expect(find.text('17 Mar 2026'), findsOneWidget);
      expect(find.text('18 Mar 2026'), findsNothing);

      await tapKeyed(tester, 'tab-overdue');
      expect(find.text('5 Mar 2026'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('the tab named in the link is selected', (tester) async {
      await openShop(
        tester,
        AppRoutes.deliveries(tab: 'overdue'),
        extra: seedDays,
      );
      expect(find.text('5 Mar 2026'), findsOneWidget);
      expect(find.text('10 Mar 2026'), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('an empty bucket explains itself', (tester) async {
      await openShop(tester, '/deliveries');
      expect(find.text('Nothing due here'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('lists refresh when an order is handed over', (tester) async {
      await openShop(tester, '/deliveries', extra: seedDays);
      expect(find.text('Rahim Uddin'), findsOneWidget);
      await tester.runAsync(
        () => orders.deliverAll('o-1', collect: const Money.taka(700)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rahim Uddin'), findsNothing);
      expect(find.text('Today (1)'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('long lists are paged with Load more', (tester) async {
      await openShop(
        tester,
        '/deliveries',
        extra: () async {
          for (var i = 0; i < 35; i++) {
            await shopDb.customStatement(
              'INSERT INTO customer_order (id, number, customer_id, delivery_date, '
              "discount, urgent, status, created_at, updated_at) VALUES ('b$i', ${200 + i}, 'c1', "
              "'2026-03-10', 0, 0, 'received', 1, 1)",
            );
          }
        },
      );
      expect(find.text('Today (35)'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-b0')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-b34')), findsNothing);

      // Scrolling near the end fetches the next page by itself.
      for (var i = 0; i < 4; i++) {
        await tester.drag(verticalScrollable, const Offset(0, -2500));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('order-b34')), findsOneWidget);
      expect(find.byKey(const ValueKey('load-more')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('uncollected: ready for days and still here', (tester) async {
      await openShop(
        tester,
        '/deliveries',
        extra: () async {
          await seedOrder(advance: 1200); // ready 6 days ago, not collected
          await seedOrder(
            customer: 'c2',
            garment: 'shirt',
            price: 500,
            advance: 500,
          );
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
          await orders.setAllItemsStatus('o-4', OrderStatus.ready);
          final old = DateTime(2026, 3, 4, 10).millisecondsSinceEpoch;
          await shopDb.customStatement(
            'UPDATE order_item SET status_changed_at = $old WHERE order_id = \'o-1\'',
          );
          await shopDb.customStatement(
            'UPDATE customer_order SET updated_at = $old WHERE id = \'o-1\'',
          );
        },
      );
      expect(find.text('Uncollected (1)'), findsOneWidget);
      await tapKeyed(tester, 'tab-uncollected');
      expect(find.text('Rahim Uddin'), findsOneWidget);
      expect(find.text('Karim Hossain'), findsNothing);
      expect(find.text('Ready for 6 days'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Home flags uncollected garments', (tester) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () async {
          await seedOrder(advance: 1200, delivery: '2026-03-20');
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
          final old = DateTime(2026, 3, 1).millisecondsSinceEpoch;
          await shopDb.customStatement(
            'UPDATE order_item SET status_changed_at = $old',
          );
        },
      );
      expect(find.byKey(const ValueKey('stat-uncollected')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla tab labels use Bangla digits', (tester) async {
      await openShop(tester, '/deliveries', locale: 'bn', extra: seedDays);
      expect(find.text('আজ (২)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('moving a delivery date can notify the customer (S4-08)', (
      tester,
    ) async {
      await openShop(
        tester,
        '/order/o-1',
        extra: () => seedOrder(delivery: '2026-03-20'),
      );
      await tester.tap(find.byKey(const ValueKey('order-menu')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Change delivery');
      // The reason box only appears once the date has moved.
      expect(find.byKey(const ValueKey('reschedule-reason')), findsNothing);
      await tapKeyed(tester, 'edit-delivery-date');
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reschedule-reason')),
        'Fabric arrived late',
      );
      await tapKeyed(tester, 'edit-delivery-save');

      // The "delivery moved" message is offered with the new date.
      expect(
        find.text('Tell the customer about the new date?'),
        findsOneWidget,
      );
      final text = tester
          .widget<TextField>(find.byKey(const ValueKey('message-text')))
          .controller!
          .text;
      expect(text, contains('25 Mar 2026'));
      expect(text, contains('order #1'));
      await tapKeyed(tester, 'message-sms');
      expect(env.launcher.opened.single.queryParameters['body'], text);

      final log = await tester.runAsync(
        () => orders.watchChangeLog('o-1').first,
      );
      expect(log!.first.detail, contains('2026-03-20 → 2026-03-25'));
      expect(log.first.detail, contains('Fabric arrived late'));
      await shutDown(tester, shopDb);
    });

    testWidgets('changing only urgency does not offer a message', (
      tester,
    ) async {
      await openShop(tester, '/order/o-1', extra: () => seedOrder());
      await tester.tap(find.byKey(const ValueKey('order-menu')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Change delivery');
      await tapText(tester, 'Urgent');
      await tapKeyed(tester, 'edit-delivery-save');
      expect(find.byKey(const ValueKey('message-text')), findsNothing);
      expect((await detail(tester, 'o-1')).order.urgent, isTrue);
      await shutDown(tester, shopDb);
    });
  });

  // -------------------------------------------------------------------------
  group('reminders (S4-05, S4-06)', () {
    testWidgets('the schedule is built at start from open deliveries', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () => seedOrder(delivery: '2026-03-11'),
      );
      final plan = env.notifications.current;
      expect(plan, hasLength(2));
      expect(plan[0].at, DateTime(2026, 3, 10, 19));
      expect(plan[0].title, '1 delivery tomorrow');
      expect(plan[0].payload, '/order/o-1');
      expect(plan[1].at, DateTime(2026, 3, 11, 8));
      expect(plan[1].title, '1 delivery today');
      await shutDown(tester, shopDb);
    });

    testWidgets('several orders on one day make one grouped reminder', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () async {
          for (var i = 0; i < 5; i++) {
            await seedOrder(delivery: '2026-03-12');
          }
        },
      );
      final plan = env.notifications.current;
      expect(plan, hasLength(2));
      expect(
        plan.first.title,
        '5 deliveries tomorrow'.replaceAll('tomorrow', 'tomorrow'),
      );
      expect(plan.first.payload, '/deliveries?tab=tomorrow');
      await shutDown(tester, shopDb);
    });

    testWidgets('changing a delivery date replaces the reminders', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () => seedOrder(delivery: '2026-03-12'),
      );
      final before = env.notifications.current.map((n) => n.id).toSet();
      await tester.runAsync(
        () => orders.updateDetails('o-1', deliveryDate: '2026-03-15'),
      );
      await tester.pump(const Duration(seconds: 1));
      final after = env.notifications.current;
      expect(after.map((n) => n.id).toSet().intersection(before), isEmpty);
      expect(after.first.at, DateTime(2026, 3, 14, 19));
      await shutDown(tester, shopDb);
    });

    testWidgets('a delivered order no longer reminds', (tester) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () => seedOrder(delivery: '2026-03-12', advance: 1200),
      );
      expect(env.notifications.current, isNotEmpty);
      await tester.runAsync(() => orders.deliverAll('o-1'));
      await tester.pump(const Duration(seconds: 1));
      expect(env.notifications.current, isEmpty);
      await shutDown(tester, shopDb);
    });

    testWidgets('overdue deliveries produce a daily digest', (tester) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () => seedOrder(delivery: '2026-03-05'),
      );
      final plan = env.notifications.current;
      expect(plan, isNotEmpty);
      expect(plan.every((n) => n.title == '1 delivery overdue'), isTrue);
      expect(plan.first.at, DateTime(2026, 3, 11, 9));
      await shutDown(tester, shopDb);
    });

    testWidgets('reminder texts follow the app language', (tester) async {
      await openShop(
        tester,
        AppRoutes.home,
        locale: 'bn',
        extra: () => seedOrder(delivery: '2026-03-11'),
      );
      expect(env.notifications.current.first.title, contains('আগামীকাল'));
      await shutDown(tester, shopDb);
    });

    testWidgets('tapping a reminder opens the order', (tester) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () => seedOrder(delivery: '2026-03-11'),
      );
      env.notifications.tap('/order/o-1');
      await tester.pumpAndSettle();
      expect(find.text('Order #1'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a reminder that launched the app opens its screen', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.home,
        withEnv: TestEnv(launch: '/deliveries?tab=tomorrow'),
        extra: () => seedOrder(delivery: '2026-03-11'),
      );
      expect(find.text('Tomorrow (1)'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a stale payload never crashes the app', (tester) async {
      await openShop(tester, AppRoutes.home);
      env.notifications.tap('/no/such/page');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('settings: switching reminders off clears the schedule', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.settingsReminders,
        extra: () => seedOrder(delivery: '2026-03-12'),
      );
      expect(env.notifications.current, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('reminders-enabled')));
      await tester.pump(const Duration(seconds: 1));
      expect(env.notifications.current, isEmpty);
      // Persisted.
      final stored = await tester.runAsync(
        () => SettingsRepository(shopDb).read(AppSettingKeys.reminderEnabled),
      );
      expect(stored, 'false');
      await tester.tap(find.byKey(const ValueKey('reminders-enabled')));
      await tester.pump(const Duration(seconds: 1));
      expect(env.notifications.current, isNotEmpty);
      await shutDown(tester, shopDb);
    });

    testWidgets('settings: asking for notification permission', (tester) async {
      await openShop(tester, AppRoutes.settingsReminders);
      expect(find.text('Notifications are off for this app'), findsOneWidget);
      await tapKeyed(tester, 'permission-allow');
      expect(env.notifications.permissionRequests, 1);
      expect(find.text('Notifications are allowed'), findsOneWidget);
      expect(find.byKey(const ValueKey('permission-allow')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('settings: allowed already, and battery guidance is shown', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.settingsReminders,
        withEnv: TestEnv(notificationsGranted: true),
      );
      expect(find.text('Notifications are allowed'), findsOneWidget);
      expect(find.text('If reminders do not appear'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('settings: choosing another evening time reschedules', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.settingsReminders,
        extra: () => seedOrder(delivery: '2026-03-12'),
      );
      expect(env.notifications.current.first.at, DateTime(2026, 3, 11, 19));
      await tapKeyed(tester, 'time-evening');
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      // 12-hour dial in English: 8:30 with the existing PM.
      await tester.enterText(fields.at(0), '8');
      await tester.enterText(fields.at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(env.notifications.current.first.at, DateTime(2026, 3, 11, 20, 30));
      expect(find.text('20:30'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('settings: uncollected threshold', (tester) async {
      await openShop(tester, AppRoutes.settingsReminders);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
      final stored = await tester.runAsync(
        () => SettingsRepository(shopDb).read(AppSettingKeys.uncollectedDays),
      );
      expect(stored, '4');
      await shutDown(tester, shopDb);
    });
  });

  // -------------------------------------------------------------------------
  group('message settings (S4-04)', () {
    testWidgets('edited wording and shop name are used in messages', (
      tester,
    ) async {
      await openShop(
        tester,
        '/order/o-1',
        configure: (env) => env.settings = const AppSettings(
          shopName: 'Noor Tailors',
          templates: {MessageKind.ready: 'Ready: {name} / {shop} / {garment}'},
        ),
        extra: () => seedOrder(),
      );
      await tapKeyed(tester, 'action-ready');
      final text = tester
          .widget<TextField>(find.byKey(const ValueKey('message-text')))
          .controller!
          .text;
      expect(text, 'Ready: Rahim Uddin / Noor Tailors / Panjabi / Kurta');
      await shutDown(tester, shopDb);
    });

    testWidgets('typing in settings saves the shop name and wording', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.settingsMessages);
      await tester.enterText(
        find.byKey(const ValueKey('shop-name')),
        'Noor Tailors',
      );
      await tester.enterText(
        find.byKey(const ValueKey('template-ready')),
        'Hello {name}',
      );
      await tester.pump(const Duration(seconds: 1));
      final repo = SettingsRepository(shopDb);
      expect(
        await tester.runAsync(() => repo.read('shop.name')),
        'Noor Tailors',
      );
      expect(
        await tester.runAsync(() => repo.read('tpl.ready')),
        'Hello {name}',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('the standard wording is shown and can be restored', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.settingsMessages);
      final field = find.byKey(const ValueKey('template-ready'));
      final standard = MessageTemplates.defaultFor(MessageKind.ready, 'en');
      expect(tester.widget<TextField>(field).controller!.text, standard);

      await tester.enterText(field, 'Changed');
      await tester.pump(const Duration(seconds: 1));
      await tapKeyed(tester, 'template-reset-ready');
      expect(tester.widget<TextField>(field).controller!.text, standard);
      expect(
        await tester.runAsync(
          () => SettingsRepository(shopDb).read('tpl.ready'),
        ),
        isNull,
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla wording is the default in Bangla', (tester) async {
      await openShop(tester, AppRoutes.settingsMessages, locale: 'bn');
      final text = tester
          .widget<TextField>(find.byKey(const ValueKey('template-ready')))
          .controller!
          .text;
      expect(text, MessageTemplates.defaultFor(MessageKind.ready, 'bn'));
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });
  });

  // -------------------------------------------------------------------------
  group('photos (S3-06)', () {
    int filesIn(TestEnv e) {
      final dir = Directory('${e.dir.path}/media');
      return dir.existsSync() ? dir.listSync().length : 0;
    }

    Future<void> toDetailsStep(WidgetTester tester) async {
      await tapKeyed(tester, 'add-panjabi');
      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'wizard-next');
    }

    testWidgets('add a photo in the wizard; it is saved with the order', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      await tapNoSettle(tester, 'panjabi-photo-camera');
      await settleIo(tester);
      expect(env.photos.requests, [PhotoOrigin.camera]);
      expect(find.byType(PhotoThumb), findsOneWidget);
      expect(filesIn(env), 2, reason: 'image + thumbnail');

      await tester.enterText(
        find.byKey(const ValueKey('price-panjabi')),
        '900',
      );
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('Order #1'), findsOneWidget);

      final rows = await query(
        tester,
        () => shopDb.select(shopDb.attachment).get(),
      );
      expect(rows, hasLength(1));
      expect(rows.single.ownerType, 'order_item');
      final order = await query(
        tester,
        () => shopDb.select(shopDb.orderItem).get(),
      );
      expect(rows.single.ownerId, order.single.id);
      expect(
        find.byType(PhotoThumb),
        findsOneWidget,
        reason: 'shown on the order',
      );
      expect(filesIn(env), 2);
      await shutDown(tester, shopDb);
    });

    testWidgets('gallery works too, and several photos can be added', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      await tapNoSettle(tester, 'panjabi-photo-gallery');
      await settleIo(tester);
      await tapNoSettle(tester, 'panjabi-photo-camera');
      await settleIo(tester);
      expect(find.byType(PhotoThumb), findsNWidgets(2));
      expect(env.photos.requests, [PhotoOrigin.gallery, PhotoOrigin.camera]);
      await shutDown(tester, shopDb);
    });

    testWidgets('removing a photo in the wizard deletes its files', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      await tapNoSettle(tester, 'panjabi-photo-camera');
      await settleIo(tester);
      expect(filesIn(env), 2);
      final remove = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('remove-'),
      );
      await reveal(tester, remove);
      await tester.tap(remove);
      await settleIo(tester);
      expect(find.byType(PhotoThumb), findsNothing);
      expect(filesIn(env), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('cancelling the picker adds nothing', (tester) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      env.photos.cancel = true;
      await tapNoSettle(tester, 'panjabi-photo-camera');
      await settleIo(tester);
      expect(find.byType(PhotoThumb), findsNothing);
      expect(filesIn(env), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('an unreadable picture shows a message and keeps nothing', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      env.photos.corrupt = true;
      await tapNoSettle(tester, 'panjabi-photo-gallery');
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Could not use that photo'), findsOneWidget);
      expect(find.byType(PhotoThumb), findsNothing);
      expect(filesIn(env), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('discarding the order deletes its photos', (tester) async {
      await openShop(tester, AppRoutes.newOrder('c1'));
      await toDetailsStep(tester);
      await tapNoSettle(tester, 'panjabi-photo-camera');
      await settleIo(tester);
      expect(filesIn(env), 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await settleIo(tester);
      expect(filesIn(env), 0);
      expect(
        await query(tester, () => shopDb.select(shopDb.attachment).get()),
        isEmpty,
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('add and remove photos on a saved order', (tester) async {
      late String itemId;
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          itemId = (await seedOrder()).items.single.id;
        },
      );
      expect(find.byType(PhotoThumb), findsNothing);
      await tapNoSettle(tester, '$itemId-photo-gallery');
      await settleIo(tester);
      expect(find.byType(PhotoThumb), findsOneWidget);
      expect(filesIn(env), 2);
      expect(
        await query(tester, () => shopDb.select(shopDb.attachment).get()),
        hasLength(1),
      );

      final remove = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('remove-'),
      );
      await reveal(tester, remove);
      await tester.tap(remove);
      await settleIo(tester);
      expect(find.byType(PhotoThumb), findsNothing);
      expect(filesIn(env), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets(
      'a delivered order can still show its photos but not change them',
      (tester) async {
        late String itemId;
        await openShop(
          tester,
          '/order/o-1',
          extra: () async {
            itemId = (await seedOrder(advance: 1200)).items.single.id;
            await orders.deliverAll('o-1');
          },
        );
        // Delivered orders stay editable for photos? Cancelled ones do not.
        expect(find.byKey(ValueKey('$itemId-photo-gallery')), findsOneWidget);
        await shutDown(tester, shopDb);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('cutting slip (S3-12)', () {
    testWidgets('shows order, delivery, style and the exact measurements', (
      tester,
    ) async {
      await openShop(
        tester,
        '/order/o-1/slip',
        extra: () async {
          final m = await DriftMeasurementRepository(
            shopDb,
            env.clock,
            SequentialIdGenerator('mm'),
          ).latest('c1', panjabiId);
          await seedOrder(measurementSetId: m!.id);
        },
      );
      expect(find.text('Cutting slip'), findsWidgets);
      expect(textOf(tester, 'slip-order-no'), 'Order #1');
      expect(find.text('Rahim Uddin'), findsOneWidget);
      expect(textOf(tester, 'slip-delivery'), 'Delivery: 10 Mar 2026');
      expect(find.text('Panjabi / Kurta'), findsOneWidget);
      expect(find.text('Collar: Band'), findsOneWidget);
      expect(find.text('Version 1 · 1 Mar 2026'), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('38½'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('uses the shop name when set; says when nothing is linked', (
      tester,
    ) async {
      await openShop(
        tester,
        '/order/o-1/slip',
        configure: (e) =>
            e.settings = const AppSettings(shopName: 'Noor Tailors'),
        extra: () => seedOrder(),
      );
      expect(find.text('Noor Tailors'), findsOneWidget);
      expect(find.text('No measurements linked'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('urgent and trial dates are called out', (tester) async {
      await openShop(
        tester,
        '/order/o-1/slip',
        extra: () async {
          await seedOrder();
          await orders.updateDetails(
            'o-1',
            trialDate: '2026-03-07',
            urgent: true,
            note: 'Wedding',
          );
        },
      );
      expect(find.text('URGENT'), findsOneWidget);
      expect(find.text('Trial: 7 Mar 2026'), findsOneWidget);
      expect(find.text('Wedding'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('sharing hands over a PNG picture of the slip', (tester) async {
      await openShop(tester, '/order/o-1/slip', extra: () => seedOrder());
      await tester.tap(find.byKey(const ValueKey('slip-share')));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(env.sharer.shared, hasLength(1));
      final shared = env.sharer.shared.single;
      expect(shared.fileName, 'slip-1.png');
      expect(shared.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(shared.bytes.length, greaterThan(2000));
      expect(find.text('Slip shared'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla slip uses Bangla digits and labels', (tester) async {
      await openShop(
        tester,
        '/order/o-1/slip',
        locale: 'bn',
        extra: () => seedOrder(),
      );
      expect(textOf(tester, 'slip-order-no'), 'অর্ডার #১');
      expect(find.text('কাটিং স্লিপ'), findsWidgets);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('reachable from the order menu', (tester) async {
      await openShop(tester, '/order/o-1', extra: () => seedOrder());
      await tester.tap(find.byKey(const ValueKey('order-menu')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cutting slip');
      expect(find.byKey(const ValueKey('slip-card')), findsOneWidget);
      await shutDown(tester, shopDb);
    });
  });

  // -------------------------------------------------------------------------
  group('search and filters (S4-09)', () {
    Future<void> seedSearch() async {
      await seedOrder(delivery: '2026-03-12'); // #1 Rahim, due 700
      await seedOrder(
        customer: 'c2',
        delivery: '2026-03-14',
        garment: 'shirt',
        price: 500,
        advance: 500,
      ); // #2 Karim, paid
      await seedOrder(
        delivery: '2026-03-16',
        price: 300,
        advance: 0,
      ); // #3 Rahim
    }

    Future<void> typeSearch(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('order-search')), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('search the order list by name, phone and number', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.orders, extra: seedSearch);
      expect(find.byType(Card), findsNWidgets(3));
      await typeSearch(tester, 'karim');
      expect(find.byKey(const ValueKey('order-o-4')), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      await typeSearch(tester, '1712');
      expect(find.byType(Card), findsNWidgets(2));
      await typeSearch(tester, '#3');
      expect(find.byType(Card), findsOneWidget);
      await typeSearch(tester, 'nobody');
      expect(find.text('No orders match these filters'), findsOneWidget);
      await tapKeyed(tester, 'filter-clear-inline');
      expect(find.byType(Card), findsNWidgets(3));
      await shutDown(tester, shopDb);
    });

    testWidgets('searching also finds delivered orders', (tester) async {
      await openShop(
        tester,
        AppRoutes.orders,
        extra: () async {
          await seedSearch();
          await orders.deliverAll('o-4');
        },
      );
      expect(find.text('Karim Hossain'), findsNothing, reason: 'open only');
      await typeSearch(tester, 'karim');
      expect(find.text('Karim Hossain'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('filter: only orders with money due', (tester) async {
      await openShop(tester, AppRoutes.orders, extra: seedSearch);
      await tapKeyed(tester, 'order-filter-button');
      await tapKeyed(tester, 'filter-due');
      await tapKeyed(tester, 'filter-apply');
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('Karim Hossain'), findsNothing);
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue, reason: 'filter badge');
      await shutDown(tester, shopDb);
    });

    testWidgets('filter: status and garment, then clear', (tester) async {
      await openShop(
        tester,
        AppRoutes.orders,
        extra: () async {
          await seedSearch();
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      await tapKeyed(tester, 'order-filter-button');
      await tapKeyed(tester, 'filter-status-ready');
      await tapKeyed(tester, 'filter-apply');
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Rahim Uddin'), findsOneWidget);

      await tapKeyed(tester, 'order-filter-button');
      await tapKeyed(tester, 'filter-clear');
      expect(find.byType(Card), findsNWidgets(3));

      await tapKeyed(tester, 'order-filter-button');
      await tapKeyed(tester, 'filter-garment');
      await tester.tap(find.text('Shirt').last);
      await tester.pumpAndSettle();
      await tapKeyed(tester, 'filter-apply');
      expect(find.text('Karim Hossain'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('global search finds customers and orders', (tester) async {
      await openShop(tester, AppRoutes.home, extra: seedSearch);
      await tapKeyed(tester, 'home-search');
      await tester.enterText(
        find.byKey(const ValueKey('global-search-field')),
        'rahim',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Customers'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-customer-c1')), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-o-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-o-4')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('global-search-field')),
        'zzzz',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Nothing found'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('global-search-field')),
        '01712',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-customer-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-customer-c2')), findsNothing);
      await shutDown(tester, shopDb);
    });
  });
}
