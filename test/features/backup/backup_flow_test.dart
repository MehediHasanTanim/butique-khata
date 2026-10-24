import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/features/backup/data/backup_key_store.dart';
import 'package:tailor_khata/features/backup/data/backup_service.dart';
import 'package:tailor_khata/features/backup/presentation/backup_providers.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

import '../../support/backup_fixture.dart';
import '../../support/shop_fixture.dart';
import '../../support/test_app.dart';

const passphrase = 'blue-mango-7-tailor';
final deviceKey = 'c' * 64;

class FakePicker implements BackupFilePicker {
  File? next;
  int picks = 0;

  @override
  Future<File?> pick() async {
    picks++;
    return next;
  }
}

void main() {
  late Directory tmp;
  late InMemoryBackupKeyStore keys;
  late FakePicker picker;
  late int restarts;

  File backupFileOnDisk(int i) =>
      Directory('${tmp.path}/backups')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tkbackup'))
          .toList()
          .elementAt(i);
  int backupCount() => Directory('${tmp.path}/backups').existsSync()
      ? Directory('${tmp.path}/backups')
            .listSync()
            .where((f) => f.path.endsWith('.tkbackup'))
            .length
      : 0;

  /// Opens the app with backups switched on, on a fresh temporary phone.
  Future<void> openBackup(
    WidgetTester tester, {
    String route = AppRoutes.backup,
    String locale = 'en',
    bool withKey = false,
    bool autoOff = true,
    DateTime? lastBackup,
  }) async {
    tmp = Directory.systemTemp.createTempSync('tk_backup_ui');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    keys = InMemoryBackupKeyStore();
    picker = FakePicker();
    restarts = 0;
    if (withKey) {
      final key = await tester.runAsync(
        () =>
            BackupCrypto.deriveKey(passphrase, params: KdfParams.fastForTests),
      );
      await keys.save(key!);
    }
    await openShop(
      tester,
      route,
      locale: locale,
      extra: () async {
        final settings = SettingsRepository(shopDb);
        if (autoOff) {
          await settings.write(BackupService.keyAutoEnabled, 'false');
        }
        if (lastBackup != null) {
          await settings.write(
            BackupService.keyLastAt,
            '${lastBackup.millisecondsSinceEpoch}',
          );
        }
      },
      overrides: <Override>[
        backupEnvironmentProvider.overrideWithValue(
          BackupEnvironment(
            backupDir: Directory('${tmp.path}/backups'),
            mediaDir: Directory('${tmp.path}/media'),
            dbFile: File('${tmp.path}/live.db'),
            deviceKeyHex: deviceKey,
            useIsolate: false,
          ),
        ),
        backupKdfParamsProvider.overrideWithValue(KdfParams.fastForTests),
        backupKeyStoreProvider.overrideWithValue(keys),
        backupFilePickerProvider.overrideWithValue(picker),
        appRestartProvider.overrideWithValue(() => restarts++),
      ],
    );
  }

  /// Waits until the screen lists the backup that was just made.
  Future<void> backupListed(WidgetTester tester) => settleIo(
    tester,
    until: () =>
        find.byKey(const ValueKey('backup-file-0')).evaluate().isNotEmpty,
  );

  Future<void> setPassphrase(WidgetTester tester, String value) async {
    await tester.enterText(
      find.byKey(const ValueKey('passphrase-field')),
      value,
    );
    await tester.enterText(
      find.byKey(const ValueKey('passphrase-confirm')),
      value,
    );
    await tester.tap(find.byKey(const ValueKey('passphrase-save')));
    await settleIo(tester);
  }

  group('set up (S6-02)', () {
    testWidgets('nothing can be backed up until a passphrase exists', (
      tester,
    ) async {
      await openBackup(tester);
      expect(find.text('Not backed up yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('backup-set-passphrase')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('backup-now')), findsNothing);
      expect(find.byKey(const ValueKey('backup-restore')), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('the passphrase must be long enough and typed twice', (
      tester,
    ) async {
      await openBackup(tester);
      await tapKeyed(tester, 'backup-set-passphrase');
      await tester.enterText(
        find.byKey(const ValueKey('passphrase-field')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey('passphrase-save')));
      await tester.pump();
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('passphrase-field')),
        'long-enough-1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passphrase-confirm')),
        'long-enough-2',
      );
      await tester.tap(find.byKey(const ValueKey('passphrase-save')));
      await tester.pump();
      expect(find.text('The two do not match'), findsOneWidget);
      expect(await keys.load(), isNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('a passphrase can be made for you', (tester) async {
      await openBackup(tester);
      await tapKeyed(tester, 'backup-set-passphrase');
      await tester.tap(find.byKey(const ValueKey('passphrase-generate')));
      await tester.pump();
      final first = tester
          .widget<TextFormField>(find.byKey(const ValueKey('passphrase-field')))
          .controller!
          .text;
      final second = tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('passphrase-confirm')),
          )
          .controller!
          .text;
      expect(first, second);
      expect(first, matches(RegExp(r'^([a-z2-9]{4}-){4}[a-z2-9]{4}$')));
      await tester.tap(find.byKey(const ValueKey('passphrase-save')));
      await settleIo(tester);
      expect(await keys.load(), isNotNull);
      await shutDown(tester, shopDb);
    });

    testWidgets('after setting it, backing up is offered', (tester) async {
      await openBackup(tester);
      await tapKeyed(tester, 'backup-set-passphrase');
      await setPassphrase(tester, passphrase);
      expect(find.byKey(const ValueKey('backup-now')), findsOneWidget);
      expect(find.byKey(const ValueKey('backup-set-passphrase')), findsNothing);
      await shutDown(tester, shopDb);
    });
  });

  group('back up now (S6-01)', () {
    testWidgets('makes a file, lists it and records the time', (tester) async {
      await openBackup(tester, withKey: true);
      expect(find.text('No backups yet'), findsOneWidget);

      await tapNoSettle(tester, 'backup-now');
      await backupListed(tester);

      expect(backupCount(), 1);
      expect(find.text('No backups yet'), findsNothing);
      expect(find.byKey(const ValueKey('backup-file-0')), findsOneWidget);
      expect(find.textContaining('Last backup:'), findsOneWidget);
      expect(find.textContaining('Backup saved'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a copy can be shared to keep somewhere else', (tester) async {
      await openBackup(tester, withKey: true);
      await tapNoSettle(tester, 'backup-now');
      await backupListed(tester);

      await tapKeyed(tester, 'backup-share-0');
      expect(env.sharer.sharedPaths, [backupFileOnDisk(0).path]);
      await shutDown(tester, shopDb);
    });

    testWidgets('automatic backup can be switched off and on', (tester) async {
      await openBackup(tester, withKey: true, autoOff: false);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('backup-auto')))
            .value,
        isTrue,
      );
      await tapKeyed(tester, 'backup-auto');
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('backup-auto')))
            .value,
        isFalse,
      );
      expect(
        await tester.runAsync(
          () => SettingsRepository(shopDb).read(BackupService.keyAutoEnabled),
        ),
        'false',
      );
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla labels and digits', (tester) async {
      await openBackup(tester, locale: 'bn', withKey: true);
      expect(find.text('ব্যাকআপ ও রিস্টোর'), findsOneWidget);
      expect(find.text('এখনই ব্যাকআপ নিন'), findsOneWidget);
      await tapNoSettle(tester, 'backup-now');
      await backupListed(tester);
      expect(find.textContaining('ব্যাকআপ সংরক্ষিত'), findsOneWidget);
      expect(find.textContaining('KB'), findsWidgets);
      await shutDown(tester, shopDb);
    });
  });

  group('automatic backup (S6-03)', () {
    testWidgets('runs when the app opens and a backup is due', (tester) async {
      await openBackup(
        tester,
        route: AppRoutes.home,
        withKey: true,
        autoOff: false,
      );
      await settleIo(tester, until: () => backupCount() == 1);
      expect(backupCount(), 1);
      await shutDown(tester, shopDb);
    });

    testWidgets('does not run when switched off', (tester) async {
      await openBackup(tester, route: AppRoutes.home, withKey: true);
      await settleIo(tester, rounds: 5);
      expect(backupCount(), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('does not run without a passphrase', (tester) async {
      await openBackup(tester, route: AppRoutes.home, autoOff: false);
      await settleIo(tester, rounds: 5);
      expect(backupCount(), 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('runs again when the app returns after a day', (tester) async {
      await openBackup(
        tester,
        route: AppRoutes.home,
        withKey: true,
        autoOff: false,
      );
      await settleIo(tester, until: () => backupCount() == 1);
      env.clock.advance(const Duration(hours: 25));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIo(tester, until: () => backupCount() == 2);
      expect(backupCount(), 2);
      await shutDown(tester, shopDb);
    });
  });

  group('the Home warning (S6-03)', () {
    final banner = find.byKey(const ValueKey('backup-banner'));

    testWidgets('never backed up', (tester) async {
      await openBackup(tester, route: AppRoutes.home);
      expect(banner, findsOneWidget);
      expect(find.text('Your data is not backed up yet'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a week without a backup', (tester) async {
      await openBackup(
        tester,
        route: AppRoutes.home,
        withKey: true,
        lastBackup: DateTime(2026, 3, 2, 9),
      );
      expect(find.text('No backup for 8 days'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets('a recent backup shows nothing', (tester) async {
      await openBackup(
        tester,
        route: AppRoutes.home,
        withKey: true,
        lastBackup: DateTime(2026, 3, 8, 9),
      );
      expect(banner, findsNothing);
      await shutDown(tester, shopDb);
    });

    testWidgets('Bangla digits in Bangla', (tester) async {
      await openBackup(
        tester,
        route: AppRoutes.home,
        locale: 'bn',
        withKey: true,
        lastBackup: DateTime(2026, 3, 2, 9),
      );
      expect(find.text('৮ দিন ব্যাকআপ নেওয়া হয়নি'), findsOneWidget);
      await shutDown(tester, shopDb);
    });

    testWidgets(
      'tapping it opens the backup screen, and backing up clears it',
      (tester) async {
        await openBackup(tester, route: AppRoutes.home, withKey: true);
        await tester.tap(banner);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('backup-now')), findsOneWidget);

        await tapNoSettle(tester, 'backup-now');
        await backupListed(tester);
        await tester.pageBack();
        await settleIo(tester, until: () => banner.evaluate().isEmpty);
        expect(banner, findsNothing);
        await shutDown(tester, shopDb);
      },
    );

    testWidgets('no banner when the app has no backup support', (tester) async {
      await openShop(tester, AppRoutes.home);
      expect(banner, findsNothing);
      await shutDown(tester, shopDb);
    });
  });

  group('restore on another phone (S6-04)', () {
    late Phone oldPhone;
    late File backup;

    setUp(() async {});

    Future<void> makeBackupOnOldPhone(WidgetTester tester) async {
      await tester.runAsync(() async {
        oldPhone = await Phone.create(keyChar: 'a');
        await oldPhone.seed();
        final service = oldPhone.service();
        await service.setPassphrase(passphrase);
        backup = (await service.createBackup()).file;
      });
      addTearDown(() async => oldPhone.dispose());
    }

    Future<void> restoreFlow(
      WidgetTester tester, {
      String pass = passphrase,
    }) async {
      picker.next = backup;
      await tapKeyed(tester, 'backup-restore');
      await tester.enterText(
        find.byKey(const ValueKey('restore-passphrase')),
        pass,
      );
      await tester.tap(find.byKey(const ValueKey('restore-passphrase-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Replace all data on this phone?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pump();
    }

    testWidgets('customers, measurements and everything else arrive', (
      tester,
    ) async {
      await openBackup(tester);
      await makeBackupOnOldPhone(tester);
      await restoreFlow(tester);
      expect(find.text('Restoring… please wait'), findsOneWidget);
      await settleIo(
        tester,
        until: () =>
            find.byKey(const ValueKey('restore-done')).evaluate().isNotEmpty,
      );

      expect(
        find.textContaining('Restored 2 customers and 3 measurements'),
        findsOneWidget,
      );
      expect(restarts, 0, reason: 'the app restarts after the message is read');
      await tester.tap(find.byKey(const ValueKey('restore-done')));
      await tester.pumpAndSettle();
      expect(restarts, 1);

      // The database file now on this phone opens with this phone's key and
      // holds the other phone's shop.
      final restored = await tester.runAsync(
        () => DatabaseOpener.open(
          File('${tmp.path}/live.db'),
          hexKey: deviceKey,
          inBackground: false,
        ),
      );
      final customers = await tester.runAsync(
        () => restored!.select(restored.customer).get(),
      );
      expect(customers, hasLength(3));
      final sets = await tester.runAsync(
        () => restored!.select(restored.measurementSet).get(),
      );
      expect(sets, hasLength(3));
      await tester.runAsync(restored!.close);
      await shutDown(tester, shopDb);
    });

    testWidgets('a wrong passphrase says so and changes nothing', (
      tester,
    ) async {
      await openBackup(tester);
      await makeBackupOnOldPhone(tester);
      await restoreFlow(tester, pass: 'not the one');
      await settleIo(
        tester,
        until: () =>
            find.textContaining('Wrong passphrase').evaluate().isNotEmpty,
      );

      expect(find.textContaining('Wrong passphrase'), findsOneWidget);
      expect(
        find.textContaining('Nothing on this phone was touched'),
        findsOneWidget,
      );
      expect(restarts, 0);
      expect(File('${tmp.path}/live.db').existsSync(), isFalse);
      // The shop on this phone is still there and still open.
      final customers = await tester.runAsync(
        () => shopDb.select(shopDb.customer).get(),
      );
      expect(customers, hasLength(2));
      await shutDown(tester, shopDb);
    });

    testWidgets('something that is not a backup', (tester) async {
      await openBackup(tester);
      final junk = File('${tmp.path}/photo.jpg')
        ..writeAsBytesSync(List.filled(300, 7));
      picker.next = junk;
      await tapKeyed(tester, 'backup-restore');
      await tester.enterText(
        find.byKey(const ValueKey('restore-passphrase')),
        passphrase,
      );
      await tester.tap(find.byKey(const ValueKey('restore-passphrase-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await settleIo(
        tester,
        until: () => find
            .text('This is not a Tailor Khata backup')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('This is not a Tailor Khata backup'), findsOneWidget);
      expect(restarts, 0);
      await shutDown(tester, shopDb);
    });

    testWidgets('cancelling at any step does nothing', (tester) async {
      await openBackup(tester);
      await makeBackupOnOldPhone(tester);

      // No file chosen.
      await tapKeyed(tester, 'backup-restore');
      expect(find.byKey(const ValueKey('restore-passphrase')), findsNothing);

      // File chosen, passphrase dialog cancelled.
      picker.next = backup;
      await tapKeyed(tester, 'backup-restore');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Replace all data on this phone?'), findsNothing);

      // Last warning cancelled.
      await tapKeyed(tester, 'backup-restore');
      await tester.enterText(
        find.byKey(const ValueKey('restore-passphrase')),
        passphrase,
      );
      await tester.tap(find.byKey(const ValueKey('restore-passphrase-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(restarts, 0);
      expect(File('${tmp.path}/live.db').existsSync(), isFalse);
      await shutDown(tester, shopDb);
    });
  });
}
