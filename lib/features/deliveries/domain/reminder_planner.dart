import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';

enum ReminderKind {
  /// The evening before a delivery day.
  eveningBefore,

  /// The morning of a delivery day.
  morningOf,

  /// Daily nudge while deliveries are overdue.
  overdueDigest,
}

/// When the tailor wants to be reminded (S4-06). Times are minutes after
/// midnight.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.eveningMinutes = 19 * 60,
    this.morningMinutes = 8 * 60,
    this.digestMinutes = 9 * 60,
  });

  final bool enabled;
  final int eveningMinutes;
  final int morningMinutes;
  final int digestMinutes;

  ReminderSettings copyWith({
    bool? enabled,
    int? eveningMinutes,
    int? morningMinutes,
    int? digestMinutes,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    eveningMinutes: eveningMinutes ?? this.eveningMinutes,
    morningMinutes: morningMinutes ?? this.morningMinutes,
    digestMinutes: digestMinutes ?? this.digestMinutes,
  );

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.eveningMinutes == eveningMinutes &&
      other.morningMinutes == morningMinutes &&
      other.digestMinutes == digestMinutes;

  @override
  int get hashCode =>
      Object.hash(enabled, eveningMinutes, morningMinutes, digestMinutes);
}

/// One local notification to schedule.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// App route opened when the notification is tapped.
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is PlannedNotification &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, at, title, body, payload);

  @override
  String toString() => 'PlannedNotification($id, $at, $title)';
}

/// Wording provider so the planner stays free of localization code.
typedef ReminderText = ({String title, String body}) Function(
  ReminderKind kind,
  int count,
);

/// Decides which notifications should exist (D-2, D-4). Pure: give it the
/// open delivery days and "now" and it returns the full schedule; callers
/// replace whatever was scheduled before. Deliveries on the same day are
/// grouped into one notification so a busy week does not spam.
List<PlannedNotification> planReminders({
  required List<DeliveryDay> days,
  required DateTime now,
  required ReminderSettings settings,
  required ReminderText text,
  int maxCount = 60,
  int digestDays = 7,
}) {
  if (!settings.enabled) return const [];
  final today = Clock.toDateString(now);

  DateTime at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, 0, minutes);

  String route(DeliveryDay day, String tab) =>
      day.count == 1 ? '/order/${day.firstOrderId}' : '/deliveries?tab=$tab';

  int idFor(ReminderKind kind, String date) =>
      Object.hash(kind.name, date) & 0x3fffffff;

  final planned = <PlannedNotification>[];

  void add(
    ReminderKind kind,
    String dateKey,
    DateTime time,
    int count,
    String payload,
  ) {
    if (!time.isAfter(now)) return;
    final words = text(kind, count);
    planned.add(
      PlannedNotification(
        id: idFor(kind, dateKey),
        at: time,
        title: words.title,
        body: words.body,
        payload: payload,
      ),
    );
  }

  var overdue = 0;
  for (final day in days) {
    if (day.date.compareTo(today) < 0) {
      overdue += day.count;
      continue;
    }
    final date = Clock.parseDate(day.date);
    add(
      ReminderKind.morningOf,
      day.date,
      at(date, settings.morningMinutes),
      day.count,
      route(day, 'today'),
    );
    add(
      ReminderKind.eveningBefore,
      day.date,
      at(
        DateTime(date.year, date.month, date.day - 1),
        settings.eveningMinutes,
      ),
      day.count,
      route(day, 'tomorrow'),
    );
  }

  if (overdue > 0) {
    final start = Clock.parseDate(today);
    for (var i = 0; i < digestDays; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      add(
        ReminderKind.overdueDigest,
        Clock.toDateString(day),
        at(day, settings.digestMinutes),
        overdue,
        '/deliveries?tab=overdue',
      );
    }
  }

  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned.take(maxCount).toList();
}
