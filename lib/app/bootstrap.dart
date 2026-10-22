import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/app.dart';
import 'package:tailor_khata/app/error_boundary.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/db/database_opener.dart';
import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
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
  try {
    final db = await _openDatabase();
    final settings = SettingsRepository(db);
    final saved = await settings.read(SettingKeys.locale);
    runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
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

Future<AppDatabase> _openDatabase() async {
  final key = await SecureDatabaseKeyStore().loadOrCreateKey();
  final file = await DatabaseOpener.defaultFile();
  return DatabaseOpener.open(file, hexKey: key);
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
