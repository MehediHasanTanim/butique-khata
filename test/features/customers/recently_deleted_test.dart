import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/features/customers/data/deleted_customers.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';

import '../../support/fakes.dart';
import '../../support/shop_fixture.dart';
import '../../support/test_app.dart';

void main() {
  final now = DateTime(2026, 3, 10, 10);

  Customer person(String id, String name) =>
      Customer(id: id, name: name, createdAt: now, updatedAt: now);

  DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  group('purge rules (S6-06)', () {
    late AppDatabase db;
    late DriftCustomerRepository customers;
    late DeletedCustomerRepository deleted;

    setUp(() async {
      env = TestEnv();
      addTearDown(env.dispose);
      db = memoryDb();
      customers = DriftCustomerRepository(db);
      deleted = DeletedCustomerRepository(db);
      await seed(db); // c1 has measurements, c2 has nothing
    });
    tearDown(() => db.close());

    Future<List<String>> ids() async =>
        (await db.select(db.customer).get()).map((c) => c.id).toList()..sort();

    test('a customer with no history is removed after 30 days', () async {
      await customers.softDelete('c2', daysAgo(31));
      expect(await deleted.purgeExpired(now), 1);
      expect(await ids(), ['c1']);
    });

    test('and not a day earlier', () async {
      await customers.softDelete('c2', daysAgo(29));
      expect(await deleted.purgeExpired(now), 0);
      expect(await ids(), ['c1', 'c2']);
    });

    test('measurement history is never purged', () async {
      await customers.softDelete('c1', daysAgo(400));
      expect(await deleted.purgeExpired(now), 0);
      expect(await ids(), ['c1', 'c2']);
      final sets = await db.select(db.measurementSet).get();
      expect(sets, isNotEmpty);
    });

    test('nor are customers with orders', () async {
      await customers.insert(person('c3', 'Salma'));
      await seedOrder(customer: 'c3');
      await customers.softDelete('c3', daysAgo(90));
      expect(await deleted.purgeExpired(now), 0);
      expect(await ids(), contains('c3'));
    });

    test('nor customers with a photo attached', () async {
      await db.customStatement(
        'INSERT INTO attachment (id, owner_type, owner_id, path, created_at) '
        "VALUES ('a1', 'customer', 'c2', 'p.jpg', 0)",
      );
      await customers.softDelete('c2', daysAgo(90));
      expect(await deleted.purgeExpired(now), 0);
    });

    test('active customers are never touched', () async {
      expect(await deleted.purgeExpired(now), 0);
      expect(await ids(), ['c1', 'c2']);
    });

    test('purging also clears the search index', () async {
      await customers.softDelete('c2', daysAgo(31));
      await deleted.purgeExpired(now);
      final hits = await db
          .customSelect(
            "SELECT rowid FROM customer_fts WHERE customer_fts MATCH 'karim*'",
          )
          .get();
      expect(hits, isEmpty);
    });

    test('lists what was removed, newest first, with days left', () async {
      await customers.insert(person('c3', 'Salma'));
      await customers.softDelete('c2', daysAgo(10));
      await customers.softDelete('c3', daysAgo(2));
      await customers.softDelete('c1', daysAgo(5));
      final list = await deleted.watchDeleted().first;
      expect(list.map((c) => c.id), ['c3', 'c1', 'c2']);
      expect(list.map((c) => c.hasHistory), [false, true, false]);
      expect(list[0].daysLeft(now), 28);
      expect(list[2].daysLeft(now), 20);
      expect(
        daysAgo(45).millisecondsSinceEpoch,
        lessThan(now.millisecondsSinceEpoch),
      );
    });

    test('restoring brings the customer back with everything', () async {
      await customers.softDelete('c1', daysAgo(3));
      expect(await customers.byId('c1'), isNull);
      await deleted.restore('c1', now);
      final back = await customers.byId('c1');
      expect(back!.name, 'Rahim Uddin');
      expect((await customers.search('rahim')).single.id, 'c1');
      expect(await deleted.watchDeleted().first, isEmpty);
    });
  });

  group('screen', () {
    testWidgets('lists deleted customers and restores one', (tester) async {
      await openShop(
        tester,
        AppRoutes.recentlyDeleted,
        extra: () async {
          final repo = DriftCustomerRepository(shopDb);
          await repo.softDelete('c1', DateTime(2026, 3, 8, 10));
          await repo.softDelete('c2', DateTime(2026, 2, 28, 10));
        },
      );
      expect(find.text('Recently deleted'), findsOneWidget);
      expect(find.text('Rahim Uddin'), findsOneWidget);
      expect(
        find.text('Has history, kept until you restore it'),
        findsOneWidget,
      );
      expect(find.text('20 days left'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('restore-c2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Karim Hossain restored'), findsOneWidget);
      expect(find.byKey(const ValueKey('deleted-c2')), findsNothing);
      final back = await tester.runAsync(
        () => DriftCustomerRepository(shopDb).byId('c2'),
      );
      expect(back, isNotNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('empty state', (tester) async {
      await openShop(tester, AppRoutes.recentlyDeleted);
      expect(find.text('Nothing deleted recently'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla', (tester) async {
      await openShop(
        tester,
        AppRoutes.recentlyDeleted,
        locale: 'bn',
        extra: () =>
            DriftCustomerRepository(shopDb)
                .softDelete('c2', DateTime(2026, 3, 9, 10)),
      );
      expect(find.text('সম্প্রতি মোছা'), findsOneWidget);
      expect(find.text('আর ২৯ দিন'), findsOneWidget);
      expect(find.text('ফিরিয়ে আনুন'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('reachable from More', (tester) async {
      await openShop(tester, AppRoutes.more);
      await tapKeyed(tester, 'more-deleted');
      expect(find.text('Nothing deleted recently'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('the app purges old deleted customers when it starts', (
      tester,
    ) async {
      await openShop(
        tester,
        AppRoutes.home,
        extra: () =>
            DriftCustomerRepository(shopDb)
                .softDelete('c2', DateTime(2026, 1, 1)),
      );
      await tester.pump(const Duration(seconds: 1));
      final remaining = await tester.runAsync(
        () => shopDb.select(shopDb.customer).get(),
      );
      expect(remaining!.map((c) => c.id), ['c1']);
      await shutDown(tester, shopDb);
    });
  });
}
