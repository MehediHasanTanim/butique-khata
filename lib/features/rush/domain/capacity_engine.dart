import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

/// Work still to do for garments promised on [date], in work units ×100.
class WorkLoad {
  const WorkLoad(this.date, this.units);

  final String date;
  final int units;
}

enum LoadLevel {
  /// Plenty of room.
  green,

  /// Less than a fifth of capacity to spare.
  amber,

  /// More promised than can be made in time.
  red,
}

/// How full the plan is up to and including one day (E-3).
class DayLoad {
  const DayLoad({
    required this.date,
    required this.isWorkingDay,
    required this.dueUnits,
    required this.capacityUnits,
    required this.cumulativeCapacity,
    required this.cumulativeDemand,
  });

  final String date;

  /// False on a weekly day off or a closed date.
  final bool isWorkingDay;

  /// Work promised for exactly this day.
  final int dueUnits;

  /// What the shop can make on this day.
  final int capacityUnits;

  /// Capacity from today up to and including this day.
  final int cumulativeCapacity;

  /// Work promised for this day or earlier (late orders count from today).
  final int cumulativeDemand;

  /// Spare capacity by the end of this day; negative means overbooked.
  int get slack => cumulativeCapacity - cumulativeDemand;

  LoadLevel get level {
    if (slack < 0) return LoadLevel.red;
    if (cumulativeDemand > 0 &&
        cumulativeCapacity > 0 &&
        slack / cumulativeCapacity < 0.2) {
      return LoadLevel.amber;
    }
    return LoadLevel.green;
  }
}

/// Capacity planning for a busy season (TD §5.6).
///
/// Work is made earliest-deadline-first, so everything promised for day `t`
/// or earlier must fit into the capacity available from today through `t`.
/// A garment is made *before* its due day, which is why the load of a day is
/// judged cumulatively rather than against that day's capacity alone.
///
/// One working lane today; per-worker lanes (v1.1) would add several
/// capacity series behind the same questions.
class CapacityEngine {
  CapacityEngine({required this.season, required this.today});

  final Season season;
  final String today;

  late final DateTime _start = _day(today);

  static DateTime _day(String date) {
    final d = Clock.parseDate(date);
    return DateTime.utc(d.year, d.month, d.day);
  }

  /// Days from today (0) to [date]; dates in the past are 0, because late
  /// work has to be done as soon as possible.
  int indexOf(String date) {
    final days = _day(date).difference(_start).inDays;
    return days < 0 ? 0 : days;
  }

  String dateAt(int index) {
    final d = _start.add(Duration(days: index));
    return Clock.toDateString(DateTime(d.year, d.month, d.day));
  }

  bool isWorkingDay(String date) {
    final weekday = _day(date).weekday;
    return WorkingDays.isWorking(season.workingDaysMask, weekday) &&
        !season.closedDates.contains(date);
  }

  /// Capacity of one day, ×100.
  int capacityOn(String date) => isWorkingDay(date) ? season.dailyCapacity : 0;

  /// The last day that matters: the target or the latest promise.
  int _horizon(List<WorkLoad> work, [int atLeast = 0]) {
    var h = indexOf(season.targetDate);
    if (atLeast > h) h = atLeast;
    for (final w in work) {
      final i = indexOf(w.date);
      if (i > h) h = i;
    }
    return h;
  }

  /// Per-day arrays up to [horizon]: due work and capacity.
  ({List<int> due, List<int> capacity}) _series(
    List<WorkLoad> work,
    int horizon,
  ) {
    final due = List<int>.filled(horizon + 1, 0);
    for (final w in work) {
      due[indexOf(w.date)] += w.units;
    }
    final capacity = [for (var i = 0; i <= horizon; i++) capacityOn(dateAt(i))];
    return (due: due, capacity: capacity);
  }

  /// Load of each day from today to the target date (inclusive).
  List<DayLoad> days(List<WorkLoad> work) {
    final horizon = _horizon(work);
    final s = _series(work, horizon);
    final last = indexOf(season.targetDate);
    final out = <DayLoad>[];
    var cumCap = 0;
    var cumDem = 0;
    for (var i = 0; i <= last; i++) {
      cumCap += s.capacity[i];
      cumDem += s.due[i];
      final date = dateAt(i);
      out.add(
        DayLoad(
          date: date,
          isWorkingDay: isWorkingDay(date),
          dueUnits: s.due[i],
          capacityUnits: s.capacity[i],
          cumulativeCapacity: cumCap,
          cumulativeDemand: cumDem,
        ),
      );
    }
    return out;
  }

  /// Capacity left by the target date after everything already promised;
  /// negative when the season is overbooked (E-6).
  int roomUnits(List<WorkLoad> work) {
    final horizon = _horizon(work);
    final s = _series(work, horizon);
    final last = indexOf(season.targetDate);
    var cap = 0;
    var dem = 0;
    for (var i = 0; i <= last; i++) {
      cap += s.capacity[i];
      dem += s.due[i];
    }
    return cap - dem;
  }

  /// Would adding [newUnits] due on [date] keep every deadline from then on
  /// achievable?
  bool isDateSafe(List<WorkLoad> work, int newUnits, String date) {
    final from = indexOf(date);
    final horizon = _horizon(work, from);
    final s = _series(work, horizon);
    var cap = 0;
    var dem = 0;
    for (var i = 0; i <= horizon; i++) {
      cap += s.capacity[i];
      dem += s.due[i];
      if (i >= from && dem + newUnits > cap) return false;
    }
    return true;
  }

  /// The earliest working day, at least [minLeadDays] from today and no
  /// later than the target date, to which [newUnits] of work can be promised
  /// without overbooking anything. Null when there is none.
  String? earliestSafeDate(
    List<WorkLoad> work,
    int newUnits, {
    int minLeadDays = 1,
  }) {
    final horizon = _horizon(work);
    final s = _series(work, horizon);
    final last = indexOf(season.targetDate);

    // Slack at the end of each day: capacity so far minus promises so far.
    final slack = List<int>.filled(horizon + 1, 0);
    var cap = 0;
    var dem = 0;
    for (var i = 0; i <= horizon; i++) {
      cap += s.capacity[i];
      dem += s.due[i];
      slack[i] = cap - dem;
    }
    // minSuffix[i] = the smallest slack from day i to the end, so a day is
    // safe exactly when that minimum can absorb the new work.
    final minSuffix = List<int>.filled(horizon + 2, 1 << 60);
    for (var i = horizon; i >= 0; i--) {
      minSuffix[i] = slack[i] < minSuffix[i + 1] ? slack[i] : minSuffix[i + 1];
    }
    for (var i = minLeadDays < 0 ? 0 : minLeadDays; i <= last; i++) {
      if (s.capacity[i] == 0) continue; // nobody is there to hand it over
      if (minSuffix[i] >= newUnits) return dateAt(i);
    }
    return null;
  }
}

/// How much of a garment's work is still to do for each stage.
abstract class StageProgress {
  /// Fraction ×100 of the work remaining for a garment in [status].
  static int remainingPercent(String status) => switch (status) {
    'received' => 100,
    'cut' => 80,
    'stitching' => 40,
    'finishing' => 20,
    _ => 0, // ready, delivered
  };

  /// Remaining work units for a garment of [units] in [status].
  static int remainingUnits(int units, String status) =>
      (units * remainingPercent(status) / 100).round();
}
