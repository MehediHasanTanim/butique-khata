import 'package:tailor_khata/core/time/clock.dart';

/// Preset kinds of busy season (E-1).
enum SeasonKind {
  eidFitr('eid_fitr'),
  eidAdha('eid_adha'),
  puja('puja'),
  pohelaBoishakh('pohela_boishakh'),
  wedding('wedding'),
  custom('custom');

  const SeasonKind(this.dbValue);

  final String dbValue;

  static SeasonKind fromDb(String value) => SeasonKind.values.firstWhere(
    (k) => k.dbValue == value,
    orElse: () => SeasonKind.custom,
  );
}

/// Weekday bits for [Season.workingDaysMask]: bit (weekday - 1), with Monday
/// = 1 … Sunday = 7 as in `DateTime.weekday`.
abstract class WorkingDays {
  static const int all = 127;

  static bool isWorking(int mask, int weekday) =>
      mask & (1 << (weekday - 1)) != 0;

  static int toggle(int mask, int weekday) => mask ^ (1 << (weekday - 1));
}

/// A busy period with a deadline and the shop's capacity for it.
class Season {
  const Season({
    required this.id,
    required this.name,
    required this.kind,
    required this.targetDate,
    required this.dailyCapacity,
    this.workingDaysMask = WorkingDays.all,
    this.closedDates = const {},
    this.active = true,
  });

  final String id;
  final String name;
  final SeasonKind kind;

  /// Everything must be ready by this day, `YYYY-MM-DD`.
  final String targetDate;

  /// Work units ×100 the shop gets through per working day.
  final int dailyCapacity;
  final int workingDaysMask;

  /// Dates the shop is closed, `YYYY-MM-DD`.
  final Set<String> closedDates;
  final bool active;

  /// Whole days from [today] to the target date (negative once passed).
  int daysLeft(String today) {
    final a = Clock.parseDate(today);
    final b = Clock.parseDate(targetDate);
    return DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  Season copyWith({
    String? name,
    SeasonKind? kind,
    String? targetDate,
    int? dailyCapacity,
    int? workingDaysMask,
    Set<String>? closedDates,
    bool? active,
  }) => Season(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    targetDate: targetDate ?? this.targetDate,
    dailyCapacity: dailyCapacity ?? this.dailyCapacity,
    workingDaysMask: workingDaysMask ?? this.workingDaysMask,
    closedDates: closedDates ?? this.closedDates,
    active: active ?? this.active,
  );
}
