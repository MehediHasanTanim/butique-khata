import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/settings/data/app_settings.dart';
import 'package:tailor_khata/features/settings/data/settings_repository.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = memoryDb();
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('a fresh database gives the defaults', () async {
    final s = await AppSettings.load(repo);
    expect(s.shopName, '');
    expect(s.reminders, const ReminderSettings());
    expect(s.reminders.enabled, isTrue);
    expect(s.reminders.eveningMinutes, 19 * 60);
    expect(s.reminders.morningMinutes, 8 * 60);
    expect(s.reminders.digestMinutes, 9 * 60);
    expect(s.templates, isEmpty);
    expect(s.uncollectedDays, 3);
  });

  test('stored values are read back', () async {
    await repo.write(AppSettingKeys.shopName, 'Noor Tailors');
    await repo.write(AppSettingKeys.reminderEnabled, 'false');
    await repo.write(AppSettingKeys.reminderEvening, '1230');
    await repo.write(AppSettingKeys.uncollectedDays, '5');
    await repo.write(MessageKind.due.settingKey, 'Pay up {name}');
    final s = await AppSettings.load(repo);
    expect(s.shopName, 'Noor Tailors');
    expect(s.reminders.enabled, isFalse);
    expect(s.reminders.eveningMinutes, 1230);
    expect(s.uncollectedDays, 5);
    expect(s.templates, {MessageKind.due: 'Pay up {name}'});
  });

  test('garbage values fall back safely', () async {
    await repo.write(AppSettingKeys.reminderEvening, 'noon');
    await repo.write(AppSettingKeys.reminderMorning, '99999');
    await repo.write(AppSettingKeys.reminderDigest, '-5');
    await repo.write(AppSettingKeys.uncollectedDays, '0');
    await repo.write(MessageKind.ready.settingKey, '   ');
    final s = await AppSettings.load(repo);
    expect(s.reminders, const ReminderSettings());
    expect(s.uncollectedDays, 1, reason: 'clamped to at least a day');
    expect(s.templates, isEmpty, reason: 'blank wording means standard');
  });

  test('templateFor prefers edited wording over the standard text', () {
    const s = AppSettings(templates: {MessageKind.ready: 'Mine'});
    expect(s.templateFor(MessageKind.ready, 'en'), 'Mine');
    expect(
      s.templateFor(MessageKind.due, 'bn'),
      MessageTemplates.defaultFor(MessageKind.due, 'bn'),
    );
  });
}
