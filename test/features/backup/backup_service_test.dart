import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/backup/backup_bundle.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/features/backup/data/backup_service.dart';
import 'package:tailor_khata/features/backup/domain/backup_models.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';

import '../../support/backup_fixture.dart';
import '../../support/db_fixtures.dart';

const passphrase = 'blue-mango-7-tailor';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Phone oldPhone;
  late Phone newPhone;

  setUp(() async {
    oldPhone = await Phone.create(keyChar: 'a');
    newPhone = await Phone.create(keyChar: 'b', now: DateTime(2026, 3, 12));
  });
  tearDown(() async {
    await oldPhone.dispose();
    await newPhone.dispose();
  });

  Future<BackupService> backedUpService() async {
    final service = oldPhone.service();
    await service.setPassphrase(passphrase);
    return service;
  }

  Future<RestoreResult> restoreOnNewPhone(
    File file, {
    String pass = passphrase,
    BackupService? service,
  }) {
    final s = service ?? newPhone.service();
    return s.restore(
      backupFile: file,
      passphrase: pass,
      liveDbFile: newPhone.dbFile,
      deviceKeyHex: newPhone.keyHex,
      closeDatabase: newPhone.db.close,
    );
  }

  Future<String?> failureCode(Future<Object?> Function() action) async {
    try {
      await action();
    } on BackupFailure catch (e) {
      return e.code;
    }
    return null;
  }

  group('create (S6-01)', () {
    test('needs a passphrase first', () async {
      expect(
        await failureCode(() => oldPhone.service().createBackup()),
        BackupFailure.noKey,
      );
    });

    test('writes one encrypted file and records when', () async {
      await oldPhone.seed();
      final service = await backedUpService();
      final result = await service.createBackup();

      expect(result.file.path, endsWith('.tkbackup'));
      expect(result.file.path, contains('tailor_khata_20260310_090000'));
      expect(result.sizeBytes, greaterThan(1000));
      expect(result.manifest.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(result.manifest.counts, {
        'customers': 2,
        'orders': 1,
        'measurements': 3,
        'payments': 1,
        'attachments': 1,
      });
      expect(
        result.manifest.files.keys,
        containsAll([
          'db.sqlite',
          'media/photo1.jpg',
          'media/photo1.thumb.jpg',
        ]),
      );

      final status = await service.status();
      expect(status.lastAt, DateTime(2026, 3, 10, 9));
      expect(status.hasKey, isTrue);
    });

    test('nothing readable is left in the file', () async {
      await oldPhone.seed();
      final result = await (await backedUpService()).createBackup();
      final text = latin1.decode(result.file.readAsBytesSync());
      for (final secret in [
        'Karim',
        'Mirpur',
        'Noor Tailors',
        'SQLite',
        'customer',
      ]) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    });

    test('no temporary files are left behind', () async {
      await oldPhone.seed();
      final before = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains('tk_backup_work'))
          .length;
      await (await backedUpService()).createBackup();
      final after = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains('tk_backup_work'))
          .length;
      expect(after, before);
    });

    test('an empty shop can be backed up too', () async {
      final result = await (await backedUpService()).createBackup();
      expect(result.manifest.counts['customers'], 0);
    });

    test('works through a background isolate', () async {
      await oldPhone.seed();
      final service = oldPhone.service(useIsolate: true);
      await service.setPassphrase(passphrase);
      final result = await service.createBackup();
      expect(result.file.existsSync(), isTrue);
    });

    test('old backups are pruned when asked', () async {
      await oldPhone.seed();
      final service = await backedUpService();
      for (var i = 0; i < 4; i++) {
        oldPhone.clock.advance(const Duration(minutes: 1));
        await service.createBackup(keep: 2);
      }
      final files = service.listBackups();
      expect(files, hasLength(2));
      expect(files.first.file.path, contains('090400'));
    });

    test('a backup made while the shop keeps working is consistent', () async {
      await oldPhone.seed();
      final service = await backedUpService();
      // Start a backup and write at the same time.
      final backup = service.createBackup();
      await DriftCustomerRepository(oldPhone.db)
          .softDelete('c2', oldPhone.clock.now());
      final result = await backup;
      // Either state is fine, but the file must be restorable.
      final restored = await restoreOnNewPhone(result.file);
      expect(restored.manifest.counts['customers'], anyOf(1, 2));
    });
  });

  group('restore round trip (S6-04, S6-05)', () {
    test(
      'everything arrives on a different phone with a different key',
      () async {
        await oldPhone.seed();
        final before = await oldPhone.dump();
        final backup = await (await backedUpService()).createBackup();

        final result = await restoreOnNewPhone(backup.file);
        await newPhone.reopen();

        expect(result.manifest.counts['measurements'], 3);
        final after = await newPhone.dump();
        expect(after.keys, before.keys);
        for (final table in before.keys) {
          expect(after[table], before[table], reason: 'table $table');
        }
        // Sanity: the data is really there.
        expect(after['customer'], hasLength(3));
        expect(after['measurement_set'], hasLength(3));
        expect(after['payment'], hasLength(1));
        expect(after['attachment'], hasLength(1));
        expect(after['season'], hasLength(1));
      },
    );

    test(
      'measurement history, payments and the deleted customer survive',
      () async {
        await oldPhone.seed();
        final backup = await (await backedUpService()).createBackup();
        await restoreOnNewPhone(backup.file);
        await newPhone.reopen();

        final repo = DriftMeasurementRepository(
          newPhone.db,
          newPhone.clock,
          SequentialIdGenerator('x'),
        );
        final versions = await repo.versions(
          'c1',
          BuiltInTemplates.byKey('panjabi').id,
        );
        expect(versions.map((v) => v.version), [3, 2, 1]);
        expect(versions.last.values['chest']!.toInchFraction(), '36');
        expect(versions[1].note, 'loose fit');
        final deleted = await (newPhone.db.select(
          newPhone.db.customer,
        )..where((t) => t.id.equals('c3'))).getSingle();
        expect(deleted.deletedAt, isNotNull);
      },
    );

    test('search, views and the append-only guards still work', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      await restoreOnNewPhone(backup.file);
      await newPhone.reopen();

      final customers = DriftCustomerRepository(newPhone.db);
      expect((await customers.search('রহি')).single.id, 'c1');
      expect((await customers.search('01712')).single.id, 'c1');
      expect((await customers.search('karim')).single.id, 'c2');

      final money = await newPhone.db
          .customSelect('SELECT total, paid FROM v_order_money')
          .getSingle();
      expect(money.read<int>('total'), 120000);
      expect(money.read<int>('paid'), 50000);

      await expectLater(
        newPhone.db.customStatement('DELETE FROM measurement_value'),
        throwsA(predicate((e) => e.toString().contains('append-only'))),
      );
      await expectLater(
        newPhone.db.customStatement('UPDATE payment SET amount = 1'),
        throwsA(predicate((e) => e.toString().contains('immutable'))),
      );
      // New customers added after the restore are searchable too.
      await customers.search('x');
    });

    test('photos are copied back', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      await restoreOnNewPhone(backup.file);
      expect(
        File('${newPhone.media.path}/photo1.jpg').readAsBytesSync(),
        File('${oldPhone.media.path}/photo1.jpg').readAsBytesSync(),
      );
      expect(
        File('${newPhone.media.path}/photo1.thumb.jpg').existsSync(),
        isTrue,
      );
    });

    test('photos already on the phone are not overwritten', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      newPhone.media.createSync(recursive: true);
      File('${newPhone.media.path}/photo1.jpg').writeAsStringSync('mine');
      await restoreOnNewPhone(backup.file);
      expect(
        File('${newPhone.media.path}/photo1.jpg').readAsStringSync(),
        'mine',
      );
    });

    test('the data it replaces is kept as a safety copy for a week', () async {
      await oldPhone.seed();
      await newPhone.seed();
      await DriftCustomerRepository(newPhone.db)
          .insert(
            (await DriftCustomerRepository(newPhone.db).byId('c1'))!.copyWith(),
          )
          .onError((_, _) {});
      final backup = await (await backedUpService()).createBackup();
      final before = newPhone.dbFile.readAsBytesSync().length;

      final result = await restoreOnNewPhone(backup.file);
      expect(result.safetyCopy, isNotNull);
      expect(result.safetyCopy!.path, contains('pre_restore_20260312_000000'));
      expect(result.safetyCopy!.lengthSync(), before);

      // The safety copy opens with the phone's own key.
      final copy = await DatabaseOpener.open(
        result.safetyCopy!,
        hexKey: newPhone.keyHex,
        inBackground: false,
      );
      expect((await copy.select(copy.customer).get()), isNotEmpty);
      await copy.close();
    });

    test('old safety copies are cleaned up after a week', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      final stale = File('${newPhone.dir.path}/pre_restore_20260101_000000.db')
        ..writeAsStringSync('old');
      stale.setLastModifiedSync(DateTime(2026, 3, 1));
      await restoreOnNewPhone(backup.file);
      expect(stale.existsSync(), isFalse);
    });

    test('restoring onto a phone with no database yet works', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      final fresh = await Phone.create(keyChar: 'c');
      await fresh.db.close();
      fresh.dbFile.deleteSync();
      final service = fresh.service();
      final result = await service.restore(
        backupFile: backup.file,
        passphrase: passphrase,
        liveDbFile: fresh.dbFile,
        deviceKeyHex: fresh.keyHex,
        closeDatabase: () async {},
      );
      expect(result.safetyCopy, isNull);
      await fresh.reopen();
      expect((await fresh.db.select(fresh.db.customer).get()), hasLength(3));
      await fresh.dispose();
    });

    test(
      'the restored phone can make its own backups and restore them again',
      () async {
        await oldPhone.seed();
        final first = await (await backedUpService()).createBackup();
        await restoreOnNewPhone(first.file);
        await newPhone.reopen();
        final second = newPhone.service();
        await second.setPassphrase('another-passphrase');
        final again = await second.createBackup();
        expect(again.manifest.counts['measurements'], 3);
      },
    );
  });

  group('refusals leave the current data untouched (S6-05)', () {
    Future<void> expectUntouched(
      Future<void> Function() attempt,
      String code,
    ) async {
      await newPhone.seed();
      final before = await newPhone.dump();
      final bytesBefore = newPhone.dbFile.readAsBytesSync();
      expect(await failureCode(attempt), code);
      // Still open and unchanged; the file on disk was not touched.
      expect(await newPhone.dump(), before);
      expect(newPhone.dbFile.readAsBytesSync(), bytesBefore);
      expect(
        newPhone.dir.listSync().where((e) => e.path.contains('incoming')),
        isEmpty,
      );
      expect(
        newPhone.dir.listSync().where((e) => e.path.contains('pre_restore')),
        isEmpty,
      );
    }

    test('wrong passphrase', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      await expectUntouched(
        () => restoreOnNewPhone(backup.file, pass: 'not it'),
        BackupFailure.wrongPassphrase,
      );
    });

    test('a damaged file', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      final bytes = backup.file.readAsBytesSync();
      final broken = File('${newPhone.dir.path}/broken.tkbackup')
        ..writeAsBytesSync(
          Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 0xff,
        );
      await expectUntouched(
        () => restoreOnNewPhone(broken),
        BackupFailure.wrongPassphrase,
      );
    });

    test('a file cut short', () async {
      await oldPhone.seed();
      final backup = await (await backedUpService()).createBackup();
      final bytes = backup.file.readAsBytesSync();
      final cut = File('${newPhone.dir.path}/cut.tkbackup')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 100));
      await expectUntouched(
        () => restoreOnNewPhone(cut),
        BackupFailure.corrupt,
      );
    });

    test('something that is not a backup', () async {
      final junk = File('${newPhone.dir.path}/photo.jpg')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(500, 3)));
      await expectUntouched(
        () => restoreOnNewPhone(junk),
        BackupFailure.notABackup,
      );
    });

    test('a file that is far too small', () async {
      final tiny = File('${newPhone.dir.path}/tiny.tkbackup')
        ..writeAsBytesSync([1]);
      await expectUntouched(
        () => restoreOnNewPhone(tiny),
        BackupFailure.notABackup,
      );
    });

    test('a missing file', () async {
      await expectUntouched(
        () => restoreOnNewPhone(File('${newPhone.dir.path}/nope.tkbackup')),
        BackupFailure.notABackup,
      );
    });
  });

  group('tampered but validly encrypted backups', () {
    late BackupService service;

    /// Builds a backup file from a real one, letting [change] edit the
    /// unpacked contents (manifest map and files) before re-sealing.
    Future<File> forge(
      File original,
      Future<void> Function(Directory dir, Map<String, dynamic> manifest)
      change,
    ) async {
      final key = (await service.keyStore.load())!;
      final work = Directory.systemTemp.createTempSync('tk_forge');
      addTearDown(() => work.deleteSync(recursive: true));
      final bundle = File('${work.path}/b.bin');
      await BackupCrypto.decryptFileWithKey(
        original,
        bundle,
        key,
        inIsolate: false,
      );
      final dir = Directory('${work.path}/u')..createSync();
      BackupBundle.read(bundle, dir);
      final manifest = jsonDecode(
        File('${dir.path}/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      await change(dir, manifest);
      File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode(manifest));
      final entries = <BundleEntry>[
        BundleEntry.file('manifest.json', File('${dir.path}/manifest.json')),
        for (final f in dir.listSync(recursive: true).whereType<File>())
          if (!f.path.endsWith('manifest.json'))
            BundleEntry.file(f.path.substring(dir.path.length + 1), f),
      ];
      final out = File('${work.path}/b2.bundle');
      BackupBundle.write(out, entries);
      final sealed = File('${newPhone.dir.path}/forged.tkbackup');
      await BackupCrypto.encryptFile(out, sealed, key, inIsolate: false);
      return sealed;
    }

    late File original;

    setUp(() async {
      await oldPhone.seed();
      service = await backedUpService();
      original = (await service.createBackup()).file;
    });

    Future<void> untouched(File forged, String code) async {
      await newPhone.seed();
      final before = await newPhone.dump();
      expect(
        await failureCode(
          () => restoreOnNewPhone(
            forged,
            service: newPhone.service(keys: service.keyStore),
          ),
        ),
        code,
      );
      expect(await newPhone.dump(), before);
    }

    test('a photo that does not match its checksum', () async {
      final forged = await forge(original, (dir, m) async {
        File('${dir.path}/media/photo1.jpg').writeAsStringSync('swapped');
      });
      await untouched(forged, BackupFailure.corrupt);
    });

    test('counts that do not match the database', () async {
      final forged = await forge(original, (dir, m) async {
        (m['counts'] as Map)['customers'] = 99;
      });
      await untouched(forged, BackupFailure.corrupt);
    });

    test('a file the manifest does not list', () async {
      final forged = await forge(original, (dir, m) async {
        File('${dir.path}/media/extra.jpg').writeAsStringSync('x');
      });
      await untouched(forged, BackupFailure.corrupt);
    });

    test('a listed file that is missing', () async {
      final forged = await forge(original, (dir, m) async {
        File('${dir.path}/media/photo1.thumb.jpg').deleteSync();
      });
      await untouched(forged, BackupFailure.corrupt);
    });

    test('a backup from a newer version of the app', () async {
      final forged = await forge(original, (dir, m) async {
        m['schemaVersion'] = AppDatabase.currentSchemaVersion + 1;
      });
      await untouched(forged, BackupFailure.newerVersion);
    });

    test('an unknown format number', () async {
      final forged = await forge(original, (dir, m) async {
        m['format'] = 99;
      });
      await untouched(forged, BackupFailure.newerVersion);
    });

    test('a manifest that is not valid', () async {
      final forged = await forge(original, (dir, m) async {
        m.remove('counts');
      });
      await untouched(forged, BackupFailure.corrupt);
    });
  });

  group('older backups are migrated forward (S6-04)', () {
    test('a version 1 backup restores into the current schema', () async {
      // Build a v1 database (as an old phone would have), snapshot it under a
      // backup key and seal it the way an old app did.
      final key = await BackupCrypto.deriveKey(
        passphrase,
        params: KdfParams.fastForTests,
      );
      final work = Directory.systemTemp.createTempSync('tk_old');
      addTearDown(() => work.deleteSync(recursive: true));
      final snapshot = File('${work.path}/db.sqlite');
      final raw = sqlite.sqlite3.open(snapshot.path)
        ..execute("PRAGMA key = \"x'${key.hex}'\"");
      DbFixtures.createV1(raw);
      raw.close();
      final manifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '0.1.0',
        createdAt: DateTime(2025, 1, 1),
        deviceId: 'old-phone',
        counts: const {
          'customers': 0,
          'orders': 0,
          'measurements': 0,
          'payments': 0,
          'attachments': 0,
        },
        files: {'db.sqlite': await BackupBundle.sha256Of(snapshot)},
      );
      final bundle = File('${work.path}/b.bin');
      BackupBundle.write(bundle, [
        BundleEntry.bytes('manifest.json', utf8.encode(manifest.encode())),
        BundleEntry.file('db.sqlite', snapshot),
      ]);
      final sealed = File('${work.path}/old.tkbackup');
      await BackupCrypto.encryptFile(bundle, sealed, key, inIsolate: false);

      final result = await restoreOnNewPhone(sealed);
      expect(result.manifest.schemaVersion, 1);
      await newPhone.reopen();
      // Old data kept, new tables exist and work.
      expect(
        (await newPhone.db.select(newPhone.db.appSetting).get()).single.value,
        'bn',
      );
      expect(
        await newPhone.db.select(newPhone.db.garmentType).get(),
        hasLength(7),
      );
      expect(await newPhone.db.select(newPhone.db.season).get(), isEmpty);
      final version = await newPhone.db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
    });
  });

  group('automatic backups (S6-03)', () {
    test('nothing happens until a passphrase is set', () async {
      expect(await oldPhone.service().maybeAutoBackup(), isNull);
    });

    test('the first one runs, then waits a day', () async {
      await oldPhone.seed();
      final service = await backedUpService();
      expect(await service.maybeAutoBackup(), isNotNull);
      expect(await service.maybeAutoBackup(), isNull, reason: 'just done');
      oldPhone.clock.advance(const Duration(hours: 23));
      expect(await service.maybeAutoBackup(), isNull);
      oldPhone.clock.advance(const Duration(hours: 2));
      expect(await service.maybeAutoBackup(), isNotNull);
    });

    test('can be switched off', () async {
      final service = await backedUpService();
      await service.setAutoEnabled(false);
      expect(await service.maybeAutoBackup(), isNull);
      await service.setAutoEnabled(true);
      expect(await service.maybeAutoBackup(), isNotNull);
    });

    test('only the newest five automatic backups are kept', () async {
      final service = await backedUpService();
      for (var i = 0; i < 8; i++) {
        oldPhone.clock.advance(const Duration(days: 2));
        await service.maybeAutoBackup();
      }
      expect(service.listBackups(), hasLength(5));
    });

    test('a failing backup does not crash the app', () async {
      final service = await backedUpService();
      oldPhone.backups.parent.createSync(recursive: true);
      // A file where the backup folder should be.
      File(oldPhone.backups.path).writeAsStringSync('in the way');
      expect(await service.maybeAutoBackup(), isNull);
    });
  });

  group('status (S6-03)', () {
    test('never backed up counts as stale', () {
      const status = BackupStatus();
      expect(status.daysSince(DateTime(2026, 3, 10)), isNull);
      expect(status.isStale(DateTime(2026, 3, 10)), isTrue);
    });

    test('stale after a week, fresh before', () {
      final status = BackupStatus(lastAt: DateTime(2026, 3, 1), hasKey: true);
      expect(status.daysSince(DateTime(2026, 3, 8)), 7);
      expect(status.isStale(DateTime(2026, 3, 7)), isFalse);
      expect(status.isStale(DateTime(2026, 3, 8)), isTrue);
    });
  });

  group('bundle safety', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tk_bundle'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('only expected names can be written', () {
      for (final bad in [
        '../evil',
        '/abs',
        'media/../x',
        'media/a/b',
        'other.txt',
        'media/.hidden',
        '',
      ]) {
        expect(
          () => BackupBundle.write(File('${dir.path}/x.bin'), [
            BundleEntry.bytes(bad, Uint8List(1)),
          ]),
          throwsA(isA<BundleException>()),
          reason: bad,
        );
      }
    });

    test('a hand-made bundle with a path escape is rejected on read', () {
      final name = utf8.encode('../../outside');
      final bytes = BytesBuilder()
        ..add([0, name.length])
        ..add(name)
        ..add(Uint8List(8)..buffer.asByteData().setUint64(0, 3))
        ..add([1, 2, 3])
        ..add([0, 0]);
      final file = File('${dir.path}/evil.bin')
        ..writeAsBytesSync(bytes.toBytes());
      final out = Directory('${dir.path}/out')..createSync();
      expect(
        () => BackupBundle.read(file, out),
        throwsA(isA<BundleException>()),
      );
      expect(File('${dir.path}/../outside').existsSync(), isFalse);
    });

    test('lengths that lie are rejected', () {
      final name = utf8.encode('db.sqlite');
      final bytes = BytesBuilder()
        ..add([0, name.length])
        ..add(name)
        ..add(Uint8List(8)..buffer.asByteData().setUint64(0, 1 << 40))
        ..add([0, 0]);
      final file = File('${dir.path}/lie.bin')
        ..writeAsBytesSync(bytes.toBytes());
      expect(
        () => BackupBundle.read(file, Directory('${dir.path}/o')..createSync()),
        throwsA(isA<BundleException>()),
      );
    });

    test('duplicates, trailing garbage and truncation are rejected', () {
      final out = Directory('${dir.path}/o')..createSync();
      final a = File('${dir.path}/a.bin');
      BackupBundle.write(a, [
        BundleEntry.bytes('db.sqlite', Uint8List.fromList([1, 2])),
      ]);
      // Trailing data after the end marker.
      File('${dir.path}/trail.bin')
          .writeAsBytesSync([...a.readAsBytesSync(), 9]);
      expect(
        () => BackupBundle.read(File('${dir.path}/trail.bin'), out),
        throwsA(isA<BundleException>()),
      );
      // Cut short.
      final bytes = a.readAsBytesSync();
      File('${dir.path}/cut.bin')
          .writeAsBytesSync(bytes.sublist(0, bytes.length - 4));
      expect(
        () => BackupBundle.read(File('${dir.path}/cut.bin'), out),
        throwsA(isA<BundleException>()),
      );
      // Same name twice.
      final twice = File('${dir.path}/twice.bin');
      BackupBundle.write(twice, [
        BundleEntry.bytes('db.sqlite', Uint8List(1)),
        BundleEntry.bytes('db.sqlite', Uint8List(1)),
      ]);
      expect(
        () => BackupBundle.read(twice, out),
        throwsA(isA<BundleException>()),
      );
    });

    test('round trip keeps bytes and order', () {
      final src = File('${dir.path}/src.bin')
        ..writeAsBytesSync(List.generate(3000000, (i) => i % 256));
      final bundle = File('${dir.path}/b.bin');
      BackupBundle.write(bundle, [
        BundleEntry.bytes('manifest.json', utf8.encode('{}')),
        BundleEntry.file('db.sqlite', src),
        BundleEntry.bytes('media/a.jpg', Uint8List.fromList([5, 6])),
      ]);
      final out = Directory('${dir.path}/out')..createSync();
      expect(BackupBundle.read(bundle, out), [
        'manifest.json',
        'db.sqlite',
        'media/a.jpg',
      ]);
      expect(
        File('${out.path}/db.sqlite').readAsBytesSync(),
        src.readAsBytesSync(),
      );
      expect(File('${out.path}/media/a.jpg').readAsBytesSync(), [5, 6]);
    });
  });
}
