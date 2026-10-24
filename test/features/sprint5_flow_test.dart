import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';
import 'package:tailor_khata/features/rush/presentation/load_calendar_screen.dart';

import '../support/shop_fixture.dart';
import '../support/test_app.dart';

void main() {
  Future<void> openRush(
    WidgetTester tester, {
    String route = AppRoutes.rush,
    String locale = 'en',
    Future<void> Function()? extra,
  }) => openShop(tester, route, locale: locale, extra: extra);

  void expectDelivery(String text) => expect(
    find.descendant(
      of: find.byKey(const ValueKey('delivery-date')),
      matching: find.text(text),
    ),
    findsOneWidget,
  );

  Color cellColor(WidgetTester tester, String date) =>
      tester.widget<Material>(find.byKey(ValueKey('cal-$date'))).color!;

  // ---------------------------------------------------------------------------
  group('season setup (S5-02)', () {
    testWidgets('the Rush tab starts empty and leads to setup', (tester) async {
      await openRush(tester);
      expect(find.text('Rush mode is off'), findsOneWidget);
      await tapKeyed(tester, 'rush-setup');
      expect(find.text('Kind of season'), findsOneWidget);
      // Sensible defaults.
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('season-capacity')),
            )
            .controller!
            .text,
        '20',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('season-name')))
            .controller!
            .text,
        'Eid-ul-Fitr',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets(
      'create a season: dates, capacity, days off, closed day, weights',
      (tester) async {
        await openRush(tester, route: AppRoutes.rushSetup());

        // Kind changes the suggested name.
        await tapKeyed(tester, 'season-kind');
        await tester.tap(find.text('Puja').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('season-name')))
              .controller!
              .text,
          'Puja',
        );
        await tapKeyed(tester, 'season-kind');
        await tester.tap(find.text('Eid-ul-Fitr').last);
        await tester.pumpAndSettle();

        // Deadline: default is 30 days out (9 April); pick the 15th.
        await tapKeyed(tester, 'season-target');
        await tester.tap(find.text('15'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('15 Apr 2026'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('season-capacity')),
          '12.5',
        );
        await tapKeyed(tester, 'day-5'); // Friday off
        await tapKeyed(tester, 'closed-add');
        await tester.tap(find.text('16'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('closed-2026-04-16')), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('weight-panjabi')),
          '1.2',
        );
        await tapKeyed(tester, 'season-save');

        final saved = (await query(
          tester,
          () => shopDb.select(shopDb.season).get(),
        )).single;
        expect(saved.name, 'Eid-ul-Fitr');
        expect(saved.kind, 'eid_fitr');
        expect(saved.targetDate, '2026-04-15');
        expect(saved.dailyCapacity, 1250);
        expect(WorkingDays.isWorking(saved.workingDaysMask, 5), isFalse);
        expect(WorkingDays.isWorking(saved.workingDaysMask, 6), isTrue);
        expect(saved.closedDatesJson, contains('2026-04-16'));
        final panjabi = (await query(
          tester,
          () => shopDb.select(shopDb.garmentType).get(),
        )).firstWhere((g) => g.id == panjabiId);
        expect(panjabi.workUnits, 120);

        // Back on the Rush tab with the countdown.
        expect(find.text('Rush mode is off'), findsNothing);
        await shutDown(tester, shopDb);
      },
    );

    testWidgets('capacity and weights are validated', (tester) async {
      await openRush(tester, route: AppRoutes.rushSetup());
      await tester.enterText(
        find.byKey(const ValueKey('season-capacity')),
        'lots',
      );
      await tapKeyed(tester, 'season-save');
      expect(
        find.text('Enter garments per day, for example 20'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('season-capacity')),
        '20',
      );
      await tester.enterText(find.byKey(const ValueKey('weight-shirt')), '0');
      await tapKeyed(tester, 'season-save');
      expect(find.text('Enter a number such as 1 or 0.6'), findsOneWidget);
      expect(
        await query(tester, () => shopDb.select(shopDb.season).get()),
        isEmpty,
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('edit an existing season, then remove it', (tester) async {
      await openRush(tester, extra: seedSeason);
      expect(find.byKey(const ValueKey('rush-days-left')), findsOneWidget);
      await tapKeyed(tester, 'rush-edit');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('season-capacity')),
            )
            .controller!
            .text,
        '10',
      );
      await tester.enterText(
        find.byKey(const ValueKey('season-capacity')),
        '15',
      );
      await tapKeyed(tester, 'season-save');
      final rows = await query(
        tester,
        () => shopDb.select(shopDb.season).get(),
      );
      expect(rows, hasLength(1), reason: 'updated in place');
      expect(rows.single.dailyCapacity, 1500);

      await tapKeyed(tester, 'rush-edit');
      await tapKeyed(tester, 'season-remove');
      expect(find.text('Rush mode is off'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('weights are shown as garments, e.g. a blouse is 0.6', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushSetup());
      String weight(String key) => tester
          .widget<TextFormField>(find.byKey(ValueKey('weight-$key')))
          .controller!
          .text;
      expect(weight('panjabi'), '1');
      expect(weight('blouse'), '0.6');
      expect(weight('blazer'), '2.5');
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('countdown board (S5-05)', () {
    testWidgets('days left, room, and garments by stage', (tester) async {
      await openRush(
        tester,
        extra: () async {
          await seedSeason();
          await seedOrder(delivery: '2026-03-15', qty: 3); // 3 Panjabi
          await seedOrder(
            delivery: '2026-03-16',
            qty: 2,
            garment: 'shirt',
          ); // 2 shirts
          await seedOrder(delivery: '2026-03-17'); // 1 Panjabi
          await orders.setAllItemsStatus('o-1', OrderStatus.cut);
          await seedOrder(
            delivery: '2026-04-30',
          ); // after Eid: not in the board
        },
      );
      expect(textOf(tester, 'rush-days-left'), '10 days left');
      expect(find.text('Ready by 20 Mar 2026'), findsOneWidget);
      // 11 days × 10 = 110 garments of capacity; 5.6 promised (80 per shirt).
      expect(textOf(tester, 'rush-room'), 'Room for about 104 more garments');
      expect(find.byKey(const ValueKey('stage-received')), findsOneWidget);
      expect(
        tester.widget<Chip>(find.byKey(const ValueKey('stage-cut'))).label
            is Text,
        isTrue,
      );
      final cut = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('stage-cut')),
          matching: find.byType(Text),
        ),
      );
      expect(cut.data, contains('3'));
      expect(textOf(tester, 'rush-not-cut'), '3 garments not yet cut');
      await shutDown(tester, shopDb);
    });

    testWidgets('a full plan says to stop taking orders', (tester) async {
      await openRush(
        tester,
        extra: () async {
          await seedSeason(target: '2026-03-11', capacity: 1000); // 2 days = 20
          await seedOrder(delivery: '2026-03-11', qty: 20);
        },
      );
      expect(
        textOf(tester, 'rush-room'),
        'Fully booked: stop taking orders for this date',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('an overbooked plan shows by how much', (tester) async {
      await openRush(
        tester,
        extra: () async {
          await seedSeason(target: '2026-03-11', capacity: 1000);
          await seedOrder(delivery: '2026-03-11', qty: 26);
        },
      );
      expect(textOf(tester, 'rush-room'), 'Over capacity by about 6 garments');
      await shutDown(tester, shopDb);
    });

    testWidgets('progress frees capacity: ready garments no longer count', (
      tester,
    ) async {
      await openRush(
        tester,
        extra: () async {
          await seedSeason(target: '2026-03-11', capacity: 1000);
          await seedOrder(delivery: '2026-03-11', qty: 26);
        },
      );
      expect(textOf(tester, 'rush-room'), contains('Over capacity'));
      await tester.runAsync(
        () => orders.setAllItemsStatus('o-1', OrderStatus.ready),
      );
      await tester.pumpAndSettle();
      expect(textOf(tester, 'rush-room'), 'Room for about 20 more garments');
      await shutDown(tester, shopDb);
    });

    testWidgets('on the last day it says so', (tester) async {
      await openRush(tester, extra: () => seedSeason(target: '2026-03-10'));
      expect(textOf(tester, 'rush-days-left'), 'Today is the day');
      await shutDown(tester, shopDb);
    });

    testWidgets('a season that has passed is not shown', (tester) async {
      await openRush(tester, extra: () => seedSeason(target: '2026-03-01'));
      expect(find.text('Rush mode is off'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla digits and labels', (tester) async {
      await openRush(
        tester,
        locale: 'bn',
        extra: () async {
          await seedSeason();
          await seedOrder(delivery: '2026-03-15', qty: 3);
        },
      );
      expect(textOf(tester, 'rush-days-left'), contains('১০'));
      expect(textOf(tester, 'rush-room'), contains('১০'));
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('load calendar (S5-06)', () {
    Future<void> seedLoad() async {
      // 10 garments a day, 5 days: ready by the 14th.
      await seedSeason(target: '2026-03-14');
      await seedOrder(delivery: '2026-03-12', qty: 28); // 28 of 30: nearly full
      await seedOrder(delivery: '2026-03-14', qty: 40); // 68 of 50: overbooked
    }

    testWidgets('days are coloured by how full the plan is', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      final light = Brightness.light;
      expect(
        cellColor(tester, '2026-03-10'),
        levelColor(LoadLevel.green, light),
      );
      expect(
        cellColor(tester, '2026-03-11'),
        levelColor(LoadLevel.green, light),
      );
      expect(
        cellColor(tester, '2026-03-12'),
        levelColor(LoadLevel.amber, light),
      );
      expect(
        cellColor(tester, '2026-03-13'),
        levelColor(LoadLevel.green, light),
      );
      expect(cellColor(tester, '2026-03-14'), levelColor(LoadLevel.red, light));
      await shutDown(tester, shopDb);
    });

    testWidgets('each day shows the garments due', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      expect(textOf(tester, 'cal-due-2026-03-12'), '28');
      expect(textOf(tester, 'cal-due-2026-03-14'), '40');
      expect(find.byKey(const ValueKey('cal-due-2026-03-11')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('only today up to the deadline is drawn', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      expect(find.byKey(const ValueKey('cal-2026-03-09')), findsNothing);
      expect(find.byKey(const ValueKey('cal-2026-03-15')), findsNothing);
      expect(find.text('March 2026'), findsOneWidget);
      expect(find.text('Room to spare'), findsOneWidget);
      expect(find.text('Overbooked'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('tap a day: spare room and the orders due', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      await tapKeyed(tester, 'cal-2026-03-14');
      expect(textOf(tester, 'day-sheet-title'), 'Due 14 Mar 2026');
      expect(textOf(tester, 'day-sheet-spare'), 'Over by 18 garments');
      expect(find.byKey(const ValueKey('order-o-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-o-1')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('a quiet day says so and shows its spare room', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      await tapKeyed(tester, 'cal-2026-03-11');
      expect(textOf(tester, 'day-sheet-spare'), 'Spare: 20 garments');
      expect(find.text('No orders due this day'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('days off are marked closed and add no capacity', (
      tester,
    ) async {
      await openRush(
        tester,
        route: AppRoutes.rushCalendar,
        extra: () async {
          // Friday 13 March off.
          await seedSeason(
            target: '2026-03-14',
            mask: WorkingDays.toggle(WorkingDays.all, 5),
          );
        },
      );
      final closed = cellColor(tester, '2026-03-13');
      expect(closed, isNot(levelColor(LoadLevel.green, Brightness.light)));
      await tapKeyed(tester, 'cal-2026-03-13');
      expect(textOf(tester, 'day-sheet-spare'), startsWith('Closed'));
      await shutDown(tester, shopDb);
    });

    testWidgets('moving garments along updates the colours live', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushCalendar, extra: seedLoad);
      expect(
        cellColor(tester, '2026-03-14'),
        levelColor(LoadLevel.red, Brightness.light),
      );
      await tester.runAsync(
        () => orders.setAllItemsStatus('o-4', OrderStatus.ready),
      );
      await tester.pumpAndSettle();
      expect(
        cellColor(tester, '2026-03-14'),
        isNot(levelColor(LoadLevel.red, Brightness.light)),
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('without a season it explains itself', (tester) async {
      await openRush(tester, route: AppRoutes.rushCalendar);
      expect(find.text('Rush mode is off'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a 60-day season with 300 orders draws without overflow', (
      tester,
    ) async {
      await openRush(
        tester,
        route: AppRoutes.rushCalendar,
        extra: () async {
          await seedSeason(target: '2026-05-08', capacity: 3000);
          await shopDb.transaction(() async {
            for (var i = 0; i < 300; i++) {
              final day = (i % 58) + 10;
              final date = day <= 31
                  ? '2026-03-${day.toString().padLeft(2, '0')}'
                  : '2026-04-${(day - 31).toString().padLeft(2, '0')}';
              await shopDb.customStatement(
                'INSERT INTO customer_order (id, number, customer_id, delivery_date, '
                "discount, urgent, status, created_at, updated_at) VALUES ('b$i', ${500 + i}, 'c1', "
                "'$date', 0, 0, 'received', 1, 1)",
              );
              await shopDb.customStatement(
                'INSERT INTO order_item (id, order_id, garment_type_id, qty, price, status, '
                "status_changed_at, work_units) VALUES ('bi$i', 'b$i', '$panjabiId', 1, 100, "
                "'received', 1, 100)",
              );
            }
          });
        },
      );
      expect(find.byKey(const ValueKey('cal-2026-03-10')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('batch lists (S5-08)', () {
    Future<void> seedBatches() async {
      await seedSeason();
      await seedOrder(delivery: '2026-03-15', qty: 3); // o-1: 3 Panjabi
      await seedOrder(
        delivery: '2026-03-16',
        qty: 2,
        garment: 'shirt',
      ); // o-4: 2 shirts
      await seedOrder(delivery: '2026-03-30', qty: 4); // o-7: later
      await seedOrder(delivery: '2026-03-17'); // o-10: 1 Panjabi
      await orders.setAllItemsStatus('o-10', OrderStatus.cut);
    }

    testWidgets('garments grouped by stage and type', (tester) async {
      await openRush(tester, route: AppRoutes.rushBatches, extra: seedBatches);
      expect(textOf(tester, 'batch-stage-received'), 'Received · 9');
      expect(textOf(tester, 'batch-stage-cut'), 'Cut · 1');
      expect(
        find.byKey(const ValueKey('batch-received-panjabi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch-received-shirt')),
        findsOneWidget,
      );
      expect(find.text('7 garments'), findsOneWidget); // 3 + 4 Panjabi
      expect(find.text('2 garments'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('limit to orders due before the deadline', (tester) async {
      await openRush(tester, route: AppRoutes.rushBatches, extra: seedBatches);
      await tapKeyed(tester, 'batch-only-target');
      expect(textOf(tester, 'batch-stage-received'), 'Received · 5');
      expect(find.text('3 garments'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('move a whole group to the next stage in one tap', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushBatches, extra: seedBatches);
      await tapKeyed(tester, 'batch-move-received-panjabi');
      expect(find.text('Move 7 Panjabi / Kurta to Cut?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('batch-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2 moved'), findsOneWidget, reason: 'two order lines');
      await tester.pumpAndSettle();
      expect(textOf(tester, 'batch-stage-cut'), 'Cut · 8');
      expect(textOf(tester, 'batch-stage-received'), 'Received · 2');
      final o1 = await detail(tester, 'o-1');
      expect(o1.order.status, OrderStatus.cut);
      await shutDown(tester, shopDb);
    });

    testWidgets('a batch limited by date only moves those garments', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushBatches, extra: seedBatches);
      await tapKeyed(tester, 'batch-only-target');
      await tapKeyed(tester, 'batch-move-received-panjabi');
      await tester.tap(find.byKey(const ValueKey('batch-confirm')));
      await tester.pumpAndSettle();
      expect((await detail(tester, 'o-1')).order.status, OrderStatus.cut);
      expect((await detail(tester, 'o-7')).order.status, OrderStatus.received);
      await shutDown(tester, shopDb);
    });

    testWidgets('cancelling the confirmation moves nothing', (tester) async {
      await openRush(tester, route: AppRoutes.rushBatches, extra: seedBatches);
      await tapKeyed(tester, 'batch-move-received-shirt');
      await tapText(tester, 'Cancel');
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.received);
      await shutDown(tester, shopDb);
    });

    testWidgets('ready garments have no move button; empty shop explains', (
      tester,
    ) async {
      await openRush(
        tester,
        route: AppRoutes.rushBatches,
        extra: () async {
          await seedOrder(advance: 1200);
          await orders.setAllItemsStatus('o-1', OrderStatus.ready);
        },
      );
      expect(find.byKey(const ValueKey('batch-stage-ready')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('batch-move-ready-panjabi')),
        findsNothing,
      );
      await shutDown(tester, shopDb);

      await openRush(tester, route: AppRoutes.rushBatches);
      expect(find.text('Nothing in progress'), findsOneWidget);
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('rush list (S5-09)', () {
    Future<void> seedList() async {
      await seedSeason();
      await seedOrder(delivery: '2026-03-18'); // o-1 Rahim
      await seedOrder(
        customer: 'c2',
        delivery: '2026-03-12',
        garment: 'shirt',
        price: 500,
        advance: 0,
      ); // o-4 Karim
      await seedOrder(delivery: '2026-03-30'); // o-7: after Eid
    }

    testWidgets('one line per order, soonest first, up to the deadline', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushList, extra: seedList);
      expect(find.byKey(const ValueKey('rush-row-o-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('rush-row-o-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('rush-row-o-7')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('rush-row-o-4'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('rush-row-o-1'))).dy,
        ),
      );
      expect(find.text('Karim Hossain'), findsOneWidget);
      expect(
        find.text('Swipe right to move an order to its next stage'),
        findsOneWidget,
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('swipe right moves an order to its next stage', (tester) async {
      await openRush(tester, route: AppRoutes.rushList, extra: seedList);
      await tester.drag(
        find.byKey(const ValueKey('rush-row-o-4')),
        const Offset(400, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Order #2 is now Cut'), findsOneWidget);
      await tester.pumpAndSettle();
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.cut);
      // The row stays; it just shows the new stage.
      expect(find.byKey(const ValueKey('rush-row-o-4')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('swiping again keeps walking the pipeline up to ready', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushList, extra: seedList);
      for (var i = 0; i < 3; i++) {
        await tester.drag(
          find.byKey(const ValueKey('rush-row-o-4')),
          const Offset(400, 0),
        );
        await tester.pumpAndSettle();
      }
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.finishing);
      await tester.drag(
        find.byKey(const ValueKey('rush-row-o-4')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.ready);
      // Ready orders cannot be swiped further: hand-over has its own check.
      await tester.drag(
        find.byKey(const ValueKey('rush-row-o-4')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.ready);
      await shutDown(tester, shopDb);
    });

    testWidgets('swiping left does nothing; tapping opens the order', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.rushList, extra: seedList);
      await tester.drag(
        find.byKey(const ValueKey('rush-row-o-4')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect((await detail(tester, 'o-4')).order.status, OrderStatus.received);
      await tester.tap(find.byKey(const ValueKey('rush-row-o-4')));
      await tester.pumpAndSettle();
      expect(find.text('Order #2'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('delivered orders drop off; empty list explains', (
      tester,
    ) async {
      await openRush(
        tester,
        route: AppRoutes.rushList,
        extra: () async {
          await seedSeason();
          await seedOrder(advance: 1200);
          await orders.deliverAll('o-1');
        },
      );
      expect(find.text('No open orders'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('without a season every open order is listed', (tester) async {
      await openRush(
        tester,
        route: AppRoutes.rushList,
        extra: () async {
          await seedOrder(delivery: '2026-03-30');
        },
      );
      expect(find.byKey(const ValueKey('rush-row-o-1')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('large text for a glance, in Bangla too', (tester) async {
      await openRush(
        tester,
        route: AppRoutes.rushList,
        locale: 'bn',
        extra: seedList,
      );
      expect(find.text('#১'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shutDown(tester, shopDb);
    });
  });

  // ---------------------------------------------------------------------------
  group('safe date in the wizard (S5-07)', () {
    /// 10 garments a day to the 14th; 30 already promised for the 12th, which
    /// fills everything up to then. The 13th is the first day with room.
    Future<void> seedBusy() async {
      await seedSeason(target: '2026-03-14');
      await seedOrder(delivery: '2026-03-12', qty: 30);
    }

    Future<void> toDeliveryStep(
      WidgetTester tester, {
      String garment = 'panjabi',
    }) async {
      await tapKeyed(tester, 'add-$garment');
      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'wizard-next');
      await tester.enterText(find.byKey(ValueKey('price-$garment')), '900');
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
    }

    testWidgets('suggests and pre-fills the earliest safe date', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'), extra: seedBusy);
      await toDeliveryStep(tester);
      expect(
        textOf(tester, 'safe-date-title'),
        'Earliest safe date: 13 Mar 2026',
      );
      expect(textOf(tester, 'safe-date-status'), 'This date has room.');

      await shutDown(tester, shopDb);
    });

    testWidgets('choosing a full date warns and can be fixed with one tap', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'), extra: seedBusy);
      await toDeliveryStep(tester);
      await tapKeyed(tester, 'delivery-date');
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'safe-date-status'), 'This date is already full.');
      expect(find.byKey(const ValueKey('safe-date-use')), findsOneWidget);
      await tapKeyed(tester, 'safe-date-use');
      expect(textOf(tester, 'safe-date-status'), 'This date has room.');
      expect(find.byKey(const ValueKey('safe-date-use')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('saving a full date needs one extra tap and tags the order', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'), extra: seedBusy);
      await toDeliveryStep(tester);
      await tapKeyed(tester, 'delivery-date');
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tapKeyed(tester, 'wizard-next');
      expect(find.text('This date is already full'), findsOneWidget);
      expect(
        find.textContaining('Eid-ul-Fitr is booked up to this date'),
        findsOneWidget,
      );
      // Backing out saves nothing.
      await tapText(tester, 'Go back');
      expect(
        await query(tester, () => shopDb.select(shopDb.customerOrder).get()),
        hasLength(1),
      );

      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'date-full-take');
      final all = await query(
        tester,
        () => shopDb.select(shopDb.customerOrder).get(),
      );
      expect(all, hasLength(2));
      final created = all.firstWhere((o) => o.number == 2);
      expect(created.overbooked, isTrue);
      expect(created.seasonId, 'season1');
      expect(find.byKey(const ValueKey('overbooked-chip')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a safe date saves straight away and is linked to the season', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'), extra: seedBusy);
      await toDeliveryStep(tester);
      await tapKeyed(tester, 'wizard-next');
      expect(find.text('This date is already full'), findsNothing);
      final created = (await query(
        tester,
        () => shopDb.select(shopDb.customerOrder).get(),
      )).firstWhere((o) => o.number == 2);
      expect(created.overbooked, isFalse);
      expect(created.seasonId, 'season1');
      expect(created.deliveryDate, '2026-03-13');
      expect(find.byKey(const ValueKey('overbooked-chip')), findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('the order remembers each garment weight', (tester) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'), extra: seedBusy);
      await toDeliveryStep(tester, garment: 'shirt');
      await tapKeyed(tester, 'wizard-next');
      final items = await query(
        tester,
        () => shopDb.select(shopDb.orderItem).get(),
      );
      expect(items.where((i) => i.workUnits == 80), hasLength(1));
      await shutDown(tester, shopDb);
    });

    testWidgets('a heavier order needs a later date', (tester) async {
      await openRush(
        tester,
        route: AppRoutes.newOrder('c1'),
        extra: () async {
          await seedSeason(target: '2026-03-14');
          // 19 garments due on the 11th: 20 can be made by then, so only one
          // more garment fits there.
          await seedOrder(delivery: '2026-03-11', qty: 19);
        },
      );
      await tapKeyed(tester, 'add-panjabi');
      await tapKeyed(tester, 'add-panjabi'); // two Panjabi on separate lines
      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'wizard-next');
      await tester.enterText(
        find.byKey(const ValueKey('price-panjabi')),
        '900',
      );
      // The second line is further down the (lazily built) list.
      await reveal(tester, find.byKey(const ValueKey('price-panjabi-2')));
      await tester.enterText(
        find.byKey(const ValueKey('price-panjabi-2')),
        '900',
      );
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(
        textOf(tester, 'safe-date-title'),
        'Earliest safe date: 12 Mar 2026',
      );
      expectDelivery('12 Mar 2026');
      await shutDown(tester, shopDb);
    });

    testWidgets('a single garment still fits on the 11th', (tester) async {
      await openRush(
        tester,
        route: AppRoutes.newOrder('c1'),
        extra: () async {
          await seedSeason(target: '2026-03-14');
          await seedOrder(delivery: '2026-03-11', qty: 19);
        },
      );
      await tapKeyed(tester, 'add-panjabi');
      await tapKeyed(tester, 'wizard-next');
      await tapKeyed(tester, 'wizard-next');
      await tester.enterText(
        find.byKey(const ValueKey('price-panjabi')),
        '900',
      );
      await tester.pump();
      await tapKeyed(tester, 'wizard-next');
      expect(
        textOf(tester, 'safe-date-title'),
        'Earliest safe date: 11 Mar 2026',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('no safe date before the deadline is explained', (
      tester,
    ) async {
      await openRush(
        tester,
        route: AppRoutes.newOrder('c1'),
        extra: () async {
          await seedSeason(
            target: '2026-03-11',
            capacity: 500,
          ); // 10 garments total
          await seedOrder(delivery: '2026-03-11', qty: 10);
        },
      );
      await toDeliveryStep(tester);
      expect(
        textOf(tester, 'safe-date-title'),
        'No safe date before Eid-ul-Fitr. You can still take the order.',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('without a season the wizard behaves as before', (
      tester,
    ) async {
      await openRush(tester, route: AppRoutes.newOrder('c1'));
      await toDeliveryStep(tester);
      expect(find.byKey(const ValueKey('safe-date-card')), findsNothing);
      expectDelivery('17 Mar 2026');
      await tapKeyed(tester, 'wizard-next');
      final created = (await query(
        tester,
        () => shopDb.select(shopDb.customerOrder).get(),
      )).single;
      expect(created.seasonId, isNull);
      expect(created.overbooked, isFalse);
      await shutDown(tester, shopDb);
    });

    testWidgets(
      'a date the tailor picked is not overwritten by the suggestion',
      (tester) async {
        await openRush(
          tester,
          route: AppRoutes.newOrder('c1'),
          extra: seedBusy,
        );
        await tapKeyed(tester, 'add-panjabi');
        await tapKeyed(tester, 'wizard-next');
        await tapKeyed(tester, 'wizard-next');
        await tester.enterText(
          find.byKey(const ValueKey('price-panjabi')),
          '900',
        );
        await tester.pump();
        await tapKeyed(tester, 'wizard-next');
        await tapKeyed(tester, 'delivery-date');
        await tester.tap(find.text('14'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // Go back and forth: the chosen 14th stays.
        await tapKeyed(tester, 'wizard-back');
        await tapKeyed(tester, 'wizard-next');
        expectDelivery('14 Mar 2026');
        await shutDown(tester, shopDb);
      },
    );
  });
}
