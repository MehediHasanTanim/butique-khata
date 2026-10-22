import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

/// Overridden in `bootstrap` with the opened, encrypted database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('appDatabaseProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => SystemClock());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Initial locale code read before `runApp` so the first frame is correct.
final initialLocaleCodeProvider = Provider<String>((ref) => 'en');

/// Runtime language switch, persisted in `app_setting` (S0-06).
class LocaleController extends Notifier<Locale> {
  static const supported = ['en', 'bn'];

  @override
  Locale build() => Locale(ref.watch(initialLocaleCodeProvider));

  Future<void> setLanguage(String code) async {
    if (!supported.contains(code)) return;
    state = Locale(code);
    await ref.read(settingsRepositoryProvider).write(SettingKeys.locale, code);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);

/// True when numbers should be rendered with Bangla digits.
final useBanglaDigitsProvider = Provider<bool>(
  (ref) => ref.watch(localeProvider).languageCode == 'bn',
);
