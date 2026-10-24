import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// When to be reminded, whether notifications are allowed, and what to do if
/// the phone stops them (D-2, S4-06).
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await ref
        .read(notificationServiceProvider)
        .arePermissionsGranted();
    if (mounted) setState(() => _allowed = granted);
  }

  Future<void> _requestPermission() async {
    await ref.read(notificationServiceProvider).requestPermission();
    await _refreshPermission();
  }

  String _time(int minutes, bool bangla) {
    final text =
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    return DigitFormatter.format(text, bangla: bangla);
  }

  Future<int?> _pickTime(int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final reminders = settings.reminders;

    Widget timeTile(
      String label,
      int minutes,
      ReminderSettings Function(int) update,
      Key key,
    ) => ListTile(
      key: key,
      minTileHeight: 56,
      enabled: reminders.enabled,
      title: Text(label),
      trailing: Text(
        _time(minutes, bangla),
        style: theme.textTheme.titleMedium,
      ),
      onTap: () async {
        final picked = await _pickTime(minutes);
        if (picked != null) await controller.setReminders(update(picked));
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsReminders)),
      body: ListView(
        children: [
          SwitchListTile(
            key: const ValueKey('reminders-enabled'),
            title: Text(l10n.remindersOn),
            value: reminders.enabled,
            onChanged: (v) =>
                controller.setReminders(reminders.copyWith(enabled: v)),
          ),
          timeTile(
            l10n.remindersEvening,
            reminders.eveningMinutes,
            (m) => reminders.copyWith(eveningMinutes: m),
            const ValueKey('time-evening'),
          ),
          timeTile(
            l10n.remindersMorning,
            reminders.morningMinutes,
            (m) => reminders.copyWith(morningMinutes: m),
            const ValueKey('time-morning'),
          ),
          timeTile(
            l10n.remindersDigest,
            reminders.digestMinutes,
            (m) => reminders.copyWith(digestMinutes: m),
            const ValueKey('time-digest'),
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('uncollected-days'),
            minTileHeight: 56,
            title: Text(l10n.uncollectedAfter),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: settings.uncollectedDays > 1
                      ? () => controller.setUncollectedDays(
                          settings.uncollectedDays - 1,
                        )
                      : null,
                ),
                Text(
                  DigitFormatter.format(
                    '${settings.uncollectedDays}',
                    bangla: bangla,
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => controller.setUncollectedDays(
                    settings.uncollectedDays + 1,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('permission-status'),
            leading: Icon(
              _allowed == true
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: _allowed == true
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            title: Text(
              _allowed == true
                  ? l10n.notificationsAllowed
                  : l10n.notificationsBlocked,
            ),
            // Under the text, not beside it: a button with a long (Bangla or
            // large-text) label would otherwise fill the whole row.
            subtitle: _allowed == false
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton(
                        key: const ValueKey('permission-allow'),
                        onPressed: _requestPermission,
                        child: Text(l10n.notificationsAllow),
                      ),
                    ),
                  )
                : null,
          ),
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.battery_alert_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.batteryTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.batteryBody, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
