import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tailor_khata/app/app.dart';
import 'package:tailor_khata/app/error_boundary.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/notification_service.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/backup/presentation/backup_providers.dart';
import 'package:tailor_khata/features/security/data/lock_store.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';
import 'package:tailor_khata/features/settings/data/app_settings.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

enum Flavor { dev, prod }

/// Entry point shared by every flavor.
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorBoundary.install();
  ErrorBoundary.run(() => _launch(flavor));
}

Future<void> _launch(Flavor flavor) async {
  AppLog.i('boot', 'Starting ${flavor.name}');
  // Date names for every locale, available before any widget builds.
  await initializeDateFormatting();
  try {
    final key = await SecureDatabaseKeyStore().loadOrCreateKey();
    final dbFile = await DatabaseOpener.defaultFile();
    final db = await DatabaseOpener.open(dbFile, hexKey: key);
    final settings = SettingsRepository(db);
    final saved = await settings.read(SettingKeys.locale);
    final appSettings = await AppSettings.load(settings);
    final media = await FileMediaStore.inAppSupport();
    final notifications = await _startNotifications();
    final lockStore = SecureLockStore();
    final lockConfig = await lockStore.load();
    final supportDir = await getApplicationSupportDirectory();
    final documentsDir = await getApplicationDocumentsDirectory();
    runApp(
      ProviderScope(
        // A new key makes a restart (after a restore) build a fresh tree.
        key: UniqueKey(),
        overrides: [
          backupEnvironmentProvider.overrideWithValue(
            BackupEnvironment(
              backupDir: Directory(p.join(documentsDir.path, 'backups')),
              mediaDir: Directory(p.join(supportDir.path, 'media')),
              dbFile: dbFile,
              deviceKeyHex: key,
            ),
          ),
          appRestartProvider.overrideWithValue(() => _launch(flavor)),
          lockStoreProvider.overrideWithValue(lockStore),
          initialLockConfigProvider.overrideWithValue(lockConfig),
          appDatabaseProvider.overrideWithValue(db),
          initialAppSettingsProvider.overrideWithValue(appSettings),
          mediaStoreProvider.overrideWithValue(media),
          notificationServiceProvider.overrideWithValue(notifications),
          initialLocaleCodeProvider.overrideWithValue(
            LocaleController.supported.contains(saved) ? saved! : 'en',
          ),
        ],
        child: const TailorKhataApp(),
      ),
    );
  } on Failure catch (failure) {
    runApp(StartupErrorApp(failure: failure, onRetry: () => _launch(flavor)));
  }
}

/// Notifications are a convenience: if setup fails the app still works.
Future<NotificationService> _startNotifications() async {
  final service = LocalNotificationService();
  try {
    await service.init();
    return service;
  } on Object catch (error) {
    AppLog.e('boot', 'Notifications unavailable', error);
    return NoopNotificationService();
  }
}

/// Shown instead of the app when the database cannot be opened. Never
/// deletes or resets data (Spec: losing history is the worst failure).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    required this.failure,
    required this.onRetry,
    super.key,
  });

  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      theme: AppTheme.light(const Locale('en')),
      home: Builder(
        builder: (context) {
          final l10n = AppL10n.of(context);
          return Scaffold(
            body: SafeArea(
              child: EmptyState(
                icon: Icons.lock_outline,
                title: l10n.startupErrorTitle,
                body: failure.code == 'db.wrong_key'
                    ? '${l10n.startupErrorWrongKey}\n\n${l10n.startupErrorBody}'
                    : l10n.startupErrorBody,
                action: PrimaryButton(
                  label: l10n.actionRetry,
                  onPressed: onRetry,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
