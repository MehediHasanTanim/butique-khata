import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/data/deleted_customers.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';
import 'package:tailor_khata/features/export/data/csv_exporter.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/data/drift_rush_repository.dart';

/// Remembers every SELECT the app runs so its query plan can be checked.
class _Recorder extends QueryInterceptor {
  final Map<String, List<Object?>> selects = {};

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (!statement.startsWith('EXPLAIN')) {
      selects.putIfAbsent(statement, () => args);
    }
    return super.runSelect(executor, statement, args);
  }
}

const int customerCount = 10000;
const int orderCount = 50000;

/// A busy shop: 10,000 customers, 50,000 orders with garments and advance
/// payments, 30,000 measurement versions (TD §11 reference load). Like a
/// real shop, most orders are history: one in ten is still open.
Future<void> loadBusyShop(AppDatabase db) async {
  final people = SeedGenerator().customers(customerCount);
  await db.batch((batch) {
    batch.insertAll(db.customer, [
      for (var i = 0; i < customerCount; i++)
        CustomerCompanion.insert(
          id: 'c$i',
          name: people[i].name,
          nameNorm: NameNormalizer.normalize(people[i].name),
          phone: Value('+88${people[i].phone}'),
          phoneDigits: Value(
            PhoneNormalizer.parse(people[i].phone)?.searchDigits,
          ),
          createdAt: 1,
          updatedAt: 1,
        ),
    ]);
  });
  const orderN = orderCount - 1;
  await db.customStatement('''
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < $orderN)
INSERT INTO customer_order (id, number, customer_id, delivery_date, discount, urgent,
                            status, created_at, updated_at)
SELECT 'o' || i, i + 1, 'c' || (i % $customerCount),
       date('2026-02-20', '+' || (i % 60) || ' days'), 0, i % 20 = 0,
       CASE i % 50 WHEN 0 THEN 'received' WHEN 1 THEN 'cut' WHEN 2 THEN 'stitching'
                  WHEN 3 THEN 'finishing' WHEN 4 THEN 'ready' ELSE 'delivered' END,
       1, 1
FROM n''');
  await db.customStatement('''
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < $orderN)
INSERT INTO order_item (id, order_id, garment_type_id, qty, price, status,
                        status_changed_at, work_units)
SELECT 'i' || i, 'o' || i, (SELECT id FROM garment_type WHERE key = 'panjabi'), 1,
       120000,
       CASE i % 50 WHEN 0 THEN 'received' WHEN 1 THEN 'cut' WHEN 2 THEN 'stitching'
                  WHEN 3 THEN 'finishing' WHEN 4 THEN 'ready' ELSE 'delivered' END,
       1, 100
FROM n''');
  await db.customStatement('''
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 2 FROM n WHERE i < ${orderN - 1})
INSERT INTO payment (id, order_id, amount, kind, method, paid_on, created_at)
SELECT 'p' || i, 'o' || i, 50000, 'advance', 'cash', '2026-02-20', 1 FROM n''');
  await db.customStatement('''
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 29999)
INSERT INTO measurement_set (id, customer_id, garment_type_id, version, taken_on,
                             display_unit, status, created_at)
SELECT 'm' || i, 'c' || (i % $customerCount),
       (SELECT id FROM garment_type WHERE key = 'panjabi'), i / $customerCount + 1,
       '2026-01-01', 'in', 'active', 1
FROM n''');
  await db.customStatement('''
INSERT INTO measurement_value (set_id, field_key, mm10)
SELECT id, 'chest', 9779 FROM measurement_set''');
}

List<String> fullScans(List<String> plan) => [
  for (final line in plan)
    if (RegExp(r'^SCAN ').hasMatch(line) &&
        !line.contains('USING') &&
        !line.contains('CONSTANT ROW') &&
        !line.contains('VIRTUAL TABLE'))
      line,
];

void main() {
  late AppDatabase db;
  late _Recorder recorder;
  final clock = FixedClock(DateTime(2026, 3, 10, 10));

  setUpAll(() async {
    recorder = _Recorder();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
    await loadBusyShop(db);
  });
  tearDownAll(() => db.close());

  Future<List<String>> planOf(String sql, List<Object?> args) async {
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN $sql',
          variables: [for (final a in args) Variable(a)],
        )
        .get();
    return [for (final r in rows) r.read<String>('detail')];
  }

  /// Times [action] a few times and returns the best, so one slow scheduler
  /// hiccup on a busy CI machine does not fail the build.
  Future<int> best(Future<void> Function() action, {int runs = 5}) async {
    var fastest = 1 << 30;
    for (var i = 0; i < runs; i++) {
      final watch = Stopwatch()..start();
      await action();
      watch.stop();
      fastest = min(fastest, watch.elapsedMilliseconds);
    }
    return fastest;
  }

  test('the busy shop is as big as intended', () async {
    Future<int> count(String table) async =>
        (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
            .read<int>('c');
    expect(await count('customer'), customerCount);
    expect(await count('customer_order'), orderCount);
    expect(await count('order_item'), orderCount);
    expect(await count('payment'), orderCount ~/ 2);
    expect(await count('measurement_set'), 30000);
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('hot queries never scan a whole table (S6-08)', () {
    late DriftOrderRepository orders;
    late DriftCustomerRepository customers;
    late DriftMeasurementRepository measures;
    late DriftRushRepository rush;
    final panjabi = BuiltInTemplates.byKey('panjabi').id;

    setUpAll(() {
      orders = DriftOrderRepository(db, clock, SequentialIdGenerator('x'));
      customers = DriftCustomerRepository(db);
      measures = DriftMeasurementRepository(
        db,
        clock,
        SequentialIdGenerator('y'),
      );
      rush = DriftRushRepository(db);
    });

    /// Runs what each screen runs, so [recorder] sees the real statements.
    Future<void> exerciseScreens() async {
      final today = '2026-03-10';
      // Customer list, search by name, by phone, duplicate check.
      await customers.watchAll().first;
      await customers.search('rah');
      await customers.search('রহ');
      await customers.search('01712');
      await customers.findByPhone('+8801712345678');
      await customers.byId('c77');
      // Orders and deliveries.
      await orders.deliveriesPage(from: today, to: today);
      await orders.deliveriesPage(
        from: today,
        to: '2026-03-17',
        after: const DeliveryCursor('2026-03-12', 3000),
      );
      await orders.deliveriesPage(
        after: const DeliveryCursor('2026-03-12', 3000),
      );
      await orders.uncollected(olderThanMillis: 1000);
      await orders.watchSummaries(customerId: 'c77').first;
      await orders.detail('o77');
      await orders.watchCustomerDue('c77').first;
      await orders
          .watchDeliveryCounts(
            buckets: DeliveryBuckets.of(today),
            uncollectedBeforeMillis: 1000,
          )
          .first;
      await orders.watchDashboard(today: today, startOfTodayMillis: 1000).first;
      await orders.watchDues().first;
      await orders.watchOpenDeliveryDays().first;
      // Measurements.
      await measures.latest('c77', panjabi);
      await measures.watchLatestPerGarment('c77').first;
      await measures.versions('c77', panjabi);
      // Rush.
      await rush.watchOpenItems().first;
      await rush.watchStageCounts(toDate: '2026-03-20').first;
      await rush.itemIds(panjabi, OrderStatus.cut, toDate: today);
      // Recently deleted and export.
      await DeletedCustomerRepository(db).watchDeleted().first;
      await CsvExporter(db).customers();
    }

    /// Statements that read every row on purpose, with the reason. Each is
    /// also held to a time budget below.
    const readEverything = {
      'SELECT COALESCE(SUM(CASE WHEN o.delivery_date <':
          'Home / list counts: one pass over orders (no index on status)',
      "FROM customer_order o WHERE o.deleted_at IS NULL AND o.cancelled_at IS NULL AND o.status != 'delivered' AND o.delivery_date = ?":
          'Home dashboard numbers',
      'SELECT c.id AS customer_id, c.name AS customer_name, SUM(CASE WHEN m.total - m.paid':
          'who owes what: totals over every order',
      'FROM customer c WHERE c.deleted_at IS NOT NULL':
          'the recently-deleted list (few rows, by definition)',
    };

    test('every SELECT uses an index', () async {
      recorder.selects.clear();
      await exerciseScreens();
      expect(recorder.selects.length, greaterThan(15));

      final problems = <String>[];
      for (final entry in recorder.selects.entries.toList()) {
        final sql = entry.key;
        if (sql.startsWith('EXPLAIN') || sql.startsWith('PRAGMA')) continue;
        final scans = fullScans(await planOf(sql, entry.value));
        if (scans.isEmpty) continue;
        final allowed = readEverything.keys.any(sql.contains);
        if (!allowed) problems.add('$scans\n  in: $sql');
      }
      expect(problems, isEmpty, reason: problems.join('\n\n'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('screens stay within their time budget at 50,000 orders', () async {
      const today = '2026-03-10';
      // Generous limits for a slow CI machine; a phone is slower than this
      // desktop, but the headroom is tenfold or more.
      final budgets = <String, (int, Future<void> Function())>{
        'search by name': (200, () => customers.search('rah')),
        'search by Bangla name': (200, () => customers.search('রহ')),
        'search by phone': (200, () => customers.search('01712')),
        'duplicate phone check': (
          50,
          () => customers.findByPhone('+8801712345678'),
        ),
        'first page of the customer list': (
          300,
          () => customers.watchAll().first,
        ),
        'deliveries today': (
          150,
          () => orders.deliveriesPage(from: today, to: today),
        ),
        'next page of deliveries': (
          150,
          () => orders.deliveriesPage(
            after: const DeliveryCursor('2026-03-12', 3000),
          ),
        ),
        'a customer\'s orders': (
          50,
          () => orders.watchSummaries(customerId: 'c77').first,
        ),
        'order detail': (50, () => orders.detail('o77')),
        'what a customer owes': (
          50,
          () => orders.watchCustomerDue('c77').first,
        ),
        'delivery counts': (
          250,
          () => orders
              .watchDeliveryCounts(
                buckets: DeliveryBuckets.of(today),
                uncollectedBeforeMillis: 1000,
              )
              .first,
        ),
        'home dashboard': (
          300,
          () => orders
              .watchDashboard(today: today, startOfTodayMillis: 1000)
              .first,
        ),
        'dues list': (500, () => orders.watchDues().first),
        'reminder days': (150, () => orders.watchOpenDeliveryDays().first),
        'latest measurements': (
          50,
          () => measures.watchLatestPerGarment('c77').first,
        ),
        'measurement history': (50, () => measures.versions('c77', panjabi)),
        'rush open items': (300, () => rush.watchOpenItems().first),
        'rush stage counts': (
          200,
          () => rush.watchStageCounts(toDate: '2026-03-20').first,
        ),
      };
      final slow = <String>[];
      for (final entry in budgets.entries) {
        final (limit, action) = entry.value;
        final took = await best(action);
        if (took > limit) slow.add('${entry.key}: $took ms (limit $limit)');
      }
      expect(slow, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('plans use the intended indexes', () async {
      Future<String> plan(String sql, [List<Object?> args = const []]) async =>
          (await planOf(sql, args)).join(' | ');

      expect(
        await plan('SELECT * FROM customer_order WHERE customer_id = ?', [
          'c5',
        ]),
        contains('idx_order_customer'),
      );
      expect(
        await plan(
          'SELECT * FROM customer_order WHERE delivery_date >= ? ORDER BY delivery_date, number LIMIT 30',
          ['2026-03-10'],
        ),
        contains('idx_order_delivery'),
      );
      expect(
        await plan('SELECT * FROM order_item WHERE order_id = ?', ['o5']),
        contains('idx_item_order'),
      );
      expect(
        await plan('SELECT * FROM payment WHERE order_id = ?', ['o5']),
        contains('idx_payment_order'),
      );
      expect(
        await plan(
          'SELECT * FROM measurement_set WHERE customer_id = ? AND garment_type_id = ? ORDER BY version DESC',
          ['c5', 'g'],
        ),
        // The unique (customer, garment, version) index serves this lookup.
        contains('customer_id=? AND garment_type_id=?'),
      );
      expect(
        await plan('SELECT * FROM customer WHERE phone_digits = ?', [
          '01712345678',
        ]),
        contains('idx_customer_phone'),
      );
      expect(
        await plan('SELECT * FROM customer ORDER BY name_norm LIMIT 50'),
        contains('idx_customer_name'),
      );
      expect(
        await plan(
          "SELECT rowid FROM customer_fts WHERE customer_fts MATCH 'rah*'",
        ),
        contains('VIRTUAL TABLE'),
      );
      expect(
        await plan("SELECT * FROM order_item WHERE status = 'cut'"),
        contains('idx_item_status'),
      );
    });
  });
}
