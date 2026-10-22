import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/services/notification_service.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';

/// Rebuilds the scheduled notifications from the current orders (D-2).
///
/// Run at app start and whenever orders, reminder settings or the language
/// change. The schedule is replaced as a whole, so it can never drift from
/// the database; the dashboard remains the source of truth either way.
class ReminderSync {
  ReminderSync({
    required this.orders,
    required this.notifications,
    required this.clock,
    required this.settings,
    required this.text,
  });

  final OrderRepository orders;
  final NotificationService notifications;
  final Clock clock;
  final ReminderSettings Function() settings;
  final ReminderText Function() text;

  /// The most recent plan, for inspection.
  List<PlannedNotification> lastPlan = const [];

  Future<void> sync() async {
    final days = await orders.watchOpenDeliveryDays().first;
    lastPlan = planReminders(
      days: days,
      now: clock.now(),
      settings: settings(),
      text: text(),
    );
    try {
      await notifications.replaceAll(lastPlan);
      AppLog.d('reminders', 'Scheduled ${lastPlan.length} notifications');
    } on Object catch (error) {
      AppLog.e('reminders', 'Could not schedule', error);
    }
  }
}
