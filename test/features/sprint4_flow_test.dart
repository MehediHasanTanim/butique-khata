import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

import '../support/shop_fixture.dart';
import '../support/test_app.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('Flow D: ready → message → deliver (S4-10)', () {
    testWidgets('from the Home screen to a settled, delivered order', (
      tester,
    ) async {
      await openShop(tester, AppRoutes.home, extra: () => seedOrder());

      // Home answers "what is due today?".
      expect(textOf(tester, 'stat-today'), contains('1'));
      expect(find.byKey(const ValueKey('order-o-1')), findsOneWidget);
      expect(find.text('Rahim Uddin'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('order-o-1')));
      await tester.pumpAndSettle();
      expect(find.text('Order #1'), findsOneWidget);

      // Mark ready → the app offers to message the customer.
      await tapKeyed(tester, 'action-ready');
      expect(find.text('Tell the customer?'), findsOneWidget);
      final text = tester
          .widget<TextField>(find.byKey(const ValueKey('message-text')))
          .controller!
          .text;
      expect(text, contains('Rahim Uddin'));
      expect(text, contains('Panjabi'));
      expect(text, contains('order #1'));
      expect(text, contains('Balance due: ৳700.'));

      await tapKeyed(tester, 'message-sms');
      expect(env.launcher.opened, hasLength(1));
      final sms = env.launcher.opened.single;
      expect(sms.scheme, 'sms');
      expect(sms.path, '+8801712345678');
      expect(sms.queryParameters['body'], text);
      expect(
        find.text('Tell the customer?'),
        findsNothing,
        reason: 'sheet closed',
      );

      // The order is ready; handing it over asks about the balance.
      expect((await detail(tester, 'o-1')).order.status, OrderStatus.ready);
      expect(find.byKey(const ValueKey('action-ready')), findsNothing);
      await tapKeyed(tester, 'action-deliver');
      expect(find.text('৳700 is still due'), findsOneWidget);
      await tapKeyed(tester, 'deliver-collect');

      expect(find.text('Delivered'), findsWidgets);
      expect(textOf(tester, 'due'), '৳0');
      expect(find.byKey(const ValueKey('action-deliver')), findsNothing);
      final done = await detail(tester, 'o-1');
      expect(done.order.status, OrderStatus.delivered);
      expect(done.money.isSettled, isTrue);

      // Back on Home the delivery is gone from today's list.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(textOf(tester, 'stat-today'), contains('0'));
      expect(find.byKey(const ValueKey('home-nothing-due')), findsOneWidget);
      expect(textOf(tester, 'stat-due'), '৳0');
      await shutDown(tester, shopDb);
    });

    testWidgets('WhatsApp opens wa.me with the same text', (tester) async {
      await openShop(tester, '/order/o-1', extra: () => seedOrder());
      await tapKeyed(tester, 'action-ready');
      await tapKeyed(tester, 'message-whatsapp');
      final uri = env.launcher.opened.single;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/8801712345678');
      expect(uri.queryParameters['text'], contains('Rahim Uddin'));
      await shutDown(tester, shopDb);
    });

    testWidgets('no phone number: the text is copied instead', (tester) async {
      await openShop(
        tester,
        '/order/o-1',
        extra: () => seedOrder(customer: 'c2'),
      );
      await tapKeyed(tester, 'action-ready');
      await tapAndSee(tester, 'message-sms');
      expect(env.launcher.opened, isEmpty);
      expect(
        find.text('No phone number saved. The message was copied instead.'),
        findsOneWidget,
      );
      expect(clipboard, contains('Karim Hossain'));
      await shutDown(tester, shopDb);
    });

    testWidgets('messaging app missing: falls back to copying', (tester) async {
      await openShop(tester, '/order/o-1', extra: () => seedOrder());
      env.launcher.succeeds = false;
      await tapKeyed(tester, 'action-ready');
      await tapAndSee(tester, 'message-sms');
      expect(env.launcher.opened, hasLength(1));
      expect(
        find.text('Could not open the app. The message was copied.'),
        findsOneWidget,
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('the message can be edited before sending', (tester) async {
      await openShop(tester, '/order/o-1', extra: () => seedOrder());
      await tapKeyed(tester, 'action-ready');
      await tester.enterText(
        find.byKey(const ValueKey('message-text')),
        'Custom words',
      );
      await tapKeyed(tester, 'message-sms');
      expect(
        env.launcher.opened.single.queryParameters['body'],
        'Custom words',
      );
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('deliver guard (S4-03)', () {
    testWidgets('deliver anyway leaves the balance owing', (tester) async {
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          await seedOrder();
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      await tapKeyed(tester, 'action-deliver');
      await tapKeyed(tester, 'deliver-with-due');
      final d = await detail(tester, 'o-1');
      expect(d.order.status, OrderStatus.delivered);
      expect(d.money.due, const Money.taka(700));
      expect(textOf(tester, 'due'), '৳700');
      await shutDown(tester, shopDb);
    });

    testWidgets('backing out changes nothing', (tester) async {
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          await seedOrder();
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      await tapKeyed(tester, 'action-deliver');
      await tapText(tester, 'Go back');
      expect((await detail(tester, 'o-1')).order.status, OrderStatus.ready);
      await shutDown(tester, shopDb);
    });

    testWidgets('a settled order is delivered without a question', (
      tester,
    ) async {
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          await seedOrder(advance: 1200);
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      await tapKeyed(tester, 'action-deliver');
      expect(find.byKey(const ValueKey('deliver-collect')), findsNothing);
      expect((await detail(tester, 'o-1')).order.status, OrderStatus.delivered);
      await shutDown(tester, shopDb);
    });

    testWidgets('moving a single garment to Delivered asks too', (
      tester,
    ) async {
      late OrderDetail d;
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          d = await seedOrder();
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      await tapKeyed(tester, 'advance-${d.items.single.id}');
      expect(find.text('৳700 is still due'), findsOneWidget);
      await tapKeyed(tester, 'deliver-collect');
      final after = await detail(tester, 'o-1');
      expect(after.order.status, OrderStatus.delivered);
      expect(after.money.isSettled, isTrue);
      await shutDown(tester, shopDb);
    });

    testWidgets('picking Delivered in the status picker is guarded', (
      tester,
    ) async {
      late OrderDetail d;
      await openShop(
        tester,
        '/order/o-1',
        extra: () async {
          d = await seedOrder();
        },
      );
      await tapKeyed(tester, 'status-${d.items.single.id}');
      await tapKeyed(tester, 'pick-status-delivered');
      expect(find.byKey(const ValueKey('deliver-with-due')), findsOneWidget);
      await tapText(tester, 'Go back');
      expect((await detail(tester, 'o-1')).order.status, OrderStatus.received);
      await shutDown(tester, shopDb);
    });
  });
}
