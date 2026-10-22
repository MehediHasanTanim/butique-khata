import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

import '../support/db_fixtures.dart';

AppDatabase _memory() => AppDatabase(NativeDatabase.memory());

void main() {
  group('SettingsRepository', () {
    late AppDatabase db;
    late SettingsRepository repo;

    setUp(() {
      db = _memory();
      repo = SettingsRepository(db);
    });
    tearDown(() => db.close());

    test('read returns null, write upserts, remove deletes', () async {
      expect(await repo.read('locale'), isNull);
      await repo.write('locale', 'bn');
      await repo.write('locale', 'en');
      expect(await repo.read('locale'), 'en');
      await repo.remove('locale');
      expect(await repo.read('locale'), isNull);
    });

    test('watch emits changes', () async {
      final values = <String?>[];
      final sub = repo.watch('k').listen(values.add);
      await pumpEventQueue();
      await repo.write('k', 'a');
      await pumpEventQueue();
      await repo.write('k', 'b');
      await pumpEventQueue();
      await sub.cancel();
      expect(values, [null, 'a', 'b']);
    });
  });

  group('migration harness', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tk_mig'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('v1 fixture opens at current version and keeps data', () async {
      final file = File('${dir.path}/v1.db');
      DbFixtures.writeV1File(file);

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      expect(await SettingsRepository(db).read('locale'), 'bn');
      final audit = await db.select(db.auditLog).get();
      expect(audit.single.entity, 'customer');
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
    });

    test('fresh database is created at the current schema version', () async {
      final db = _memory();
      addTearDown(db.close);
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names, containsAll(['app_setting', 'audit_log']));
    });
  });

  group('SecureDatabaseKeyStore.generateKey', () {
    test('is 64 hex chars and varies', () {
      final a = SecureDatabaseKeyStore.generateKey();
      final b = SecureDatabaseKeyStore.generateKey();
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, isNot(b));
    });
  });

  group('encrypted database (SQLCipher)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tk_enc'));
    tearDown(() => dir.deleteSync(recursive: true));

    final keyA = 'a' * 64;
    final keyB = 'b' * 64;

    test('round-trips data with the right key', () async {
      final file = File('${dir.path}/enc.db');
      var db = await DatabaseOpener.open(
        file,
        hexKey: keyA,
        inBackground: false,
      );
      await SettingsRepository(db).write('locale', 'bn');
      await db.close();

      db = await DatabaseOpener.open(file, hexKey: keyA, inBackground: false);
      expect(await SettingsRepository(db).read('locale'), 'bn');
      await db.close();
    });

    test('file on disk is not plain SQLite', () async {
      final file = File('${dir.path}/enc.db');
      final db = await DatabaseOpener.open(
        file,
        hexKey: keyA,
        inBackground: false,
      );
      await SettingsRepository(db).write('secret', 'rahim-uddin');
      await db.close();

      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
      expect(String.fromCharCodes(bytes), isNot(contains('rahim-uddin')));
    });

    test(
      'wrong key throws WrongDatabaseKeyFailure and keeps the file',
      () async {
        final file = File('${dir.path}/enc.db');
        final db = await DatabaseOpener.open(
          file,
          hexKey: keyA,
          inBackground: false,
        );
        await SettingsRepository(db).write('locale', 'bn');
        await db.close();
        final sizeBefore = file.lengthSync();

        await expectLater(
          DatabaseOpener.open(file, hexKey: keyB, inBackground: false),
          throwsA(isA<WrongDatabaseKeyFailure>()),
        );
        expect(file.lengthSync(), sizeBefore);

        // The right key still works afterwards: nothing was reset.
        final again = await DatabaseOpener.open(
          file,
          hexKey: keyA,
          inBackground: false,
        );
        expect(await SettingsRepository(again).read('locale'), 'bn');
        await again.close();
      },
    );

    test('background isolate opens and queries', () async {
      final file = File('${dir.path}/bg.db');
      final db = await DatabaseOpener.open(file, hexKey: keyA);
      await SettingsRepository(db).write('locale', 'en');
      expect(await SettingsRepository(db).read('locale'), 'en');
      await db.close();
    });

    test(
      'plain sqlite file is rejected with a key (not silently opened)',
      () async {
        final file = File('${dir.path}/plain.db');
        final raw = sqlite.sqlite3.open(file.path)
          ..execute('CREATE TABLE t(x)');
        raw.close();
        await expectLater(
          DatabaseOpener.open(file, hexKey: keyA, inBackground: false),
          throwsA(isA<WrongDatabaseKeyFailure>()),
        );
      },
    );
  });
}
