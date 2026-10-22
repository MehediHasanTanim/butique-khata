import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/external_launcher.dart';
import 'package:tailor_khata/core/services/file_sharer.dart';
import 'package:tailor_khata/core/services/notification_service.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/features/deliveries/data/reminder_sync.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/settings/data/app_settings.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

// Platform services. Each can be replaced in tests (or in `bootstrap`).

/// Overridden in `bootstrap` with the initialized service.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NoopNotificationService(),
);

final externalLauncherProvider = Provider<ExternalLauncher>(
  (ref) => const UrlLauncher(),
);

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const SharePlusFileSharer(),
);

final photoSourceProvider = Provider<PhotoSource>((ref) => ImagePickerSource());

/// Overridden in `bootstrap` with the real store.
final mediaStoreProvider = Provider<MediaStore>(
  (ref) => throw StateError('mediaStoreProvider must be overridden'),
);

// App-wide settings (shop name, reminders, message wording).

/// Settings read before `runApp`, so the first frame already uses them.
final initialAppSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> setShopName(String name) async {
    final clean = name.trim();
    state = state.copyWith(shopName: clean);
    await _repo.write(AppSettingKeys.shopName, clean);
  }

  Future<void> setReminders(ReminderSettings value) async {
    state = state.copyWith(reminders: value);
    await _repo.write(AppSettingKeys.reminderEnabled, '${value.enabled}');
    await _repo.write(
      AppSettingKeys.reminderEvening,
      '${value.eveningMinutes}',
    );
    await _repo.write(
      AppSettingKeys.reminderMorning,
      '${value.morningMinutes}',
    );
    await _repo.write(AppSettingKeys.reminderDigest, '${value.digestMinutes}');
  }

  /// Saves edited wording; a blank [text] goes back to the standard one.
  Future<void> setTemplate(MessageKind kind, String text) async {
    final next = Map.of(state.templates);
    if (text.trim().isEmpty) {
      next.remove(kind);
      await _repo.remove(kind.settingKey);
    } else {
      next[kind] = text;
      await _repo.write(kind.settingKey, text);
    }
    state = state.copyWith(templates: next);
  }

  Future<void> setUncollectedDays(int days) async {
    final clamped = days.clamp(1, 60);
    state = state.copyWith(uncollectedDays: clamped);
    await _repo.write(AppSettingKeys.uncollectedDays, '$clamped');
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// Rebuilds the scheduled reminders from the current orders (D-2).
final reminderSyncProvider = Provider<ReminderSync>(
  (ref) => ReminderSync(
    orders: ref.watch(orderRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
    clock: ref.watch(clockProvider),
    settings: () => ref.read(appSettingsProvider).reminders,
    text: () {
      final l10n = lookupAppL10n(ref.read(localeProvider));
      return (ReminderKind kind, int count) => (
        title: switch (kind) {
          ReminderKind.eveningBefore => l10n.reminderEveningTitle(count),
          ReminderKind.morningOf => l10n.reminderMorningTitle(count),
          ReminderKind.overdueDigest => l10n.reminderOverdueTitle(count),
        },
        body: l10n.reminderBody,
      );
    },
  ),
);
