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
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/data/drift_rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

import '../../support/db_fixtures.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftRushRepository rush;
  late DriftOrderRepository orders;
  late String panjabi;
  late String pant;

  setUp(() async {
    db = memoryDb();
    final clock = FixedClock(DateTime(2026, 3, 10, 9));
    rush = DriftRushRepository(db);
    orders = DriftOrderRepository(db, clock, SequentialIdGenerator('o'));
    await DriftCustomerRepository(db).insert(
      Customer(
        id: 'c1',
        name: 'Rahim',
        createdAt: clock.now(),
        updatedAt: clock.now(),
      ),
    );
    panjabi = BuiltInTemplates.byKey('panjabi').id;
    pant = BuiltInTemplates.byKey('pant').id;
  });
  tearDown(() => db.close());

  Season season({
    String id = 's1',
    String target = '2026-03-20',
    bool active = true,
  }) => Season(
    id: id,
    name: 'Eid',
    kind: SeasonKind.eidFitr,
    targetDate: target,
    dailyCapacity: 2000,
    workingDaysMask: WorkingDays.toggle(WorkingDays.all, 5),
    closedDates: {'2026-03-18', '2026-03-17'},
    active: active,
  );

  Future<OrderDetail> make({
    String garment = 'panjabi',
    int qty = 1,
    String delivery = '2026-03-15',
  }) => orders.create(
    NewOrder(
      customerId: 'c1',
      deliveryDate: delivery,
      items: [
        NewOrderItem(
          garmentTypeId: garment == 'panjabi' ? panjabi : pant,
          price: const Money.taka(1000),
          qty: qty,
          workUnits: garment == 'panjabi' ? 100 : 80,
        ),
      ],
    ),
  );

  group('seasons (S5-01)', () {
    test('save and read back every field', () async {
      await rush.save(season());
      final read = (await rush.activeSeason('2026-03-10'))!;
      expect(read.id, 's1');
      expect(read.kind, SeasonKind.eidFitr);
      expect(read.targetDate, '2026-03-20');
      expect(read.dailyCapacity, 2000);
      expect(WorkingDays.isWorking(read.workingDaysMask, 5), isFalse);
      expect(WorkingDays.isWorking(read.workingDaysMask, 6), isTrue);
      expect(read.closedDates, {'2026-03-17', '2026-03-18'});
    });

    test('saving again updates in place', () async {
      await rush.save(season());
      await rush.save(season().copyWith(dailyCapacity: 3000, name: 'Eid 2'));
      final all = await rush.watchSeasons().first;
      expect(all, hasLength(1));
      expect(all.single.dailyCapacity, 3000);
      expect(all.single.name, 'Eid 2');
    });

    test('the active season is the soonest one not yet passed', () async {
      await rush.save(season(id: 'past', target: '2026-03-01'));
      await rush.save(season(id: 'far', target: '2026-06-01'));
      await rush.save(season(id: 'near', target: '2026-03-25'));
      await rush.save(season(id: 'off', target: '2026-03-12', active: false));
      expect((await rush.activeSeason('2026-03-10'))!.id, 'near');
      expect((await rush.activeSeason('2026-03-26'))!.id, 'far');
      expect(await rush.activeSeason('2026-07-01'), isNull);
    });

    test('the target day itself still counts as active', () async {
      await rush.save(season(target: '2026-03-10'));
      expect(await rush.activeSeason('2026-03-10'), isNotNull);
      expect(await rush.activeSeason('2026-03-11'), isNull);
    });

    test('deactivate hides a season but keeps it', () async {
      await rush.save(season());
      await rush.deactivate('s1');
      expect(await rush.activeSeason('2026-03-10'), isNull);
      expect(await rush.watchSeasons().first, isEmpty);
      expect(await db.select(db.season).get(), hasLength(1));
    });

    test('streams update live', () async {
      final seen = <String?>[];
      final sub = rush
          .watchActiveSeason('2026-03-10')
          .listen((s) => seen.add(s?.id));
      await pumpEventQueue();
      await rush.save(season());
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [null, 's1']);
    });
  });

  group('garment weights (S5-01)', () {
    test('built-in garments start with standard weights', () async {
      final garments = await DriftMeasurementRepository(
        db,
        FixedClock(DateTime(2026, 3, 10)),
        SequentialIdGenerator('m'),
      ).garments();
      final byKey = {for (final g in garments) g.key: g.workUnits};
      expect(byKey['panjabi'], 100);
      expect(byKey['blazer'], 250);
      expect(byKey['blouse'], 60);
      expect(byKey['pajama'], 50);
    });

    test('weights can be changed and must be positive', () async {
      await rush.setGarmentWeight(panjabi, 120);
      final row = await (db.select(
        db.garmentType,
      )..where((t) => t.id.equals(panjabi))).getSingle();
      expect(row.workUnits, 120);
      expect(() => rush.setGarmentWeight(panjabi, 0), throwsArgumentError);
    });

    test('seeding again keeps an edited weight', () async {
      await rush.setGarmentWeight(panjabi, 130);
      await db.customStatement('SELECT 1'); // no-op to keep the db open
      final row = await (db.select(
        db.garmentType,
      )..where((t) => t.id.equals(panjabi))).getSingle();
      expect(row.workUnits, 130);
    });
  });

  group('open items and stage counts (S5-05, S5-08)', () {
    test('lists unfinished lines of open orders only', () async {
      final a = await make(qty: 3);
      final b = await make(garment: 'pant');
      final c = await make();
      await orders.cancel(
        c.order.id,
        reason: 'x',
        advance: CancelAdvance.keep,
        today: '2026-03-10',
      );
      await orders.setAllItemsStatus(b.order.id, OrderStatus.ready);
      await orders.deliverAll(b.order.id, dueConfirmed: true);

      final items = await rush.watchOpenItems().first;
      expect(items, hasLength(1));
      expect(items.single.orderId, a.order.id);
      expect(items.single.qty, 3);
      expect(items.single.units, 300);
      expect(items.single.status, OrderStatus.received);
      expect(items.single.remainingWork.units, 300);
    });

    test('remaining work shrinks as garments progress', () async {
      final a = await make(qty: 2);
      await orders.setAllItemsStatus(a.order.id, OrderStatus.stitching);
      var item = (await rush.watchOpenItems().first).single;
      expect(item.remainingWork.units, 80); // 40% of 200
      await orders.setAllItemsStatus(a.order.id, OrderStatus.ready);
      item = (await rush.watchOpenItems().first).single;
      expect(item.remainingWork.units, 0);
    });

    test('counts garments per type and stage, optionally by date', () async {
      final a = await make(qty: 3, delivery: '2026-03-12');
      await make(qty: 2, delivery: '2026-03-14');
      await make(garment: 'pant', qty: 4, delivery: '2026-03-14');
      await orders.setAllItemsStatus(a.order.id, OrderStatus.cut);

      Map<String, int> asMap(List<StageCount> counts) => {
        for (final c in counts)
          '${c.garmentTypeId == panjabi ? 'panjabi' : 'pant'}:${c.status.name}':
              c.garments,
      };
      final all = await rush.watchStageCounts().first;
      expect(asMap(all), {
        'panjabi:cut': 3,
        'panjabi:received': 2,
        'pant:received': 4,
      });
      final early = await rush.watchStageCounts(toDate: '2026-03-12').first;
      expect(asMap(early), {'panjabi:cut': 3});
    });

    test('item ids for a batch come back in delivery order', () async {
      final late = await make(delivery: '2026-03-20');
      final early = await make(delivery: '2026-03-11');
      await make(garment: 'pant');
      final ids = await rush.itemIds(panjabi, OrderStatus.received);
      expect(ids, [early.items.single.id, late.items.single.id]);
      expect(
        await rush.itemIds(panjabi, OrderStatus.received, toDate: '2026-03-11'),
        [early.items.single.id],
      );
      expect(await rush.itemIds(panjabi, OrderStatus.cut), isEmpty);
    });
  });

  group('batch moves (S5-08)', () {
    test('moves every listed line and rolls each order up once', () async {
      final a = await make(delivery: '2026-03-12');
      final b = await make(delivery: '2026-03-13');
      final moved = await orders.moveItems([
        a.items.single.id,
        b.items.single.id,
      ], OrderStatus.cut);
      expect(moved, 2);
      expect((await orders.detail(a.order.id))!.order.status, OrderStatus.cut);
      expect((await orders.detail(b.order.id))!.order.status, OrderStatus.cut);
      final log = await orders.watchChangeLog(a.order.id).first;
      expect(log.first.action, 'item_status');
    });

    test(
      'skips lines that cannot move, cancelled orders and unknown ids',
      () async {
        final a = await make();
        final ahead = await make();
        final cancelled = await make();
        await orders.setAllItemsStatus(ahead.order.id, OrderStatus.finishing);
        await orders.cancel(
          cancelled.order.id,
          reason: 'x',
          advance: CancelAdvance.keep,
          today: '2026-03-10',
        );
        final moved = await orders.moveItems([
          a.items.single.id,
          ahead.items.single.id, // finishing → cut is two steps back
          cancelled.items.single.id,
          'nope',
        ], OrderStatus.cut);
        expect(moved, 1);
        expect(
          (await orders.detail(ahead.order.id))!.order.status,
          OrderStatus.finishing,
        );
        expect(
          (await orders.detail(cancelled.order.id))!.order.status,
          OrderStatus.received,
        );
      },
    );

    test('delivering through a batch is refused', () async {
      final a = await make();
      expect(
        () => orders.moveItems([a.items.single.id], OrderStatus.delivered),
        throwsArgumentError,
      );
    });
  });

  group('advanceOrder (S5-09)', () {
    test('lifts only the lagging garments to the next stage', () async {
      final d = await orders.create(
        NewOrder(
          customerId: 'c1',
          deliveryDate: '2026-03-15',
          items: [
            NewOrderItem(garmentTypeId: panjabi, price: const Money.taka(1)),
            NewOrderItem(garmentTypeId: pant, price: const Money.taka(1)),
          ],
        ),
      );
      await orders.setItemStatus(d.items[1].id, OrderStatus.stitching);
      // Order stage is the slowest item: received → next is cut.
      expect(await orders.advanceOrder(d.order.id), OrderStatus.cut);
      final after = (await orders.detail(d.order.id))!;
      expect(after.items.map((i) => i.status), [
        OrderStatus.cut,
        OrderStatus.stitching,
      ]);
      expect(after.order.status, OrderStatus.cut);
    });

    test(
      'walks to ready and then stops (delivery has its own guard)',
      () async {
        final d = await make();
        final seen = <OrderStatus?>[];
        for (var i = 0; i < 6; i++) {
          seen.add(await orders.advanceOrder(d.order.id));
        }
        expect(seen, [
          OrderStatus.cut,
          OrderStatus.stitching,
          OrderStatus.finishing,
          OrderStatus.ready,
          null,
          null,
        ]);
        expect(
          (await orders.detail(d.order.id))!.order.status,
          OrderStatus.ready,
        );
      },
    );

    test('cancelled and unknown orders do nothing', () async {
      final d = await make();
      await orders.cancel(
        d.order.id,
        reason: 'x',
        advance: CancelAdvance.keep,
        today: '2026-03-10',
      );
      expect(await orders.advanceOrder(d.order.id), isNull);
      expect(await orders.advanceOrder('nope'), isNull);
    });
  });

  group('orders keep their planning flags (S5-07)', () {
    test('season id and overbooked are stored', () async {
      final d = await orders.create(
        NewOrder(
          customerId: 'c1',
          deliveryDate: '2026-03-15',
          seasonId: 's1',
          overbooked: true,
          items: [
            NewOrderItem(garmentTypeId: panjabi, price: const Money.taka(1)),
          ],
        ),
      );
      expect(d.order.seasonId, 's1');
      expect(d.order.overbooked, isTrue);
      final plain = await make();
      expect(plain.order.seasonId, isNull);
      expect(plain.order.overbooked, isFalse);
    });
  });

  test('migration to v5 adds seasons, weights and order flags', () async {
    final dir = Directory.systemTemp.createTempSync('tk_mig5');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v1.db');
    DbFixtures.writeV1File(file);
    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);

    // Old data is intact and the built-in garments got their weights.
    expect(
      (await upgraded.select(upgraded.appSetting).get()).single.value,
      'bn',
    );
    final weights = {
      for (final g in await upgraded.select(upgraded.garmentType).get())
        g.key: g.workUnits,
    };
    expect(weights['panjabi'], 100);
    expect(weights['shirt'], 80);
    expect(weights['blazer'], 250);
    expect(weights['blouse'], 60);

    // New tables and columns exist and work.
    final repo = DriftRushRepository(upgraded);
    await repo.save(season());
    expect(await repo.activeSeason('2026-03-10'), isNotNull);
    final columns =
        (await upgraded
                .customSelect("PRAGMA table_info('customer_order')")
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(columns, containsAll(['season_id', 'overbooked']));
  });
}
