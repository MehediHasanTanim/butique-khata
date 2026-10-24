import 'dart:io';
import 'dart:typed_data';

import 'package:tailor_khata/core/backup/backup_crypto.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/backup/data/backup_key_store.dart';
import 'package:tailor_khata/features/backup/data/backup_service.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/rush/data/drift_rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

/// A phone: its own encrypted database, photo folder and backup folder.
class Phone {
  Phone._(this.dir, this.db, this.keyHex, this.clock);

  final Directory dir;
  AppDatabase db;
  final String keyHex;
  final FixedClock clock;

  File get dbFile => File('${dir.path}/tailor_khata.db');
  Directory get media => Directory('${dir.path}/media');
  Directory get backups => Directory('${dir.path}/backups');

  /// A new phone with an empty shop. [keyChar] makes each phone's device key
  /// different, as on real devices.
  static Future<Phone> create({String keyChar = 'a', DateTime? now}) async {
    final dir = Directory.systemTemp.createTempSync('tk_phone');
    final keyHex = keyChar * 64;
    final db = await DatabaseOpener.open(
      File('${dir.path}/tailor_khata.db'),
      hexKey: keyHex,
      inBackground: false,
    );
    return Phone._(
      dir,
      db,
      keyHex,
      FixedClock(now ?? DateTime(2026, 3, 10, 9)),
    );
  }

  Future<void> reopen() async {
    db = await DatabaseOpener.open(dbFile, hexKey: keyHex, inBackground: false);
  }

  BackupService service({
    BackupKeyStore? keys,
    String deviceId = 'phone',
    bool useIsolate = false,
  }) => BackupService(
    db: db,
    mediaDir: media,
    backupDir: backups,
    clock: clock,
    keyStore: keys ?? InMemoryBackupKeyStore(),
    settings: SettingsRepository(db),
    deviceId: deviceId,
    useIsolate: useIsolate,
    kdfParams: KdfParams.fastForTests,
  );

  Future<void> dispose() async {
    try {
      await db.close();
    } on Object {
      // Already closed by a restore.
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Rahim (3 Panjabi measurement versions, an order with an advance and two
  /// photos), Karim (a deleted customer), a season, and some settings.
  Future<void> seed() async {
    final now = clock.now();
    final customers = DriftCustomerRepository(db);
    await customers.insert(
      Customer(
        id: 'c1',
        name: 'রহিম উদ্দিন',
        phone: '+8801712345678',
        address: 'Mirpur',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await customers.insert(
      Customer(id: 'c2', name: 'Karim Hossain', createdAt: now, updatedAt: now),
    );
    await customers.insert(
      Customer(id: 'c3', name: 'Salma', createdAt: now, updatedAt: now),
    );
    await customers.softDelete('c3', now);

    final panjabi = BuiltInTemplates.byKey('panjabi').id;
    final measurements = DriftMeasurementRepository(
      db,
      clock,
      SequentialIdGenerator('m'),
    );
    for (final (date, chest) in [
      ('2024-02-01', '36'),
      ('2025-02-01', '38'),
      ('2026-02-01', '39½'),
    ]) {
      await measurements.create(
        NewMeasurement(
          customerId: 'c1',
          garmentTypeId: panjabi,
          takenOn: date,
          unit: MeasureUnit.inch,
          values: {'chest': inches(chest), 'length': inches('42')},
          note: date == '2025-02-01' ? 'loose fit' : null,
        ),
      );
    }
    final latest = (await measurements.latest('c1', panjabi))!;

    media.createSync(recursive: true);
    File(
      '${media.path}/photo1.jpg',
    ).writeAsBytesSync(Uint8List.fromList(List.generate(2000, (i) => i % 251)));
    File(
      '${media.path}/photo1.thumb.jpg',
    ).writeAsBytesSync(Uint8List.fromList(List.generate(300, (i) => i % 97)));

    final orders = DriftOrderRepository(db, clock, SequentialIdGenerator('o'));
    final order = await orders.create(
      NewOrder(
        customerId: 'c1',
        deliveryDate: '2026-03-20',
        items: [
          NewOrderItem(
            garmentTypeId: panjabi,
            price: const Money.taka(1200),
            measurementSetId: latest.id,
            style: const {'collar': 'band'},
          ),
        ],
        advance: NewPayment(
          orderId: '',
          amount: const Money.taka(500),
          method: PayMethod.bkash,
          paidOn: '2026-03-10',
          kind: PaymentKind.advance,
        ),
      ),
    );
    await db.customStatement(
      'INSERT INTO attachment (id, owner_type, owner_id, path, thumb_path, created_at) '
      "VALUES ('att1', 'order_item', '${order.items.single.id}', 'photo1.jpg', 'photo1.thumb.jpg', 1)",
    );
    await orders.setAllItemsStatus(order.order.id, OrderStatus.cut);

    await DriftRushRepository(db).save(
      const Season(
        id: 's1',
        name: 'Eid',
        kind: SeasonKind.eidFitr,
        targetDate: '2026-03-30',
        dailyCapacity: 2000,
        closedDates: {'2026-03-27'},
      ),
    );
    await SettingsRepository(db).write('locale', 'bn');
    await SettingsRepository(db).write('shop.name', 'Noor Tailors');
  }

  /// Every row of every user table, for comparing two databases. The
  /// full-text index tables are left out: their internal layout may differ
  /// while search still works (checked separately).
  Future<Map<String, List<Map<String, Object?>>>> dump() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'customer_fts%' "
          'ORDER BY name',
        )
        .get();
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in tables) {
      final name = t.read<String>('name');
      final rows = await db
          .customSelect('SELECT * FROM "$name" ORDER BY 1, 2')
          .get();
      out[name] = [for (final r in rows) Map<String, Object?>.from(r.data)];
    }
    return out;
  }
}
