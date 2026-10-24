import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/export/data/csv_exporter.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';

import '../../support/fakes.dart';
import '../../support/shop_fixture.dart';
import '../../support/test_app.dart';

void main() {
  group('cells', () {
    test('plain text stays as it is', () {
      expect(CsvExporter.csvCell('Rahim'), 'Rahim');
      expect(CsvExporter.csvCell('রহিম উদ্দিন'), 'রহিম উদ্দিন');
      expect(CsvExporter.csvCell(''), '');
    });

    test('commas, quotes and line breaks are quoted', () {
      expect(CsvExporter.csvCell('a,b'), '"a,b"');
      expect(CsvExporter.csvCell('say "hi"'), '"say ""hi"""');
      expect(CsvExporter.csvCell('two\nlines'), '"two\nlines"');
    });

    test('anything a spreadsheet could run as a formula is defused', () {
      expect(CsvExporter.csvCell('=1+1'), "'=1+1");
      expect(CsvExporter.csvCell('@SUM(A1)'), "'@SUM(A1)");
      expect(CsvExporter.csvCell('+cmd|x'), "'+cmd|x");
      expect(CsvExporter.csvCell('-cmd'), "'-cmd");
      expect(
        CsvExporter.csvCell('=HYPERLINK("http://x","y")'),
        "\"'=HYPERLINK(\"\"http://x\"\",\"\"y\"\")\"",
      );
    });

    test('phone numbers and negative amounts are not damaged', () {
      expect(CsvExporter.csvCell('+8801712345678'), '+8801712345678');
      expect(CsvExporter.csvCell('-500.00'), '-500.00');
    });

    test('money is shown as taka with two decimals', () {
      expect(CsvExporter.formatTaka(125050), '1250.50');
      expect(CsvExporter.formatTaka(5), '0.05');
      expect(CsvExporter.formatTaka(-1200), '-12.00');
      expect(CsvExporter.formatTaka(0), '0.00');
    });
  });

  group('files', () {
    late AppDatabase db;
    late CsvExporter exporter;

    setUp(() async {
      env = TestEnv();
      addTearDown(env.dispose);
      db = memoryDb();
      await seed(db);
      exporter = CsvExporter(db);
    });
    tearDown(() => db.close());

    List<List<String>> parse(String csv) => const LineSplitter()
        .convert(csv)
        .where((l) => l.isNotEmpty)
        .map((l) => l.split(','))
        .toList();

    test('customers', () async {
      final csv = await exporter.customers();
      final rows = parse(csv);
      expect(rows.first, [
        'id',
        'name',
        'phone',
        'address',
        'note',
        'created',
        'deleted',
      ]);
      expect(rows, hasLength(3));
      final rahim = rows.firstWhere((r) => r[0] == 'c1');
      expect(rahim[1], 'Rahim Uddin');
      expect(rahim[2], '+8801712345678');
      expect(rahim[5], '2026-03-05');
      expect(rahim[6], '');
      expect(csv, contains('\r\n'));
    });

    test('deleted customers are included, with the date', () async {
      await DriftCustomerRepository(db).softDelete('c2', DateTime(2026, 3, 9));
      final rows = parse(await exporter.customers());
      expect(rows.firstWhere((r) => r[0] == 'c2')[6], '2026-03-09');
    });

    test('names with commas and quotes survive', () async {
      await DriftCustomerRepository(db).insert(
        Customer(
          id: 'c9',
          name: 'Begum, "Rina"',
          createdAt: DateTime(2026, 3, 1),
          updatedAt: DateTime(2026, 3, 1),
        ),
      );
      expect(await exporter.customers(), contains('"Begum, ""Rina"""'));
    });

    test('orders carry total, paid and due', () async {
      await seedOrder(price: 1200, advance: 500, delivery: '2026-03-12');
      final rows = parse(await exporter.orders());
      expect(rows.first.sublist(0, 3), ['order_no', 'customer', 'phone']);
      final row = rows[1];
      final head = rows.first;
      String cell(String column) => row[head.indexOf(column)];
      expect(cell('customer'), 'Rahim Uddin');
      expect(cell('delivery_date'), '2026-03-12');
      expect(cell('total_bdt'), '1200.00');
      expect(cell('paid_bdt'), '500.00');
      expect(cell('due_bdt'), '700.00');
      expect(cell('urgent'), 'no');
    });

    test('payments include refunds as negative amounts', () async {
      final order = await seedOrder(price: 1200, advance: 500);
      await orders.addPayment(
        NewPayment(
          orderId: order.order.id,
          amount: const Money.taka(-100),
          method: PayMethod.cash,
          paidOn: '2026-03-08',
          kind: PaymentKind.refund,
        ),
      );
      final rows = parse(await exporter.payments());
      expect(rows.first, [
        'order_no',
        'customer',
        'date',
        'amount_bdt',
        'kind',
        'method',
        'note',
      ]);
      expect(rows.map((r) => r[3]), containsAll(['500.00', '-100.00']));
      expect(rows.map((r) => r[4]), containsAll(['advance', 'refund']));
    });

    test('measurements: one row per value, in inches and cm', () async {
      final rows = parse(await exporter.measurements());
      expect(rows.first, [
        'customer',
        'phone',
        'garment',
        'version',
        'taken_on',
        'status',
        'set_note',
        'field',
        'inches',
        'text',
        'cm',
      ]);
      final chest = rows.firstWhere((r) => r.contains('chest'));
      expect(chest[0], 'Rahim Uddin');
      expect(chest[2], 'panjabi');
      expect(chest[3], '1');
      expect(chest[4], '2026-03-01');
      final head = rows.first;
      expect(chest[head.indexOf('inches')], '38.500');
      expect(chest[head.indexOf('cm')], '97.8');
    });

    test('the zip holds all four files, each with a byte-order mark', () async {
      await seedOrder();
      final bytes = await exporter.buildZip();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.map((f) => f.name), CsvExporter.fileNames);
      for (final file in archive.files) {
        final data = file.content as List<int>;
        expect(data.take(3), [0xEF, 0xBB, 0xBF], reason: file.name);
        final text = utf8.decode(data.skip(3).toList());
        expect(text, isNotEmpty);
        expect(text.endsWith('\r\n'), isTrue);
      }
      final customers = utf8.decode(
        (archive.findFile('customers.csv')!.content as List<int>)
            .skip(3)
            .toList(),
      );
      expect(customers, contains('Rahim Uddin'));
    });

    test('an empty shop still gives header-only files', () async {
      final empty = memoryDb();
      addTearDown(empty.close);
      final archive = ZipDecoder().decodeBytes(
        await CsvExporter(empty).buildZip(),
      );
      for (final file in archive.files) {
        final lines = utf8
            .decode((file.content as List<int>).skip(3).toList())
            .split('\r\n')
            .where((l) => l.isNotEmpty);
        expect(lines, hasLength(1), reason: file.name);
      }
    });

    test('exporting changes nothing', () async {
      await seedOrder();
      final before = await db.select(db.payment).get();
      await exporter.buildZip();
      expect(await db.select(db.payment).get(), hasLength(before.length));
    });
  });

  group('More screen', () {
    testWidgets('Export shares a zip named after today', (tester) async {
      await openShop(tester, AppRoutes.more);
      await tapKeyed(tester, 'more-export');
      await settleIo(tester, until: () => env.sharer.shared.isNotEmpty);
      final shared = env.sharer.shared.single;
      expect(shared.fileName, 'tailor_khata_20260310.zip');
      final archive = ZipDecoder().decodeBytes(
        Uint8List.fromList(shared.bytes),
      );
      expect(archive.files, hasLength(4));
      await shutDown(tester, shopDb);
    });
  });
}
