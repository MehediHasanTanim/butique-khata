import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

/// Keys for settings added after the language one.
abstract class AppSettingKeys {
  static const shopName = 'shop.name';
  static const reminderEnabled = 'reminder.enabled';
  static const reminderEvening = 'reminder.evening';
  static const reminderMorning = 'reminder.morning';
  static const reminderDigest = 'reminder.digest';
  static const uncollectedDays = 'uncollected.days';
}

/// Shop-wide preferences read at startup and changed in Settings.
class AppSettings {
  const AppSettings({
    this.shopName = '',
    this.reminders = const ReminderSettings(),
    this.templates = const {},
    this.uncollectedDays = 3,
  });

  /// Printed on slips and messages.
  final String shopName;
  final ReminderSettings reminders;

  /// Wording the owner edited; kinds not in the map use the built-in text.
  final Map<MessageKind, String> templates;

  /// A garment ready this long without being collected is "uncollected".
  final int uncollectedDays;

  AppSettings copyWith({
    String? shopName,
    ReminderSettings? reminders,
    Map<MessageKind, String>? templates,
    int? uncollectedDays,
  }) => AppSettings(
    shopName: shopName ?? this.shopName,
    reminders: reminders ?? this.reminders,
    templates: templates ?? this.templates,
    uncollectedDays: uncollectedDays ?? this.uncollectedDays,
  );

  /// Template text for [kind]: the edited one, or the built-in wording.
  String templateFor(MessageKind kind, String languageCode) =>
      templates[kind] ?? MessageTemplates.defaultFor(kind, languageCode);

  /// Reads every setting from the database.
  static Future<AppSettings> load(SettingsRepository repo) async {
    int minutes(String? raw, int fallback) {
      final value = int.tryParse(raw ?? '');
      return (value == null || value < 0 || value >= 24 * 60)
          ? fallback
          : value;
    }

    const defaults = ReminderSettings();
    final templates = <MessageKind, String>{};
    for (final kind in MessageKind.values) {
      final text = await repo.read(kind.settingKey);
      if (text != null && text.trim().isNotEmpty) templates[kind] = text;
    }
    return AppSettings(
      shopName: await repo.read(AppSettingKeys.shopName) ?? '',
      reminders: ReminderSettings(
        enabled: (await repo.read(AppSettingKeys.reminderEnabled)) != 'false',
        eveningMinutes: minutes(
          await repo.read(AppSettingKeys.reminderEvening),
          defaults.eveningMinutes,
        ),
        morningMinutes: minutes(
          await repo.read(AppSettingKeys.reminderMorning),
          defaults.morningMinutes,
        ),
        digestMinutes: minutes(
          await repo.read(AppSettingKeys.reminderDigest),
          defaults.digestMinutes,
        ),
      ),
      templates: templates,
      uncollectedDays:
          (int.tryParse(
                    await repo.read(AppSettingKeys.uncollectedDays) ?? '',
                  ) ??
                  3)
              .clamp(1, 60),
    );
  }
}
